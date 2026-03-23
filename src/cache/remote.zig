const std = @import("std");
const builtin = @import("builtin");
const types = @import("../config/types.zig");

/// Chunk size for incremental sync (1MB)
const CHUNK_SIZE: usize = 1024 * 1024;

/// Get system temp directory path. Caller owns returned memory.
/// Returns platform-specific temp directory (TEMP/TMP on Windows, TMPDIR or /tmp on Unix).
fn getTempDir(allocator: std.mem.Allocator) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch
                    std.process.getEnvVarOwned(allocator, "TMP") catch
                    try allocator.dupe(u8, "C:\\Windows\\Temp"),
        else => std.process.getEnvVarOwned(allocator, "TMPDIR") catch
                try allocator.dupe(u8, "/tmp"),
    };
}

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

    // ─── Compression (v1.5.0) ───────────────────────────────────────────────

    /// Compress data using gzip CLI. Caller owns returned memory.
    /// Uses external `gzip` command for maximum compatibility across platforms.
    fn compress(self: *const RemoteCache, data: []const u8) ![]u8 {
        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write data to temporary file (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-compress-in-{d}.tmp", .{std.time.timestamp()});
        defer self.allocator.free(tmp_filename);

        const tmp_in = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
        defer self.allocator.free(tmp_in);
        const in_file = try std.fs.cwd().createFile(tmp_in, .{});
        defer in_file.close();
        defer std.fs.cwd().deleteFile(tmp_in) catch {};
        try in_file.writeAll(data);

        // Compress with gzip
        const tmp_out = try std.fmt.allocPrint(self.allocator, "{s}.gz", .{tmp_in});
        defer self.allocator.free(tmp_out);
        defer std.fs.cwd().deleteFile(tmp_out) catch {};

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "gzip", "-f", "-9", tmp_in }, // -f = force, -9 = best compression
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.CompressionFailed;
        }

        // Read compressed file
        const out_file = try std.fs.cwd().openFile(tmp_out, .{});
        defer out_file.close();
        const compressed = try out_file.readToEndAlloc(self.allocator, 100 * 1024 * 1024); // 100MB max

        return compressed;
    }

    /// Decompress gzipped data using gzip CLI. Caller owns returned memory.
    fn decompress(self: *const RemoteCache, compressed_data: []const u8) ![]u8 {
        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write compressed data to temporary file (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-decompress-in-{d}.tmp.gz", .{std.time.timestamp()});
        defer self.allocator.free(tmp_filename);

        const tmp_in = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
        defer self.allocator.free(tmp_in);
        const in_file = try std.fs.cwd().createFile(tmp_in, .{});
        defer in_file.close();
        defer std.fs.cwd().deleteFile(tmp_in) catch {};
        try in_file.writeAll(compressed_data);

        // Decompress with gunzip
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "gunzip", "-c", tmp_in }, // -c = write to stdout
        });
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return error.DecompressionFailed;
        }

        return result.stdout; // Caller owns
    }

    // ─── Incremental Sync (v1.5.0) ──────────────────────────────────────────

    /// Manifest structure for chunked cache entries
    const Manifest = struct {
        original_size: usize,
        chunk_size: usize,
        chunks: []ChunkInfo,

        const ChunkInfo = struct {
            hash: [64]u8, // SHA256 hex string
            size: usize,
        };

        pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
            allocator.free(self.chunks);
        }
    };

    /// Create manifest from data by splitting into chunks
    fn createManifest(self: *const RemoteCache, data: []const u8) !Manifest {
        const chunk_count = (data.len + CHUNK_SIZE - 1) / CHUNK_SIZE;
        const chunks = try self.allocator.alloc(Manifest.ChunkInfo, chunk_count);

        var i: usize = 0;
        while (i < chunk_count) : (i += 1) {
            const start = i * CHUNK_SIZE;
            const end = @min(start + CHUNK_SIZE, data.len);
            const chunk_data = data[start..end];

            // Compute SHA256 hash of chunk
            var hash_buf: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(chunk_data, &hash_buf, .{});

            // Convert to hex
            var hash_hex: [64]u8 = undefined;
            bytesToHex(&hash_hex, &hash_buf);

            chunks[i] = .{
                .hash = hash_hex,
                .size = chunk_data.len,
            };
        }

        return Manifest{
            .original_size = data.len,
            .chunk_size = CHUNK_SIZE,
            .chunks = chunks,
        };
    }

    /// Serialize manifest to JSON
    fn serializeManifest(self: *const RemoteCache, manifest: *const Manifest) ![]u8 {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        var writer = buf.writer(self.allocator);
        try writer.writeAll("{\"original_size\":");
        try writer.print("{d}", .{manifest.original_size});
        try writer.writeAll(",\"chunk_size\":");
        try writer.print("{d}", .{manifest.chunk_size});
        try writer.writeAll(",\"chunks\":[");

        for (manifest.chunks, 0..) |chunk, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("{\"hash\":\"");
            try writer.writeAll(&chunk.hash);
            try writer.writeAll("\",\"size\":");
            try writer.print("{d}", .{chunk.size});
            try writer.writeAll("}");
        }

        try writer.writeAll("]}");
        return try self.allocator.dupe(u8, buf.items);
    }

    /// Deserialize manifest from JSON
    fn deserializeManifest(self: *const RemoteCache, json: []const u8) !Manifest {
        const parsed = try std.json.parseFromSlice(
            struct {
                original_size: usize,
                chunk_size: usize,
                chunks: []struct {
                    hash: []const u8,
                    size: usize,
                },
            },
            self.allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        const chunks = try self.allocator.alloc(Manifest.ChunkInfo, parsed.value.chunks.len);
        for (parsed.value.chunks, 0..) |chunk_json, i| {
            if (chunk_json.hash.len != 64) return error.InvalidManifest;
            var hash: [64]u8 = undefined;
            @memcpy(&hash, chunk_json.hash[0..64]);
            chunks[i] = .{
                .hash = hash,
                .size = chunk_json.size,
            };
        }

        return Manifest{
            .original_size = parsed.value.original_size,
            .chunk_size = parsed.value.chunk_size,
            .chunks = chunks,
        };
    }

    /// Check if a chunk exists remotely (returns true if exists, false if not)
    fn hasChunk(self: *const RemoteCache, chunk_hash: []const u8) !bool {
        const key = try std.fmt.allocPrint(self.allocator, "chunks/{s}", .{chunk_hash});
        defer self.allocator.free(key);

        // Try to pull the chunk (HTTP HEAD would be better, but this works)
        const result = switch (self.config.type) {
            .http => try self.pullHTTP(key),
            .s3 => try self.pullS3(key),
            .gcs => try self.pullGCS(key),
            .azure => try self.pullAzure(key),
        };

        if (result) |data| {
            self.allocator.free(data);
            return true;
        }
        return false;
    }

    /// Upload a single chunk
    fn pushChunk(self: *const RemoteCache, chunk_hash: []const u8, data: []const u8) !void {
        const key = try std.fmt.allocPrint(self.allocator, "chunks/{s}", .{chunk_hash});
        defer self.allocator.free(key);

        const to_push = if (self.config.compression)
            try self.compress(data)
        else
            data;
        defer if (self.config.compression) self.allocator.free(to_push);

        return switch (self.config.type) {
            .http => try self.pushHTTP(key, to_push),
            .s3 => try self.pushS3(key, to_push),
            .gcs => try self.pushGCS(key, to_push),
            .azure => try self.pushAzure(key, to_push),
        };
    }

    /// Download a single chunk
    fn pullChunk(self: *const RemoteCache, chunk_hash: []const u8) !?[]u8 {
        const key = try std.fmt.allocPrint(self.allocator, "chunks/{s}", .{chunk_hash});
        defer self.allocator.free(key);

        const compressed = switch (self.config.type) {
            .http => try self.pullHTTP(key),
            .s3 => try self.pullS3(key),
            .gcs => try self.pullGCS(key),
            .azure => try self.pullAzure(key),
        };

        if (compressed == null) return null;
        defer self.allocator.free(compressed.?);

        if (self.config.compression) {
            return try self.decompress(compressed.?);
        }
        return try self.allocator.dupe(u8, compressed.?);
    }

    // ────────────────────────────────────────────────────────────────────────

    /// Pull a cache entry from remote using incremental sync.
    /// Returns cached data or null if not found. Caller owns returned memory.
    pub fn pull(self: *const RemoteCache, key: []const u8) !?[]u8 {
        // Use incremental sync if enabled
        if (self.config.incremental_sync) {
            return try self.pullIncremental(key);
        }

        // Fallback to monolithic pull
        const compressed = switch (self.config.type) {
            .http => try self.pullHTTP(key),
            .s3 => try self.pullS3(key),
            .gcs => try self.pullGCS(key),
            .azure => try self.pullAzure(key),
        };

        if (compressed == null) return null;
        defer self.allocator.free(compressed.?);

        // Decompress if compression is enabled
        if (self.config.compression) {
            return try self.decompress(compressed.?);
        }
        // Return raw data if compression is disabled
        return try self.allocator.dupe(u8, compressed.?);
    }

    /// Pull using incremental sync (download manifest + chunks)
    fn pullIncremental(self: *const RemoteCache, key: []const u8) !?[]u8 {
        // Download manifest
        const manifest_key = try std.fmt.allocPrint(self.allocator, "{s}.manifest", .{key});
        defer self.allocator.free(manifest_key);

        const manifest_data = switch (self.config.type) {
            .http => try self.pullHTTP(manifest_key),
            .s3 => try self.pullS3(manifest_key),
            .gcs => try self.pullGCS(manifest_key),
            .azure => try self.pullAzure(manifest_key),
        };

        if (manifest_data == null) return null; // Cache miss
        defer self.allocator.free(manifest_data.?);

        var manifest = try self.deserializeManifest(manifest_data.?);
        defer manifest.deinit(self.allocator);

        // Allocate buffer for reassembled data
        const result = try self.allocator.alloc(u8, manifest.original_size);
        errdefer self.allocator.free(result);

        // Download and reassemble chunks
        var offset: usize = 0;
        for (manifest.chunks) |chunk_info| {
            const chunk_data = try self.pullChunk(&chunk_info.hash) orelse return error.MissingChunk;
            defer self.allocator.free(chunk_data);

            if (chunk_data.len != chunk_info.size) return error.ChunkSizeMismatch;

            @memcpy(result[offset .. offset + chunk_data.len], chunk_data);
            offset += chunk_data.len;
        }

        return result;
    }

    /// Push a cache entry to remote using incremental sync.
    pub fn push(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        // Use incremental sync if enabled
        if (self.config.incremental_sync) {
            return try self.pushIncremental(key, data);
        }

        // Fallback to monolithic push
        const to_push = if (self.config.compression)
            try self.compress(data)
        else
            data;
        defer if (self.config.compression) self.allocator.free(to_push);

        return switch (self.config.type) {
            .http => try self.pushHTTP(key, to_push),
            .s3 => try self.pushS3(key, to_push),
            .gcs => try self.pushGCS(key, to_push),
            .azure => try self.pushAzure(key, to_push),
        };
    }

    /// Push using incremental sync (upload only missing chunks + manifest)
    fn pushIncremental(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        // Create manifest
        var manifest = try self.createManifest(data);
        defer manifest.deinit(self.allocator);

        // Upload chunks (only if they don't exist remotely)
        var i: usize = 0;
        while (i < manifest.chunks.len) : (i += 1) {
            const chunk_info = manifest.chunks[i];
            const chunk_hash = chunk_info.hash[0..];

            // Check if chunk already exists
            const exists = try self.hasChunk(chunk_hash);
            if (exists) continue; // Skip existing chunk

            // Upload missing chunk
            const start = i * CHUNK_SIZE;
            const end = @min(start + CHUNK_SIZE, data.len);
            const chunk_data = data[start..end];
            try self.pushChunk(chunk_hash, chunk_data);
        }

        // Upload manifest
        const manifest_json = try self.serializeManifest(&manifest);
        defer self.allocator.free(manifest_json);

        const manifest_key = try std.fmt.allocPrint(self.allocator, "{s}.manifest", .{key});
        defer self.allocator.free(manifest_key);

        const to_push = if (self.config.compression)
            try self.compress(manifest_json)
        else
            manifest_json;
        defer if (self.config.compression) self.allocator.free(to_push);

        return switch (self.config.type) {
            .http => try self.pushHTTP(manifest_key, to_push),
            .s3 => try self.pushS3(manifest_key, to_push),
            .gcs => try self.pushGCS(manifest_key, to_push),
            .azure => try self.pushAzure(manifest_key, to_push),
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

        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write data to temp file for curl upload (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_filename);

        const tmp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
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

        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write data to temp file for curl upload (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_filename);

        const tmp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
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

    /// Google Cloud Storage backend using OAuth2 service account authentication.
    /// Reference: https://cloud.google.com/storage/docs/authentication
    /// Authentication methods:
    /// 1. Service account key via GOOGLE_APPLICATION_CREDENTIALS env var (JSON file path)
    /// 2. Access token via GOOGLE_ACCESS_TOKEN env var (for pre-authenticated scenarios)
    fn pullGCS(self: *const RemoteCache, key: []const u8) !?[]u8 {
        const bucket = self.config.bucket orelse return error.MissingBucket;
        const prefix = self.config.prefix orelse "";

        // Construct GCS object path
        const object_key = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(object_key);

        // Get access token
        const access_token = try self.getGCSAccessToken();
        defer self.allocator.free(access_token);

        // Build GCS URL (using JSON API for simplicity, supports alt=media for raw download)
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://storage.googleapis.com/storage/v1/b/{s}/o/{s}?alt=media",
            .{ bucket, object_key },
        );
        defer self.allocator.free(url);

        // Use curl for GCS GET
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}", .{access_token}));
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

    fn pushGCS(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        const bucket = self.config.bucket orelse return error.MissingBucket;
        const prefix = self.config.prefix orelse "";

        // Construct GCS object path
        const object_key = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(object_key);

        // Get access token
        const access_token = try self.getGCSAccessToken();
        defer self.allocator.free(access_token);

        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write data to temp file for curl upload (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_filename);

        const tmp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
        defer self.allocator.free(tmp_path);
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        defer std.fs.cwd().deleteFile(tmp_path) catch {};
        try file.writeAll(data);

        // Build GCS upload URL (using JSON API with uploadType=media)
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://storage.googleapis.com/upload/storage/v1/b/{s}/o?uploadType=media&name={s}",
            .{ bucket, object_key },
        );
        defer self.allocator.free(url);

        // Use curl for GCS POST
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-X");
        try argv.append(self.allocator, "POST");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: Bearer {s}", .{access_token}));
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

    /// Get GCS access token from environment.
    /// Supports two methods:
    /// 1. GOOGLE_ACCESS_TOKEN - pre-authenticated bearer token
    /// 2. GOOGLE_APPLICATION_CREDENTIALS - path to service account JSON key file
    fn getGCSAccessToken(self: *const RemoteCache) ![]u8 {
        const platform = @import("../util/platform.zig");

        // Method 1: Direct access token
        if (platform.getenv("GOOGLE_ACCESS_TOKEN")) |token| {
            return try self.allocator.dupe(u8, token);
        }

        // Method 2: Service account key file
        if (platform.getenv("GOOGLE_APPLICATION_CREDENTIALS")) |creds_path| {
            return try self.getGCSAccessTokenFromServiceAccount(creds_path);
        }

        return error.MissingGCPCredentials;
    }

    /// Obtain OAuth2 access token from service account JSON key file.
    /// Uses Google's OAuth2 token endpoint with JWT assertion.
    /// Reference: https://developers.google.com/identity/protocols/oauth2/service-account
    fn getGCSAccessTokenFromServiceAccount(self: *const RemoteCache, creds_path: []const u8) ![]u8 {
        // Read service account JSON file
        const file = try std.fs.cwd().openFile(creds_path, .{});
        defer file.close();
        const json_data = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(json_data);

        // Parse JSON to extract client_email and private_key
        const parsed = try std.json.parseFromSlice(
            struct {
                client_email: []const u8,
                private_key: []const u8,
                token_uri: ?[]const u8 = null,
            },
            self.allocator,
            json_data,
            .{},
        );
        defer parsed.deinit();

        const service_account = parsed.value;
        const token_uri = service_account.token_uri orelse "https://oauth2.googleapis.com/token";

        // Create JWT assertion
        const jwt = try self.createGCSJWT(service_account.client_email, service_account.private_key);
        defer self.allocator.free(jwt);

        // Exchange JWT for access token via OAuth2 token endpoint
        const form_data = try std.fmt.allocPrint(
            self.allocator,
            "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion={s}",
            .{jwt},
        );
        defer self.allocator.free(form_data);

        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write form data to temp file (platform-agnostic)
        const tmp_filename = "zr-gcs-oauth-form.tmp";
        const tmp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
        defer self.allocator.free(tmp_path);
        const tmp_file = try std.fs.cwd().createFile(tmp_path, .{});
        defer tmp_file.close();
        defer std.fs.cwd().deleteFile(tmp_path) catch {};
        try tmp_file.writeAll(form_data);

        // Use curl to POST to token endpoint
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-X");
        try argv.append(self.allocator, "POST");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "Content-Type: application/x-www-form-urlencoded");
        try argv.append(self.allocator, "--data-binary");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "@{s}", .{tmp_path}));
        try argv.append(self.allocator, token_uri);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.GCSOAuth2Failed;
        }

        // Parse JSON response to extract access_token
        const token_response = try std.json.parseFromSlice(
            struct {
                access_token: []const u8,
                expires_in: ?i64 = null,
                token_type: ?[]const u8 = null,
            },
            self.allocator,
            result.stdout,
            .{},
        );
        defer token_response.deinit();

        return try self.allocator.dupe(u8, token_response.value.access_token);
    }

    /// Create JWT assertion for GCS service account OAuth2.
    /// Reference: https://developers.google.com/identity/protocols/oauth2/service-account#authorizingrequests
    fn createGCSJWT(self: *const RemoteCache, client_email: []const u8, private_key: []const u8) ![]u8 {
        // JWT Header (alg: RS256, typ: JWT)
        const header = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
        const header_b64 = try self.base64UrlEncode(header);
        defer self.allocator.free(header_b64);

        // JWT Payload (iss, scope, aud, exp, iat)
        const now = std.time.timestamp();
        const exp = now + 3600; // 1 hour expiration
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "{{\"iss\":\"{s}\",\"scope\":\"https://www.googleapis.com/auth/devstorage.read_write\",\"aud\":\"https://oauth2.googleapis.com/token\",\"exp\":{d},\"iat\":{d}}}",
            .{ client_email, exp, now },
        );
        defer self.allocator.free(payload);
        const payload_b64 = try self.base64UrlEncode(payload);
        defer self.allocator.free(payload_b64);

        // Construct signing input: header.payload
        const signing_input = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ header_b64, payload_b64 },
        );
        defer self.allocator.free(signing_input);

        // Sign with RS256 (RSA-SHA256) using private_key
        // NOTE: This is a simplified implementation using openssl command.
        // A production implementation should use a proper RSA signing library.
        const signature = try self.signRS256(signing_input, private_key);
        defer self.allocator.free(signature);

        // Construct final JWT: header.payload.signature
        return try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}.{s}",
            .{ header_b64, payload_b64, signature },
        );
    }

    /// Base64 URL-safe encoding (without padding).
    fn base64UrlEncode(self: *const RemoteCache, data: []const u8) ![]u8 {
        const encoder = std.base64.url_safe_no_pad;
        const encoded_len = encoder.Encoder.calcSize(data.len);
        const encoded = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.Encoder.encode(encoded, data);
        return encoded;
    }

    /// Sign data with RS256 (RSA-SHA256) using private key.
    /// Uses openssl command for RSA signing (Zig 0.15 lacks RSA in std.crypto).
    fn signRS256(self: *const RemoteCache, data: []const u8, private_key: []const u8) ![]u8 {
        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write private key to temp file (platform-agnostic)
        const key_filename = "zr-gcs-privkey.pem";
        const key_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, key_filename });
        defer self.allocator.free(key_path);
        const key_file = try std.fs.cwd().createFile(key_path, .{});
        defer key_file.close();
        defer std.fs.cwd().deleteFile(key_path) catch {};
        try key_file.writeAll(private_key);

        // Write data to temp file
        const data_filename = "zr-gcs-data.tmp";
        const data_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, data_filename });
        defer self.allocator.free(data_path);
        const data_file = try std.fs.cwd().createFile(data_path, .{});
        defer data_file.close();
        defer std.fs.cwd().deleteFile(data_path) catch {};
        try data_file.writeAll(data);

        // Sign using openssl
        const sig_filename = "zr-gcs-sig.bin";
        const sig_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, sig_filename });
        defer self.allocator.free(sig_path);
        defer std.fs.cwd().deleteFile(sig_path) catch {};

        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "openssl");
        try argv.append(self.allocator, "dgst");
        try argv.append(self.allocator, "-sha256");
        try argv.append(self.allocator, "-sign");
        try argv.append(self.allocator, key_path);
        try argv.append(self.allocator, "-out");
        try argv.append(self.allocator, sig_path);
        try argv.append(self.allocator, data_path);

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv.items,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            return error.RSASigningFailed;
        }

        // Read signature binary
        const sig_file = try std.fs.cwd().openFile(sig_path, .{});
        defer sig_file.close();
        const sig_binary = try sig_file.readToEndAlloc(self.allocator, 4096);
        defer self.allocator.free(sig_binary);

        // Base64 URL-safe encode signature
        return try self.base64UrlEncode(sig_binary);
    }

    // ─── Azure Backend ──────────────────────────────────────────────────────

    /// Azure Blob Storage backend using Shared Key authentication.
    /// Reference: https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
    /// Requires AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_KEY environment variables.
    fn pullAzure(self: *const RemoteCache, key: []const u8) !?[]u8 {
        const bucket = self.config.bucket orelse return error.MissingBucket; // Container name
        const prefix = self.config.prefix orelse "";

        // Construct Azure blob path
        const blob_name = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(blob_name);

        // Get Azure credentials from environment
        const platform = @import("../util/platform.zig");
        const account = platform.getenv("AZURE_STORAGE_ACCOUNT") orelse return error.MissingAzureCredentials;
        const access_key = platform.getenv("AZURE_STORAGE_KEY") orelse return error.MissingAzureCredentials;

        // Generate timestamp (RFC1123 format)
        const date = try self.formatRFC1123(std.time.timestamp());
        defer self.allocator.free(date);

        // Construct URL: https://{account}.blob.core.windows.net/{container}/{blob}
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}.blob.core.windows.net/{s}/{s}",
            .{ account, bucket, blob_name },
        );
        defer self.allocator.free(url);

        // Construct canonicalized resource: /{account}/{container}/{blob}
        const canonicalized_resource = try std.fmt.allocPrint(
            self.allocator,
            "/{s}/{s}/{s}",
            .{ account, bucket, blob_name },
        );
        defer self.allocator.free(canonicalized_resource);

        // Sign request with Shared Key
        const auth_header = try self.signAzureRequest(
            "GET",
            "",
            "",
            date,
            canonicalized_resource,
            account,
            access_key,
        );
        defer self.allocator.free(auth_header);

        // Use curl for Azure GET
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-ms-date: {s}", .{date}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "x-ms-version: 2023-11-03");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth_header}));
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

    fn pushAzure(self: *const RemoteCache, key: []const u8, data: []const u8) !void {
        const bucket = self.config.bucket orelse return error.MissingBucket; // Container name
        const prefix = self.config.prefix orelse "";

        // Construct Azure blob path
        const blob_name = if (prefix.len > 0)
            try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ prefix, key })
        else
            try std.fmt.allocPrint(self.allocator, "{s}.cache", .{key});
        defer self.allocator.free(blob_name);

        // Get Azure credentials from environment
        const platform = @import("../util/platform.zig");
        const account = platform.getenv("AZURE_STORAGE_ACCOUNT") orelse return error.MissingAzureCredentials;
        const access_key = platform.getenv("AZURE_STORAGE_KEY") orelse return error.MissingAzureCredentials;

        // Generate timestamp (RFC1123 format)
        const date = try self.formatRFC1123(std.time.timestamp());
        defer self.allocator.free(date);

        // Construct URL: https://{account}.blob.core.windows.net/{container}/{blob}
        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://{s}.blob.core.windows.net/{s}/{s}",
            .{ account, bucket, blob_name },
        );
        defer self.allocator.free(url);

        // Construct canonicalized resource: /{account}/{container}/{blob}
        const canonicalized_resource = try std.fmt.allocPrint(
            self.allocator,
            "/{s}/{s}/{s}",
            .{ account, bucket, blob_name },
        );
        defer self.allocator.free(canonicalized_resource);

        // Content-Length for signature
        const content_length = try std.fmt.allocPrint(self.allocator, "{d}", .{data.len});
        defer self.allocator.free(content_length);

        // Sign request with Shared Key
        const auth_header = try self.signAzureRequest(
            "PUT",
            "application/octet-stream",
            content_length,
            date,
            canonicalized_resource,
            account,
            access_key,
        );
        defer self.allocator.free(auth_header);

        // Get system temp directory
        const tmp_dir_path = try getTempDir(self.allocator);
        defer self.allocator.free(tmp_dir_path);

        // Write data to temp file for curl upload (platform-agnostic)
        const tmp_filename = try std.fmt.allocPrint(self.allocator, "zr-cache-{s}.tmp", .{key});
        defer self.allocator.free(tmp_filename);

        const tmp_path = try std.fs.path.join(self.allocator, &[_][]const u8{ tmp_dir_path, tmp_filename });
        defer self.allocator.free(tmp_path);
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        defer std.fs.cwd().deleteFile(tmp_path) catch {};
        try file.writeAll(data);

        // Use curl for Azure PUT
        var argv = std.ArrayList([]const u8){};
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "curl");
        try argv.append(self.allocator, "-s");
        try argv.append(self.allocator, "-f");
        try argv.append(self.allocator, "-X");
        try argv.append(self.allocator, "PUT");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "x-ms-date: {s}", .{date}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "x-ms-version: 2023-11-03");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "x-ms-blob-type: BlockBlob");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Content-Length: {s}", .{content_length}));
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, "Content-Type: application/octet-stream");
        try argv.append(self.allocator, "-H");
        try argv.append(self.allocator, try std.fmt.allocPrint(self.allocator, "Authorization: {s}", .{auth_header}));
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

    /// Sign Azure Blob Storage request using Shared Key.
    /// Reference: https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
    fn signAzureRequest(
        self: *const RemoteCache,
        method: []const u8,
        content_type: []const u8,
        content_length: []const u8,
        date: []const u8,
        canonicalized_resource: []const u8,
        account: []const u8,
        access_key: []const u8,
    ) ![]u8 {
        // Construct string to sign for Azure Shared Key
        // Format: VERB\n\n\nContent-Length\n\nContent-Type\n\n\n\n\n\n\nx-ms-blob-type:BlockBlob\nx-ms-date:DATE\nx-ms-version:VERSION\n/ACCOUNT/RESOURCE
        const api_version = "2023-11-03";

        // For GET, content_length and content_type are empty
        // For PUT, we need to include them + x-ms-blob-type header
        const string_to_sign = if (std.mem.eql(u8, method, "PUT"))
            try std.fmt.allocPrint(
                self.allocator,
                "{s}\n\n\n{s}\n\n{s}\n\n\n\n\n\n\nx-ms-blob-type:BlockBlob\nx-ms-date:{s}\nx-ms-version:{s}\n{s}",
                .{ method, content_length, content_type, date, api_version, canonicalized_resource },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{s}\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:{s}\nx-ms-version:{s}\n{s}",
                .{ method, date, api_version, canonicalized_resource },
            );
        defer self.allocator.free(string_to_sign);

        // Decode base64 access key
        const decoder = std.base64.standard;
        const decoded_key_len = try decoder.Decoder.calcSizeForSlice(access_key);
        const decoded_key = try self.allocator.alloc(u8, decoded_key_len);
        defer self.allocator.free(decoded_key);
        try decoder.Decoder.decode(decoded_key, access_key);

        // HMAC-SHA256 signature
        var signature_buf: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&signature_buf, string_to_sign, decoded_key);

        // Base64 encode signature
        const encoder = std.base64.standard;
        const encoded_len = encoder.Encoder.calcSize(signature_buf.len);
        const encoded_sig = try self.allocator.alloc(u8, encoded_len);
        _ = encoder.Encoder.encode(encoded_sig, &signature_buf);

        // Authorization header: SharedKey {account}:{signature}
        const auth_header = try std.fmt.allocPrint(
            self.allocator,
            "SharedKey {s}:{s}",
            .{ account, encoded_sig },
        );
        self.allocator.free(encoded_sig);

        return auth_header; // Caller owns
    }

    /// Format Unix timestamp as RFC1123 for Azure (e.g., "Mon, 01 Jan 2024 12:00:00 GMT").
    fn formatRFC1123(self: *const RemoteCache, timestamp: i64) ![]u8 {
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day_seconds = epoch_seconds.getDaySeconds();
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        // 1970-01-01 was Thursday (index 3 in our array starting with Mon=0)
        // epoch_day.day is days since 1970-01-01
        const day_of_week = @mod(epoch_day.day + 3, 7);
        const weekdays = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
        const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

        return try std.fmt.allocPrint(
            self.allocator,
            "{s}, {d:0>2} {s} {d} {d:0>2}:{d:0>2}:{d:0>2} GMT",
            .{
                weekdays[day_of_week],
                month_day.day_index + 1,
                months[month_day.month.numeric() - 1],
                year_day.year,
                day_seconds.getHoursIntoDay(),
                day_seconds.getMinutesIntoHour(),
                day_seconds.getSecondsIntoMinute(),
            },
        );
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

test "GCS backend missing credentials" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .gcs,
        .bucket = "test-bucket",
    };
    const cache = RemoteCache.init(allocator, config);

    // GCS operations should fail without credentials
    // (unless they happen to be set in the environment)
    const result = cache.pullGCS("test-key") catch |err| {
        // Expected to fail with MissingGCPCredentials
        try std.testing.expect(err == error.MissingGCPCredentials);
        return;
    };

    // If we got here, GCP credentials were in the environment
    if (result) |data| {
        allocator.free(data);
    }
}

test "base64UrlEncode" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .gcs,
        .bucket = "test-bucket",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test known base64 encoding (without padding)
    const result = try cache.base64UrlEncode("hello world");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("aGVsbG8gd29ybGQ", result);
}

test "GCS JWT header and payload format" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .gcs,
        .bucket = "test-bucket",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test JWT header encoding
    const header = "{\"alg\":\"RS256\",\"typ\":\"JWT\"}";
    const header_b64 = try cache.base64UrlEncode(header);
    defer allocator.free(header_b64);

    // Verify header is properly base64 encoded
    try std.testing.expect(header_b64.len > 0);
    try std.testing.expectEqualStrings("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9", header_b64);
}

test "Azure backend missing credentials" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .azure,
        .bucket = "test-container",
    };
    const cache = RemoteCache.init(allocator, config);

    // Azure operations should fail without credentials
    // (unless they happen to be set in the environment)
    const result = cache.pullAzure("test-key") catch |err| {
        // Expected to fail with MissingAzureCredentials
        try std.testing.expect(err == error.MissingAzureCredentials);
        return;
    };

    // If we got here, Azure credentials were in the environment
    if (result) |data| {
        allocator.free(data);
    }
}

test "formatRFC1123" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .azure,
        .bucket = "test-container",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test known timestamp: Monday, 01 Jan 2024 00:00:00 GMT = 1704067200
    const rfc1123 = try cache.formatRFC1123(1704067200);
    defer allocator.free(rfc1123);

    try std.testing.expectEqualStrings("Mon, 01 Jan 2024 00:00:00 GMT", rfc1123);
}

test "Azure signature generation" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .azure,
        .bucket = "test-container",
    };
    const cache = RemoteCache.init(allocator, config);

    // Test signature generation with known values
    // Using a test access key (base64 encoded 32-byte key)
    const test_key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const test_account = "testaccount";
    const test_date = "Mon, 01 Jan 2024 00:00:00 GMT";

    const auth_header = try cache.signAzureRequest(
        "GET",
        "",
        "",
        test_date,
        "/testaccount/test-container/test.cache",
        test_account,
        test_key,
    );
    defer allocator.free(auth_header);

    // Verify the header starts with "SharedKey testaccount:"
    try std.testing.expect(std.mem.startsWith(u8, auth_header, "SharedKey testaccount:"));
    try std.testing.expect(auth_header.len > 30); // Should have a base64 signature
}

// ─── Compression Tests (v1.5.0) ─────────────────────────────────────────────

test "compression: roundtrip small data" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .compression = true,
    };
    const cache = RemoteCache.init(allocator, config);

    const original = "Hello, World! This is a test of gzip compression.";

    const compressed = try cache.compress(original);
    defer allocator.free(compressed);

    // Compressed data should be smaller or roughly the same for small data
    try std.testing.expect(compressed.len > 0);

    const decompressed = try cache.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "compression: roundtrip large repeating data" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .compression = true,
    };
    const cache = RemoteCache.init(allocator, config);

    // Create highly compressible data (repeating pattern)
    var original = std.ArrayList(u8){};
    defer original.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try original.appendSlice(allocator, "AAAAAAAAAA");
    }

    const compressed = try cache.compress(original.items);
    defer allocator.free(compressed);

    // Compressed should be significantly smaller than original
    try std.testing.expect(compressed.len < original.items.len / 10);

    const decompressed = try cache.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original.items, decompressed);
}

test "compression: binary data" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .compression = true,
    };
    const cache = RemoteCache.init(allocator, config);

    // Binary data with all byte values
    var original: [256]u8 = undefined;
    for (&original, 0..) |*byte, idx| {
        byte.* = @as(u8, @truncate(idx));
    }

    const compressed = try cache.compress(&original);
    defer allocator.free(compressed);

    const decompressed = try cache.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &original, decompressed);
}

test "compression: empty data" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .compression = true,
    };
    const cache = RemoteCache.init(allocator, config);

    const original = "";

    const compressed = try cache.compress(original);
    defer allocator.free(compressed);

    // Even empty data should have gzip header/footer
    try std.testing.expect(compressed.len >= 20);

    const decompressed = try cache.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

// ─── Incremental Sync Tests (v1.5.0) ────────────────────────────────────────

test "createManifest: single chunk" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .incremental_sync = true,
    };
    const cache = RemoteCache.init(allocator, config);

    const data = "Small data under 1MB";
    var manifest = try cache.createManifest(data);
    defer manifest.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), manifest.chunks.len);
    try std.testing.expectEqual(@as(usize, data.len), manifest.original_size);
    try std.testing.expectEqual(@as(usize, data.len), manifest.chunks[0].size);
}

test "createManifest: multiple chunks" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .incremental_sync = true,
    };
    const cache = RemoteCache.init(allocator, config);

    // Create data > 2MB (3 chunks)
    var data = std.ArrayList(u8){};
    defer data.deinit(allocator);

    var i: usize = 0;
    while (i < 3 * 1024 * 1024) : (i += 1) {
        try data.append(allocator, @as(u8, @truncate(i % 256)));
    }

    var manifest = try cache.createManifest(data.items);
    defer manifest.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), manifest.chunks.len);
    try std.testing.expectEqual(@as(usize, data.items.len), manifest.original_size);

    // First two chunks should be CHUNK_SIZE
    try std.testing.expectEqual(@as(usize, CHUNK_SIZE), manifest.chunks[0].size);
    try std.testing.expectEqual(@as(usize, CHUNK_SIZE), manifest.chunks[1].size);

    // Last chunk should be remainder
    const expected_last_size = data.items.len - (2 * CHUNK_SIZE);
    try std.testing.expectEqual(expected_last_size, manifest.chunks[2].size);
}

test "manifest serialization roundtrip" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .incremental_sync = true,
    };
    const cache = RemoteCache.init(allocator, config);

    const data = "Test data for manifest serialization";
    var manifest = try cache.createManifest(data);
    defer manifest.deinit(allocator);

    // Serialize
    const json = try cache.serializeManifest(&manifest);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"original_size\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"chunks\"") != null);

    // Deserialize
    var manifest2 = try cache.deserializeManifest(json);
    defer manifest2.deinit(allocator);

    try std.testing.expectEqual(manifest.original_size, manifest2.original_size);
    try std.testing.expectEqual(manifest.chunk_size, manifest2.chunk_size);
    try std.testing.expectEqual(manifest.chunks.len, manifest2.chunks.len);

    for (manifest.chunks, manifest2.chunks) |chunk1, chunk2| {
        try std.testing.expectEqualSlices(u8, &chunk1.hash, &chunk2.hash);
        try std.testing.expectEqual(chunk1.size, chunk2.size);
    }
}

test "chunk hash consistency" {
    const allocator = std.testing.allocator;
    const config = types.RemoteCacheConfig{
        .type = .http,
        .url = "http://localhost",
        .incremental_sync = true,
    };
    const cache = RemoteCache.init(allocator, config);

    const data = "Deterministic chunk hashing test";

    var manifest1 = try cache.createManifest(data);
    defer manifest1.deinit(allocator);

    var manifest2 = try cache.createManifest(data);
    defer manifest2.deinit(allocator);

    // Same data should produce same chunk hashes
    try std.testing.expectEqual(manifest1.chunks.len, manifest2.chunks.len);
    for (manifest1.chunks, manifest2.chunks) |chunk1, chunk2| {
        try std.testing.expectEqualSlices(u8, &chunk1.hash, &chunk2.hash);
    }
}
