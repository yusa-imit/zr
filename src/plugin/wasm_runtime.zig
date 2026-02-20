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

/// WASM section IDs (MVP spec)
pub const SectionId = enum(u8) {
    custom = 0,
    type = 1,
    import = 2,
    function = 3,
    table = 4,
    memory = 5,
    global = 6,
    @"export" = 7,
    start = 8,
    element = 9,
    code = 10,
    data = 11,
    data_count = 12,
};

/// WASM opcodes (subset of MVP spec for basic operations)
pub const Opcode = enum(u8) {
    // Control flow
    @"unreachable" = 0x00,
    nop = 0x01,
    block = 0x02,
    loop = 0x03,
    @"if" = 0x04,
    @"else" = 0x05,
    end = 0x0B,
    br = 0x0C,
    br_if = 0x0D,
    br_table = 0x0E,
    @"return" = 0x0F,
    call = 0x10,
    call_indirect = 0x11,

    // Parametric
    drop = 0x1A,
    select = 0x1B,

    // Variable access
    local_get = 0x20,
    local_set = 0x21,
    local_tee = 0x22,
    global_get = 0x23,
    global_set = 0x24,

    // Memory
    i32_load = 0x28,
    i64_load = 0x29,
    i32_store = 0x36,
    i64_store = 0x37,
    memory_size = 0x3F,
    memory_grow = 0x40,

    // Constants
    i32_const = 0x41,
    i64_const = 0x42,
    f32_const = 0x43,
    f64_const = 0x44,

    // i32 operations
    i32_eqz = 0x45,
    i32_eq = 0x46,
    i32_ne = 0x47,
    i32_lt_s = 0x48,
    i32_lt_u = 0x49,
    i32_gt_s = 0x4A,
    i32_gt_u = 0x4B,
    i32_le_s = 0x4C,
    i32_le_u = 0x4D,
    i32_ge_s = 0x4E,
    i32_ge_u = 0x4F,

    i32_clz = 0x67,
    i32_ctz = 0x68,
    i32_popcnt = 0x69,
    i32_add = 0x6A,
    i32_sub = 0x6B,
    i32_mul = 0x6C,
    i32_div_s = 0x6D,
    i32_div_u = 0x6E,
    i32_rem_s = 0x6F,
    i32_rem_u = 0x70,
    i32_and = 0x71,
    i32_or = 0x72,
    i32_xor = 0x73,
    i32_shl = 0x74,
    i32_shr_s = 0x75,
    i32_shr_u = 0x76,
    i32_rotl = 0x77,
    i32_rotr = 0x78,

    _,
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

/// WASM function code
pub const FunctionCode = struct {
    locals: []ValueType,
    body: []u8, // Raw bytecode

    pub fn deinit(self: *FunctionCode, allocator: std.mem.Allocator) void {
        allocator.free(self.locals);
        allocator.free(self.body);
    }
};

/// Binary reader for WASM module parsing
pub const BinaryReader = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) BinaryReader {
        return .{ .data = data, .pos = 0 };
    }

    pub fn hasMore(self: *const BinaryReader) bool {
        return self.pos < self.data.len;
    }

    pub fn readByte(self: *BinaryReader) !u8 {
        if (self.pos >= self.data.len) return error.InvalidModule;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    pub fn readBytes(self: *BinaryReader, len: usize) ![]const u8 {
        if (self.pos + len > self.data.len) return error.InvalidModule;
        const bytes = self.data[self.pos .. self.pos + len];
        self.pos += len;
        return bytes;
    }

    pub fn readU32(self: *BinaryReader) !u32 {
        const bytes = try self.readBytes(4);
        return std.mem.readInt(u32, bytes[0..4], .little);
    }

    /// Read LEB128 unsigned integer
    pub fn readVarU32(self: *BinaryReader) !u32 {
        var result: u32 = 0;
        var shift: u5 = 0;
        while (true) {
            const byte = try self.readByte();
            result |= (@as(u32, byte & 0x7F) << shift);
            if ((byte & 0x80) == 0) break;
            shift += 7;
            if (shift >= 35) return error.InvalidModule; // Max 5 bytes for u32
        }
        return result;
    }

    /// Read LEB128 signed integer
    pub fn readVarI32(self: *BinaryReader) !i32 {
        var result: i32 = 0;
        var shift: u5 = 0;
        var byte: u8 = undefined;
        while (true) {
            byte = try self.readByte();
            result |= (@as(i32, @intCast(byte & 0x7F)) << shift);
            shift += 7;
            if ((byte & 0x80) == 0) break;
            if (shift >= 35) return error.InvalidModule;
        }
        // Sign extend if negative
        if (shift < 32 and (byte & 0x40) != 0) {
            result |= @as(i32, -1) << shift;
        }
        return result;
    }

    /// Read LEB128 signed 64-bit integer
    pub fn readVarI64(self: *BinaryReader) !i64 {
        var result: i64 = 0;
        var shift: u6 = 0;
        var byte: u8 = undefined;
        while (true) {
            byte = try self.readByte();
            result |= (@as(i64, @intCast(byte & 0x7F)) << shift);
            shift += 7;
            if ((byte & 0x80) == 0) break;
            if (shift >= 70) return error.InvalidModule;
        }
        // Sign extend if negative
        if (shift < 64 and (byte & 0x40) != 0) {
            result |= @as(i64, -1) << shift;
        }
        return result;
    }

    /// Read UTF-8 name (length-prefixed)
    pub fn readName(self: *BinaryReader, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.readVarU32();
        const bytes = try self.readBytes(len);
        return try allocator.dupe(u8, bytes);
    }

    /// Read value type
    pub fn readValueType(self: *BinaryReader) !ValueType {
        const byte = try self.readByte();
        return std.meta.intToEnum(ValueType, byte) catch error.InvalidModule;
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
    function_codes: std.ArrayList(FunctionCode),
    exports: std.StringHashMap(u32), // export name -> function index
    host_functions: std.StringHashMap(HostFunction),
    types: std.ArrayList(FunctionSignature), // Type section

    pub fn init(allocator: std.mem.Allocator) Instance {
        return .{
            .allocator = allocator,
            .memory = null,
            .functions = std.StringHashMap(FunctionSignature).init(allocator),
            .function_codes = .{},
            .exports = std.StringHashMap(u32).init(allocator),
            .host_functions = std.StringHashMap(HostFunction).init(allocator),
            .types = .{},
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

        for (self.function_codes.items) |*code| {
            code.deinit(self.allocator);
        }
        self.function_codes.deinit(self.allocator);

        var export_iter = self.exports.keyIterator();
        while (export_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.exports.deinit();

        var host_iter = self.host_functions.keyIterator();
        while (host_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.host_functions.deinit();

        for (self.types.items) |*sig| {
            var mutable_sig = sig.*;
            mutable_sig.deinit(self.allocator);
        }
        self.types.deinit(self.allocator);
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

    /// Load a WASM module from bytes
    pub fn loadModule(self: *Instance, bytes: []const u8) !void {
        var reader = BinaryReader.init(bytes);

        // 1. Validate magic number (0x00 0x61 0x73 0x6D)
        const magic = try reader.readU32();
        if (magic != 0x6D736100) { // "\0asm" in little-endian
            return error.InvalidModule;
        }

        // 2. Validate version (currently only version 1 is supported)
        const version = try reader.readU32();
        if (version != 1) {
            return error.InvalidModule;
        }

        // 3. Parse sections
        while (reader.hasMore()) {
            const section_id_byte = try reader.readByte();
            const section_size = try reader.readVarU32();
            const section_start = reader.pos;

            const section_id = std.meta.intToEnum(SectionId, section_id_byte) catch {
                // Unknown section, skip it
                reader.pos = section_start + section_size;
                continue;
            };

            switch (section_id) {
                .type => try self.parseTypeSection(&reader),
                .import => try self.parseImportSection(&reader),
                .function => try self.parseFunctionSection(&reader),
                .memory => try self.parseMemorySection(&reader),
                .@"export" => try self.parseExportSection(&reader),
                .code => try self.parseCodeSection(&reader),
                else => {
                    // Skip unsupported sections for now
                    reader.pos = section_start + section_size;
                },
            }
        }
    }

    fn parseTypeSection(self: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const form = try reader.readByte();
            if (form != 0x60) return error.InvalidModule; // func type

            // Read parameters
            const param_count = try reader.readVarU32();
            const params = try self.allocator.alloc(ValueType, param_count);
            errdefer self.allocator.free(params);

            var j: u32 = 0;
            while (j < param_count) : (j += 1) {
                params[j] = try reader.readValueType();
            }

            // Read results
            const result_count = try reader.readVarU32();
            const results = try self.allocator.alloc(ValueType, result_count);
            errdefer self.allocator.free(results);

            j = 0;
            while (j < result_count) : (j += 1) {
                results[j] = try reader.readValueType();
            }

            try self.types.append(self.allocator, .{ .params = params, .results = results });
        }
    }

    fn parseImportSection(_: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            // Skip module name
            const mod_len = try reader.readVarU32();
            _ = try reader.readBytes(mod_len);

            // Skip field name
            const field_len = try reader.readVarU32();
            _ = try reader.readBytes(field_len);

            // Skip import kind and type
            const kind = try reader.readByte();
            switch (kind) {
                0 => _ = try reader.readVarU32(), // function
                1 => { // table
                    _ = try reader.readByte(); // elem type
                    _ = try reader.readByte(); // flags
                    _ = try reader.readVarU32(); // initial
                },
                2 => { // memory
                    _ = try reader.readByte(); // flags
                    _ = try reader.readVarU32(); // initial
                },
                3 => { // global
                    _ = try reader.readByte(); // type
                    _ = try reader.readByte(); // mutability
                },
                else => return error.InvalidModule,
            }
        }
    }

    fn parseFunctionSection(self: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const type_idx = try reader.readVarU32();
            if (type_idx >= self.types.items.len) return error.InvalidModule;
            // Store type index (will be used when parsing code section)
        }
    }

    fn parseMemorySection(self: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        if (count > 1) return error.InvalidModule; // MVP allows only 1 memory

        if (count == 1) {
            const flags = try reader.readByte();
            const initial = try reader.readVarU32();
            const max: ?u32 = if (flags & 0x01 != 0) try reader.readVarU32() else null;

            try self.initMemory(initial, max);
        }
    }

    fn parseExportSection(self: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const name = try reader.readName(self.allocator);
            errdefer self.allocator.free(name);

            const kind = try reader.readByte();
            const index = try reader.readVarU32();

            if (kind == 0) { // function export
                try self.exports.put(name, index);
            } else {
                self.allocator.free(name); // We only handle function exports for now
            }
        }
    }

    fn parseCodeSection(self: *Instance, reader: *BinaryReader) !void {
        const count = try reader.readVarU32();
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const code_size = try reader.readVarU32();
            const code_start = reader.pos;

            // Parse locals
            const local_count = try reader.readVarU32();
            var locals: std.ArrayList(ValueType) = .{};
            errdefer locals.deinit(self.allocator);

            var j: u32 = 0;
            while (j < local_count) : (j += 1) {
                const n = try reader.readVarU32();
                const val_type = try reader.readValueType();
                var k: u32 = 0;
                while (k < n) : (k += 1) {
                    try locals.append(self.allocator, val_type);
                }
            }

            // Read function body (raw bytecode)
            const body_size = code_size - (reader.pos - code_start);
            const body = try reader.readBytes(body_size);
            const body_copy = try self.allocator.dupe(u8, body);

            try self.function_codes.append(self.allocator, .{
                .locals = try locals.toOwnedSlice(self.allocator),
                .body = body_copy,
            });
        }
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

test "BinaryReader: readByte" {
    const data = [_]u8{ 0x01, 0x02, 0x03 };
    var reader = BinaryReader.init(&data);

    try std.testing.expectEqual(@as(u8, 0x01), try reader.readByte());
    try std.testing.expectEqual(@as(u8, 0x02), try reader.readByte());
    try std.testing.expectEqual(@as(u8, 0x03), try reader.readByte());

    const result = reader.readByte();
    try std.testing.expectError(error.InvalidModule, result);
}

test "BinaryReader: readVarU32" {
    // Single byte
    {
        const data = [_]u8{0x05};
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(u32, 5), try reader.readVarU32());
    }

    // Multi-byte
    {
        const data = [_]u8{ 0xE5, 0x8E, 0x26 }; // 624485 in LEB128
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(u32, 624485), try reader.readVarU32());
    }
}

test "BinaryReader: readVarI32" {
    // Positive
    {
        const data = [_]u8{0x05};
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(i32, 5), try reader.readVarI32());
    }

    // Negative
    {
        const data = [_]u8{0x7F}; // -1 in LEB128
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(i32, -1), try reader.readVarI32());
    }
}

test "BinaryReader: readVarI64" {
    // Positive
    {
        const data = [_]u8{0x05};
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(i64, 5), try reader.readVarI64());
    }

    // Negative
    {
        const data = [_]u8{0x7F}; // -1 in LEB128
        var reader = BinaryReader.init(&data);
        try std.testing.expectEqual(@as(i64, -1), try reader.readVarI64());
    }
}

test "BinaryReader: readName" {
    const allocator = std.testing.allocator;
    const data = [_]u8{ 0x05, 'h', 'e', 'l', 'l', 'o' };
    var reader = BinaryReader.init(&data);

    const name = try reader.readName(allocator);
    defer allocator.free(name);

    try std.testing.expectEqualStrings("hello", name);
}

test "Instance: loadModule - invalid magic" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    const bad_module = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    const result = instance.loadModule(&bad_module);
    try std.testing.expectError(error.InvalidModule, result);
}

test "Instance: loadModule - minimal valid module" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    // Minimal WASM module: magic + version
    const minimal_module = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version 1
    };

    try instance.loadModule(&minimal_module);
}

test "Instance: loadModule - module with type section" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    // WASM module with type section: one function type (i32) -> i32
    const module = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version
        0x01, // type section
        0x07, // section size
        0x01, // 1 type
        0x60, // func type
        0x01, 0x7F, // 1 param: i32
        0x01, 0x7F, // 1 result: i32
    };

    try instance.loadModule(&module);
    try std.testing.expectEqual(@as(usize, 1), instance.types.items.len);
    try std.testing.expectEqual(@as(usize, 1), instance.types.items[0].params.len);
    try std.testing.expectEqual(@as(usize, 1), instance.types.items[0].results.len);
    try std.testing.expectEqual(ValueType.i32, instance.types.items[0].params[0]);
    try std.testing.expectEqual(ValueType.i32, instance.types.items[0].results[0]);
}

test "Instance: loadModule - module with memory section" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    // WASM module with memory section: 1 page initial, 10 pages max
    const module = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version
        0x05, // memory section
        0x04, // section size
        0x01, // 1 memory
        0x01, // flags: has max
        0x01, // initial: 1
        0x0A, // max: 10
    };

    try instance.loadModule(&module);
    try std.testing.expect(instance.memory != null);
    try std.testing.expectEqual(@as(usize, 65536), instance.memory.?.data.len);
}

test "Instance: loadModule - module with export section" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    // WASM module with export section: export function 0 as "test"
    const module = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version
        0x07, // export section
        0x08, // section size
        0x01, // 1 export
        0x04, 't', 'e', 's', 't', // name: "test"
        0x00, // kind: function
        0x00, // index: 0
    };

    try instance.loadModule(&module);
    try std.testing.expectEqual(@as(usize, 1), instance.exports.count());
    try std.testing.expect(instance.exports.contains("test"));
    try std.testing.expectEqual(@as(u32, 0), instance.exports.get("test").?);
}

test "Instance: loadModule - complete module" {
    const allocator = std.testing.allocator;
    var instance = Instance.init(allocator);
    defer instance.deinit();

    // Complete WASM module:
    // - Type section: (i32) -> i32
    // - Function section: 1 function of type 0
    // - Memory section: 1 page
    // - Export section: export function 0 as "add"
    // - Code section: empty function body
    const module = [_]u8{
        0x00, 0x61, 0x73, 0x6D, // magic
        0x01, 0x00, 0x00, 0x00, // version

        // Type section
        0x01, 0x07, 0x01, 0x60, 0x01, 0x7F, 0x01, 0x7F,

        // Function section
        0x03, 0x02, 0x01, 0x00, // 1 function, type 0

        // Memory section
        0x05, 0x03, 0x01, 0x00, 0x01, // 1 memory, no max, 1 page

        // Export section
        0x07, 0x07, 0x01, 0x03, 'a', 'd', 'd', 0x00, 0x00,

        // Code section
        0x0A, 0x09, 0x01, // code section, 1 function
        0x07, // code size
        0x00, // 0 locals
        0x20, 0x00, // local.get 0
        0x41, 0x01, // i32.const 1
        0x6A, // i32.add
        0x0B, // end
    };

    try instance.loadModule(&module);

    // Verify parsed data
    try std.testing.expectEqual(@as(usize, 1), instance.types.items.len);
    try std.testing.expect(instance.memory != null);
    try std.testing.expectEqual(@as(usize, 1), instance.exports.count());
    try std.testing.expectEqual(@as(usize, 1), instance.function_codes.items.len);

    // Verify export
    try std.testing.expect(instance.exports.contains("add"));
    try std.testing.expectEqual(@as(u32, 0), instance.exports.get("add").?);

    // Verify function code
    const code = instance.function_codes.items[0];
    try std.testing.expectEqual(@as(usize, 0), code.locals.len);
    try std.testing.expect(code.body.len > 0);
}
