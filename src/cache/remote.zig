const std = @import("std");
const types = @import("../config/types.zig");

/// Remote cache client (Phase 7 — PRD §5.7.3).
/// Supports S3, GCS, Azure, and HTTP backends.
pub const RemoteCache = struct {
    config: types.RemoteCacheConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: types.RemoteCacheConfig) RemoteCache {
        return .{
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RemoteCache) void {
        _ = self;
    }

    /// Pull a cache entry from remote. Returns cached data or null if not found.
    /// Caller owns returned memory.
    pub fn pull(self: *const RemoteCache, key: []const u8) !?[]u8 {
        return switch (self.config.type) {
            .http => try self.pullHTTP(key),
            .s3 => try self.pullS3(key),
            .gcs => try self.pullGCS(key),
            .azure => try self.pullAzure(key),
        };
    }

    /// Push a cache entry to remote.
    pub fn push(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        return switch (self.config.type) {
            .http => try self.pushHTTP(key, data),
            .s3 => try self.pushS3(key, data),
            .gcs => try self.pushGCS(key, data),
            .azure => try self.pushAzure(key, data),
        };
    }

    // ─── HTTP Backend ───────────────────────────────────────────────────────

    fn pullHTTP(self: *const RemoteCache, key: []const u8) !?[]u8 {
        const url_base = self.config.url orelse return error.MissingURL;
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ url_base, key });
        defer self.allocator.free(url);

        // Use curl for HTTP GET (std.http.Client has limitations in Zig 0.15)
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s"); // silent
        try argv.append(self.allocator, "-f"); // fail on HTTP errors (404 → exit 22)
        if (self.config.auth) |auth| {
            const header = try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth});
            defer self.allocator.free(header);
            try argv.append(self.allocator, "-H");
            try argv.append(self.allocator, header);
        }
        try argv.append(self.allocator, url);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch return null;
        defer self.allocator.free(result.stderr);

        // exit 22 = HTTP 404 (cache miss)
        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return null;
        }

        return result.stdout; // Caller owns
    }

    fn pushHTTP(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        const url_base = self.config.url orelse return error.MissingURL;
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ url_base, key });
        defer self.allocator.free(url);

        // Write data to temp file for curl upload
        const tmp_path = try std.fmt.allocPrint(self.allocator, "/tmp/zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_path);
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        defer std.fs.cwd().deleteFile(tmp_path) catch {};
        try file.writeAll(data);

        // Use curl for HTTP PUT
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s"); // silent
        try argv.append(self.allocator, "-f"); // fail on HTTP errors
        try argv.append(self.allocator, "-X");
        try argv.append(self.allocator, "PUT");
        if (self.config.auth) |auth| {
            const header = try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth});
            defer self.allocator.free(header);
            try argv.append(self.allocator, "-H");
            try argv.append(self.allocator, header);
        }
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "Content-Type: application/octet-stream");
        try argv.append(self.allocator, "--data-binary");
        const data_arg = try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_path});
        defer self.allocator.free(data_arg);
        try argv.append(self.allocator, data_arg);
        try argv.append(self.allocator, url);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.RemoteCacheFailed;
        }
    }

    // ─── S3 Backend ─────────────────────────────────────────────────────────

    /// AWS Signature v4 signing for S3 requests.
    /// Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
    fn signS3Request(
        self: *const RemoteCache,
        method: []const u8,
        url_path: []const u8,
        date_iso: []const u8,
        date_stamp: []const u8,
        payload_hash: []const u8,
    ) ![]const u8 {
        const region = self.config.region orelse "us-east-1";

        // Get AWS credentials from environment
        const platform = @import("../util/platform.zig");
        const aws_access_key = platform.getenv("AWS_ACCESS_KEY_ID") orelse return error.MissingAWSCredentials;
        const aws_secret_key = platform.getenv("AWS_SECRET_ACCESS_KEY") orelse return error.MissingAWSCredentials;

        // Canonical request
        const canonical_headers = try std.fmt.allocPrint(
            self.allocator,
            "host:{s}.s3.{s}.amazonaws.com\nx-amz-content-sha256:{s}\nx-amz-date:{s}\n",
            .{ self.config.bucket.?, region, payload_hash, date_iso },
        );
        defer self.allocator.free(canonical_headers);

        const signed_headers = "host;x-amz-content-sha256;x-amz-date";

        const canonical_request = try std.fmt.allocPrint(
            self.allocator,
            "{s}\n{s}\n\n{s}\n{s}\n{s}",
            .{ method, url_path, canonical_headers, signed_headers, payload_hash },
        );
        defer self.allocator.free(canonical_request);

        // Hash canonical request
        var canonical_hash_buf: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(canonical_request, &canonical_hash_buf, .{});
        var canonical_hash_hex: [64]u8 = undefined;
        bytesToHex(&canonical_hash_hex, &canonical_hash_buf);
        const canonical_hash = canonical_hash_hex[0..];

        // String to sign
        const credential_scope = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}/s3/aws4_request",
            .{ date_stamp, region },
        );
        defer self.allocator.free(credential_scope);

        const string_to_sign = try std.fmt.allocPrint(
            self.allocator,
            "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}",
            .{ date_iso, credential_scope, canonical_hash },
        );
        defer self.allocator.free(string_to_sign);

        // Calculate signature
        const aws_key = try std.fmt.allocPrint(self.allocator, "AWS4{s}", .{aws_secret_key});
        defer self.allocator.free(aws_key);
        const kDate = try self.hmacSha256(aws_key, date_stamp);
        defer self.allocator.free(kDate);

        const kRegion = try self.hmacSha256(kDate, region);
        defer self.allocator.free(kRegion);

        const kService = try self.hmacSha256(kRegion, "s3");
        defer self.allocator.free(kService);

        const kSigning = try self.hmacSha256(kService, "aws4_request");
        defer self.allocator.free(kSigning);

        const signature = try self.hmacSha256(kSigning, string_to_sign);
        defer self.allocator.free(signature);

        var signature_hex_buf: [64]u8 = undefined;
        bytesToHex(&signature_hex_buf, signature);
        const signature_hex = signature_hex_buf[0..];

        // Authorization header
        const auth_header = try std.fmt.allocPrint(
            self.allocator,
            "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}",
            .{ aws_access_key, credential_scope, signed_headers, signature_hex },
        );

        return auth_header; // Caller owns
    }

    /// HMAC-SHA256 helper for AWS Signature v4.
    fn hmacSha256(self: *const RemoteCache, key: []const u8, data: []const u8) ![]u8 {
        var out: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&out, data, key);
        const result = try self.allocator.alloc(u8, 32);
        @memcpy(result, &out);
        return result;
    }

    /// Convert bytes to lowercase hex string.
    fn bytesToHex(out: []u8, in: []const u8) void {
        const hex_chars = "0123456789abcdef";
        for (in, 0..) |byte, i| {
            out[i * 2] = hex_chars[byte >> 4];
            out[i * 2 + 1] = hex_chars[byte & 0x0F];
        }
    }

    fn pullS3(self: *const RemoteCache, key: []const u8) !?[]u8 {
        const bucket = self.config.bucket orelse return error.MissingBucket;
        const region = self.config.region orelse "us-east-1";
        const prefix = self.config.prefix orelse "";

        // Construct S3 object path
        const object_key = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(object_key);

        // Generate timestamp
        const now = std.time.timestamp();
        const date_iso = try self.formatISO8601(now);
        defer self.allocator.free(date_iso);
        const date_stamp = try self.formatDateStamp(now);
        defer self.allocator.free(date_stamp);

        // Payload hash for GET is empty
        const empty_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

        // Sign request
        const url_path = try std.fmt.allocPrint(self.allocator, "/{s}", .{object_key});
        defer self.allocator.free(url_path);
        const auth_header = try self.signS3Request("GET", url_path, date_iso, date_stamp, empty_hash);
        defer self.allocator.free(auth_header);

        // Build S3 URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}.s3.{s}.amazonaws.com/{s}",
            .{ bucket, region, object_key },
        );
        defer self.allocator.free(url);

        // Use curl for S3 GET
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth_header}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-amz-content-sha256: {s}", .{empty_hash}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-amz-date: {s}", .{date_iso}));
        try argv.append(self.allocator, url);

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        }) catch return null;
        defer self.allocator.free(result.stderr);

        // exit 22 = HTTP 404 (cache miss)
        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return null;
        }

        return result.stdout; // Caller owns
    }

    fn pushS3(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        const bucket = self.config.bucket orelse return error.MissingBucket;
        const region = self.config.region orelse "us-east-1";
        const prefix = self.config.prefix orelse "";

        // Construct S3 object path
        const object_key = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(object_key);

        // Generate timestamp
        const now = std.time.timestamp();
        const date_iso = try self.formatISO8601(now);
        defer self.allocator.free(date_iso);
        const date_stamp = try self.formatDateStamp(now);
        defer self.allocator.free(date_stamp);

        // Calculate payload hash
        var payload_hash_buf: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &payload_hash_buf, .{});
        var payload_hash_hex: [64]u8 = undefined;
        bytesToHex(&payload_hash_hex, &payload_hash_buf);
        const payload_hash = payload_hash_hex[0..];

        // Sign request
        const url_path = try std.fmt.allocPrint(self.allocator, "/{s}", .{object_key});
        defer self.allocator.free(url_path);
        const auth_header = try self.signS3Request("PUT", url_path, date_iso, date_stamp, payload_hash);
        defer self.allocator.free(auth_header);

        // Build S3 URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}.s3.{s}.amazonaws.com/{s}",
            .{ bucket, region, object_key },
        );
        defer self.allocator.free(url);

        // Write data to temp file for curl upload
        const tmp_path = try std.fmt.allocPrint(self.allocator, "/tmp/zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_path);
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        defer std.fs.cwd().deleteFile(tmp_path) catch {};
        try file.writeAll(data);

        // Use curl for S3 PUT
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-X");
        try argv.append(self.allocator, "PUT");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth_header}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-amz-content-sha256: {s}", .{payload_hash}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-amz-date: {s}", .{date_iso}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "Content-Type: application/octet-stream");
        try argv.append(self.allocator, "--data-binary");
        const data_arg = try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_path});
        defer self.allocator.free(data_arg);
        try argv.append(self.allocator, data_arg);
        try argv.append(self.allocator, url);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.RemoteCacheFailed;
        }
    }

    /// Format Unix timestamp as ISO8601 for AWS (e.g., "20230101T120000Z").
    fn formatISO8601(self: *const RemoteCache, timestamp: i64) ![]u8 {
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(
            self.allocator,
            "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}Z",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            },
        );
    }

    /// Format Unix timestamp as date stamp for AWS (e.g., "20230101").
    fn formatDateStamp(self: *const RemoteCache, timestamp: i64) ![]u8 {
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return try std.fmt.allocPrint(
            self.allocator,
            "{d:0>4}{d:0>2}{d:0>2}",
            .{
                year_day.year,
                month_day.month.numeric(),
                month_day.day_index + 1,
            },
        );
    }

    // ─── GCS Backend ────────────────────────────────────────────────────────

    fn pullGCS(self: *const RemoteCache, key: []const u8) !?[]u8 {
        // TODO: Implement GCS backend
        _ = self;
        _ = key;
        return error.NotImplemented;
    }

    fn pushGCS(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        // TODO: Implement GCS backend
        _ = self;
        _ = key;
        _ = data;
        return error.NotImplemented;
    }

    // ─── Azure Backend ──────────────────────────────────────────────────────

    fn pullAzure(self: *const RemoteCache, key: []const u8) !?[]u8 {
        // TODO: Implement Azure Blob Storage backend
        _ = self;
        _ = key;
        return error.NotImplemented;
    }

    fn pushAzure(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        // TODO: Implement Azure Blob Storage backend
        _ = self;
        _ = key;
        _ = data;
        return error.NotImplemented;
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────

test "RemoteCache init and deinit" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "https://cache.example.com",
    };
    var cache = RemoteCache.init(allocator, config);
    defer cache.deinit();
}

test "formatISO8601" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .s3,
        .bucket = "test-bucket",
        .region = "us-east-1",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test known timestamp: 2024-01-01 00:00:00 UTC = 1704067200
    const iso = try cache.formatISO8601(1704067200);
    defer allocator.free(iso);

    try std.testing.expectEqualStrings("20240101T000000Z", iso);
}

test "formatDateStamp" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .s3,
        .bucket = "test-bucket",
        .region = "us-east-1",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test known timestamp: 2024-01-01 00:00:00 UTC = 1704067200
    const stamp = try cache.formatDateStamp(1704067200);
    defer allocator.free(stamp);

    try std.testing.expectEqualStrings("20240101", stamp);
}

test "hmacSha256" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .s3,
        .bucket = "test-bucket",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test known HMAC-SHA256 vector
    const result = try cache.hmacSha256("key", "The quick brown fox jumps over the lazy dog");
    defer allocator.free(result);

    // Expected HMAC-SHA256("key", "The quick brown fox jumps over the lazy dog")
    const expected = [_]u8{
        0xf7, 0xbc, 0x83, 0xf4, 0x30, 0x53, 0x84, 0x24,
        0xb1, 0x32, 0x98, 0xe6, 0xaa, 0x6f, 0xb1, 0x43,
        0xef, 0x4d, 0x59, 0xa1, 0x49, 0x46, 0x17, 0x59,
        0x97, 0x47, 0x9d, 0xbc, 0x2d, 0x1a, 0x3c, 0xd8,
    };

    try std.testing.expectEqualSlices(u8, &expected, result);
}

test "S3 backend missing credentials" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .s3,
        .bucket = "test-bucket",
        .region = "us-east-1",
    };
    const cache = RemoteCache.init(allocator, config);

    // S3 operations should fail without AWS credentials
    // (unless they happen to be set in the environment)
    const result = cache.pullS3("test-key") catch |err| {
        // Expected to fail with MissingAWSCredentials
        try std.testing.expect(err == error.MissingAWSCredentials);
        return;
    };

    // If we got here, AWS credentials were in the environment
    if (result) |data| {
        allocator.free(data);
    }
}
