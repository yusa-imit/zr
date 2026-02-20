const std = @import("std");

/// WASM plugin runtime using interpreter-based execution.
/// This module provides sandboxed execution of WASM plugins with minimal overhead.
///
/// Design decisions:
/// - Uses interpreter approach (like Wasm3) for fast cold starts and small footprint
/// - No JIT compilation to maintain cross-platform compatibility and reduce binary size
/// - Memory isolation: each plugin gets its own linear memory
/// - API surface: limited host functions exposed via imports
///
/// Note: This is a pure Zig implementation for maximum portability.
/// For production use with external WASM files, consider linking to Wasm3 C library.

pub const WasmError = error{
    InvalidModule,
    FunctionNotFound,
    ExecutionFailed,
    OutOfMemory,
    InvalidMemoryAccess,
    TypeMismatch,
    StackOverflow,
    UnsupportedInstruction,
};

/// WASM value types (MVP spec)
pub const ValueType = enum(u8) {
    i32 = 0x7F,
    i64 = 0x7E,
    f32 = 0x7D,
    f64 = 0x7C,
};

/// WASM runtime value (tagged union)
pub const Value = union(ValueType) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,

    pub fn asI32(self: Value) !i32 {
        return switch (self) {
            .i32 => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn asI64(self: Value) !i64 {
        return switch (self) {
            .i64 => |v| v,
            else => error.TypeMismatch,
        };
    }
};

/// WASM function signature
pub const FunctionSignature = struct {
    params: []const ValueType,
    results: []const ValueType,

    pub fn init(allocator: std.mem.Allocator, params: []const ValueType, results: []const ValueType) !FunctionSignature {
        return .{
            .params = try allocator.dupe(ValueType, params),
            .results = try allocator.dupe(ValueType, results),
        };
    }

    pub fn deinit(self: *FunctionSignature, allocator: std.mem.Allocator) void {
        allocator.free(self.params);
        allocator.free(self.results);
    }
};

/// WASM linear memory (sandboxed)
pub const Memory = struct {
    data: []u8,
    max_pages: ?u32, // null = unlimited

    const PAGE_SIZE: u32 = 65536; // 64 KiB

    pub fn init(allocator: std.mem.Allocator, initial_pages: u32, max_pages: ?u32) !Memory {
        const size = initial_pages * PAGE_SIZE;
        const data = try allocator.alloc(u8, size);
        @memset(data, 0);
        return .{
            .data = data,
            .max_pages = max_pages,
        };
    }

    pub fn deinit(self: *Memory, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }

    pub fn grow(self: *Memory, allocator: std.mem.Allocator, delta_pages: u32) !void {
        const current_pages = @as(u32, @intCast(self.data.len / PAGE_SIZE));
        const new_pages = current_pages + delta_pages;

        if (self.max_pages) |max| {
            if (new_pages > max) return error.OutOfMemory;
        }

        const new_size = new_pages * PAGE_SIZE;
        self.data = try allocator.realloc(self.data, new_size);
        // Zero out new memory
        @memset(self.data[current_pages * PAGE_SIZE ..], 0);
    }

    pub fn read(self: *const Memory, offset: u32, len: u32) ![]const u8 {
        if (offset + len > self.data.len) return error.InvalidMemoryAccess;
        return self.data[offset .. offset + len];
    }

    pub fn write(self: *Memory, offset: u32, data: []const u8) !void {
        if (offset + data.len > self.data.len) return error.InvalidMemoryAccess;
        @memcpy(self.data[offset .. offset + data.len], data);
    }

    pub fn readI32(self: *const Memory, offset: u32) !i32 {
        const bytes = try self.read(offset, 4);
        return std.mem.readInt(i32, bytes[0..4], .little);
    }

    pub fn writeI32(self: *Memory, offset: u32, value: i32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(i32, &buf, value, .little);
        try self.write(offset, &buf);
    }
};

/// Host function callback
pub const HostFunction = *const fn (args: []const Value, allocator: std.mem.Allocator) WasmError!Value;

/// WASM module instance
pub const Instance = struct {
    allocator: std.mem.Allocator,
    memory: ?Memory,
    functions: std.StringHashMap(FunctionSignature),
    host_functions: std.StringHashMap(HostFunction),

    pub fn init(allocator: std.mem.Allocator) Instance {
        return .{
            .allocator = allocator,
            .memory = null,
            .functions = std.StringHashMap(FunctionSignature).init(allocator),
            .host_functions = std.StringHashMap(HostFunction).init(allocator),
        };
    }

    pub fn deinit(self: *Instance) void {
        if (self.memory) |*mem| {
            mem.deinit(self.allocator);
        }

        var func_iter = self.functions.iterator();
        while (func_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var mutable_sig = entry.value_ptr.*;
            mutable_sig.deinit(self.allocator);
        }
        self.functions.deinit();

        var host_iter = self.host_functions.keyIterator();
        while (host_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.host_functions.deinit();
    }

    /// Register a host function that can be called from WASM
    pub fn registerHostFunction(self: *Instance, name: []const u8, func: HostFunction) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.host_functions.put(name_copy, func);
    }

    /// Initialize linear memory
    pub fn initMemory(self: *Instance, initial_pages: u32, max_pages: ?u32) !void {
        self.memory = try Memory.init(self.allocator, initial_pages, max_pages);
    }

    /// Execute a WASM function by name
    pub fn call(self: *Instance, func_name: []const u8, args: []const Value) !Value {
        // Check if it's a host function
        if (self.host_functions.get(func_name)) |host_func| {
            return try host_func(args, self.allocator);
        }

        // For WASM functions, we'd need to load and interpret bytecode
        // This is a placeholder for the full interpreter implementation
        return error.FunctionNotFound;
    }

    /// Load a WASM module from bytes (stub for full implementation)
    pub fn loadModule(_: *Instance, _: []const u8) !void {
        // TODO: Implement WASM module parsing
        // 1. Validate magic number (0x00 0x61 0x73 0x6D)
        // 2. Parse sections (type, import, function, memory, export, code)
        // 3. Build function table
        // 4. Initialize memory
        return error.UnsupportedInstruction;
    }
};

/// Simple plugin interface for zr
pub const PluginInterface = struct {
    instance: Instance,

    pub fn init(allocator: std.mem.Allocator) PluginInterface {
        return .{
            .instance = Instance.init(allocator),
        };
    }

    pub fn deinit(self: *PluginInterface) void {
        self.instance.deinit();
    }

    /// Load a plugin from a WASM file
    pub fn loadFromFile(self: *PluginInterface, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const wasm_bytes = try file.readToEndAlloc(self.instance.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.instance.allocator.free(wasm_bytes);

        try self.instance.loadModule(wasm_bytes);
    }

    /// Register host functions for plugin lifecycle
    pub fn registerLifecycleHooks(self: *PluginInterface) !void {
        try self.instance.registerHostFunction("on_init", hostOnInit);
        try self.instance.registerHostFunction("on_task_start", hostOnTaskStart);
        try self.instance.registerHostFunction("on_task_end", hostOnTaskEnd);
    }
};

// Host function implementations
fn hostOnInit(_: []const Value, _: std.mem.Allocator) WasmError!Value {
    // Plugin initialization hook
    return Value{ .i32 = 0 }; // Success
}

fn hostOnTaskStart(_: []const Value, _: std.mem.Allocator) WasmError!Value {
    // Task start hook
    return Value{ .i32 = 0 };
}

fn hostOnTaskEnd(_: []const Value, _: std.mem.Allocator) WasmError!Value {
    // Task end hook
    return Value{ .i32 = 0 };
}

// Tests
test "Memory: init and deinit" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, null);
    defer mem.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 65536), mem.data.len);
}

test "Memory: grow" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, 4);
    defer mem.deinit(allocator);

    try mem.grow(allocator, 2);
    try std.testing.expectEqual(@as(usize, 196608), mem.data.len); // 3 pages

    // Should fail when exceeding max
    const result = mem.grow(allocator, 2);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "Memory: read and write" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, null);
    defer mem.deinit(allocator);

    const test_data = "Hello, WASM!";
    try mem.write(100, test_data);

    const read_data = try mem.read(100, test_data.len);
    try std.testing.expectEqualStrings(test_data, read_data);
}

test "Memory: readI32 and writeI32" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, null);
    defer mem.deinit(allocator);

    try mem.writeI32(0, 0x12345678);
    const value = try mem.readI32(0);
    try std.testing.expectEqual(@as(i32, 0x12345678), value);
}

test "Memory: invalid access" {
    const allocator = std.testing.allocator;
    var mem = try Memory.init(allocator, 1, null);
    defer mem.deinit(allocator);

    const result = mem.read(65536, 1);
    try std.testing.expectError(error.InvalidMemoryAccess, result);
}

test "Instance: init and deinit" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    try std.testing.expect(instance.memory == null);
}

test "Instance: init memory" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    try instance.initMemory(2, 10);
    try std.testing.expect(instance.memory != null);
    try std.testing.expectEqual(@as(usize, 131072), instance.memory.?.data.len); // 2 pages
}

test "Instance: register and call host function" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    try instance.registerHostFunction("test_func", hostOnInit);

    const args = [_]Value{};
    const result = try instance.call("test_func", &args);
    try std.testing.expectEqual(@as(i32, 0), try result.asI32());
}

test "Instance: call unknown function" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    const args = [_]Value{};
    const result = instance.call("unknown", &args);
    try std.testing.expectError(error.FunctionNotFound, result);
}

test "PluginInterface: init and deinit" {
    const allocator = std.testing.allocator;
    var plugin = PluginInterface.init(allocator);
    defer plugin.deinit();

    try plugin.registerLifecycleHooks();
}

test "Value: type conversions" {
    const v_i32 = Value{ .i32 = 42 };
    try std.testing.expectEqual(@as(i32, 42), try v_i32.asI32());

    const v_i64 = Value{ .i64 = 12345 };
    try std.testing.expectEqual(@as(i64, 12345), try v_i64.asI64());

    const result = v_i32.asI64();
    try std.testing.expectError(error.TypeMismatch, result);
}
