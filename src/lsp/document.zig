const std = @import("std");

/// Represents an open document in the LSP server
pub const Document = struct {
    uri: []const u8, // Document URI (e.g., file:///path/to/zr.toml)
    content: []const u8, // Current document content
    version: i32, // Document version (incremented on each change)
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8, content: []const u8, version: i32) !Document {
        return Document{
            .uri = try allocator.dupe(u8, uri),
            .content = try allocator.dupe(u8, content),
            .version = version,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Document) void {
        self.allocator.free(self.uri);
        self.allocator.free(self.content);
    }

    /// Update document content with a new version
    pub fn update(self: *Document, new_content: []const u8, new_version: i32) !void {
        self.allocator.free(self.content);
        self.content = try self.allocator.dupe(u8, new_content);
        self.version = new_version;
    }
};

/// Manages all open documents
pub const DocumentStore = struct {
    documents: std.StringHashMap(Document),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DocumentStore {
        return DocumentStore{
            .documents = std.StringHashMap(Document).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DocumentStore) void {
        var iter = self.documents.iterator();
        while (iter.next()) |entry| {
            var doc = entry.value_ptr;
            doc.deinit();
        }
        self.documents.deinit();
    }

    /// Open a new document
    pub fn open(self: *DocumentStore, uri: []const u8, content: []const u8, version: i32) !void {
        const doc = try Document.init(self.allocator, uri, content, version);
        try self.documents.put(doc.uri, doc);
    }

    /// Update an existing document
    pub fn change(self: *DocumentStore, uri: []const u8, content: []const u8, version: i32) !void {
        if (self.documents.getPtr(uri)) |doc| {
            try doc.update(content, version);
        } else {
            return error.DocumentNotFound;
        }
    }

    /// Close a document
    pub fn close(self: *DocumentStore, uri: []const u8) void {
        if (self.documents.fetchRemove(uri)) |kv| {
            var doc = kv.value;
            doc.deinit();
        }
    }

    /// Get a document by URI
    pub fn get(self: *DocumentStore, uri: []const u8) ?*Document {
        return self.documents.getPtr(uri);
    }
};

test "Document - init and deinit" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "file:///test.toml", "content", 1);
    defer doc.deinit();

    try std.testing.expectEqualStrings("file:///test.toml", doc.uri);
    try std.testing.expectEqualStrings("content", doc.content);
    try std.testing.expectEqual(@as(i32, 1), doc.version);
}

test "Document - update" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "file:///test.toml", "old", 1);
    defer doc.deinit();

    try doc.update("new", 2);
    try std.testing.expectEqualStrings("new", doc.content);
    try std.testing.expectEqual(@as(i32, 2), doc.version);
}

test "DocumentStore - open and get" {
    const allocator = std.testing.allocator;
    var store = DocumentStore.init(allocator);
    defer store.deinit();

    try store.open("file:///test.toml", "content", 1);
    const doc = store.get("file:///test.toml");
    try std.testing.expect(doc != null);
    try std.testing.expectEqualStrings("content", doc.?.content);
}

test "DocumentStore - change" {
    const allocator = std.testing.allocator;
    var store = DocumentStore.init(allocator);
    defer store.deinit();

    try store.open("file:///test.toml", "old", 1);
    try store.change("file:///test.toml", "new", 2);

    const doc = store.get("file:///test.toml");
    try std.testing.expectEqualStrings("new", doc.?.content);
    try std.testing.expectEqual(@as(i32, 2), doc.?.version);
}

test "DocumentStore - close" {
    const allocator = std.testing.allocator;
    var store = DocumentStore.init(allocator);
    defer store.deinit();

    try store.open("file:///test.toml", "content", 1);
    store.close("file:///test.toml");

    const doc = store.get("file:///test.toml");
    try std.testing.expectEqual(@as(?*Document, null), doc);
}

test "DocumentStore - change nonexistent" {
    const allocator = std.testing.allocator;
    var store = DocumentStore.init(allocator);
    defer store.deinit();

    const result = store.change("file:///missing.toml", "content", 1);
    try std.testing.expectError(error.DocumentNotFound, result);
}
