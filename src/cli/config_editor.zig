const std = @import("std");
const sailor = @import("sailor");
const config_types = @import("../config/types.zig");
const config_parser = @import("../config/parser.zig");
const color_mod = @import("../output/color.zig");
const toml_highlight = @import("../config/toml_highlight.zig");

const Allocator = std.mem.Allocator;

/// Interactive TUI configuration editor
pub const ConfigEditor = struct {
    allocator: Allocator,
    mode: EditorMode,
    fields: std.ArrayList(Field),
    current_field: usize,
    preview_buffer: std.ArrayList(u8),

    pub const EditorMode = enum {
        task,
        workflow,
        profile,
    };

    pub const Field = struct {
        name: []const u8,
        prompt: []const u8,
        value: std.ArrayList(u8),
        required: bool,
        help: []const u8,
    };

    pub fn init(allocator: Allocator, mode: EditorMode) !ConfigEditor {
        var fields = std.ArrayList(Field){};
        errdefer fields.deinit(allocator);

        // Initialize fields based on mode
        switch (mode) {
            .task => try initTaskFields(allocator, &fields),
            .workflow => try initWorkflowFields(allocator, &fields),
            .profile => try initProfileFields(allocator, &fields),
        }

        return ConfigEditor{
            .allocator = allocator,
            .mode = mode,
            .fields = fields,
            .current_field = 0,
            .preview_buffer = std.ArrayList(u8){},
        };
    }

    pub fn deinit(self: *ConfigEditor) void {
        for (self.fields.items) |*field| {
            field.value.deinit(self.allocator);
        }
        self.fields.deinit(self.allocator);
        self.preview_buffer.deinit(self.allocator);
    }

    /// Run the interactive editor
    pub fn run(self: *ConfigEditor, w: anytype, ew: anytype, use_color: bool) !u8 {
        // Print header
        const title = switch (self.mode) {
            .task => "Create New Task",
            .workflow => "Create New Workflow",
            .profile => "Create New Profile",
        };
        try w.print("\n=== {s} ===\n\n", .{title});
        try w.flush();

        const stdin = std.fs.File.stdin();

        // Collect input for each field
        for (self.fields.items) |*field| {
            try w.print("{s}", .{field.prompt});
            if (!field.required) {
                try w.writeAll(" (optional)");
            }
            try w.writeAll(": ");

            // Show help hint
            if (field.help.len > 0) {
                try w.print("\n  💡 {s}\n> ", .{field.help});
            }
            try w.flush(); // CRITICAL: flush before reading stdin

            // Read line from stdin byte by byte
            var buffer = std.ArrayList(u8){};
            defer buffer.deinit(self.allocator);

            var read_buf: [1]u8 = undefined;
            while (true) {
                const n = stdin.read(&read_buf) catch |err| {
                    if (err == error.EndOfStream or err == error.NotOpenForReading) {
                        try color_mod.printError(ew, use_color, "\nCancelled by user\n", .{});
                        return 1;
                    }
                    return err;
                };
                if (n == 0) {
                    // EOF
                    try color_mod.printError(ew, use_color, "\nCancelled by user\n", .{});
                    return 1;
                }
                const ch = read_buf[0];
                if (ch == '\n') break;
                if (ch != '\r') {
                    // Skip carriage return
                    try buffer.append(self.allocator, ch);
                }
            }

            const line = buffer.items;
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (field.required and trimmed.len == 0) {
                try ew.writeAll("  ❌ This field is required!\n\n");
                return 1;
            }
            if (trimmed.len > 0) {
                try field.value.appendSlice(self.allocator, trimmed);
            }
        }

        // Generate TOML
        const toml = try self.generateToml();
        defer self.allocator.free(toml);

        // Show preview with syntax highlighting
        try w.writeAll("\n--- Generated TOML ---\n");
        if (use_color) {
            // Highlight TOML syntax
            const highlighted = toml_highlight.highlightToml(self.allocator, toml) catch toml;
            defer if (highlighted.ptr != toml.ptr) self.allocator.free(highlighted);
            try w.writeAll(highlighted);
        } else {
            try w.writeAll(toml);
        }
        try w.writeAll("\n\n");
        try w.flush();

        // Confirm
        try w.writeAll("Add to zr.toml? [Y/n]: ");
        try w.flush();

        var confirm_buffer = std.ArrayList(u8){};
        defer confirm_buffer.deinit(self.allocator);

        var read_buf: [1]u8 = undefined;
        while (true) {
            const n = stdin.read(&read_buf) catch |err| {
                if (err == error.EndOfStream or err == error.NotOpenForReading) {
                    try color_mod.printError(ew, use_color, "\nCancelled by user\n", .{});
                    return 1;
                }
                return err;
            };
            if (n == 0) break;
            const ch = read_buf[0];
            if (ch == '\n') break;
            if (ch != '\r') {
                try confirm_buffer.append(self.allocator, ch);
            }
        }

        const confirm = confirm_buffer.items;
        const trimmed = std.mem.trim(u8, confirm, &std.ascii.whitespace);
        if (trimmed.len > 0 and (trimmed[0] == 'n' or trimmed[0] == 'N')) {
            try w.writeAll("Cancelled.\n");
            return 1;
        }

        // Append to zr.toml
        const cwd = std.fs.cwd();
        const file = cwd.openFile("zr.toml", .{ .mode = .read_write }) catch |err| {
            if (err == error.FileNotFound) {
                try ew.writeAll("Error: zr.toml not found. Run `zr init` first.\n");
                return 1;
            }
            return err;
        };
        defer file.close();

        // Seek to end
        try file.seekFromEnd(0);

        // Write newline + generated TOML
        try file.writeAll("\n");
        try file.writeAll(toml);
        try file.writeAll("\n");

        try color_mod.printSuccess(w, use_color, "✓ Added to zr.toml\n", .{});
        return 0;
    }

    fn generateToml(self: *ConfigEditor) ![]const u8 {
        var buffer = std.ArrayList(u8){};
        errdefer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);

        switch (self.mode) {
            .task => try self.generateTaskToml(writer),
            .workflow => try self.generateWorkflowToml(writer),
            .profile => try self.generateProfileToml(writer),
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    fn generateTaskToml(self: *ConfigEditor, writer: anytype) !void {
        // Extract field values
        const name = if (self.fields.items.len > 0) self.fields.items[0].value.items else "example";
        const cmd = if (self.fields.items.len > 1) self.fields.items[1].value.items else "";
        const desc = if (self.fields.items.len > 2) self.fields.items[2].value.items else "";

        try writer.print("[tasks.{s}]\n", .{name});
        if (desc.len > 0) {
            try writer.print("description = \"{s}\"\n", .{desc});
        }
        try writer.print("cmd = \"{s}\"\n", .{cmd});
    }

    fn generateWorkflowToml(self: *ConfigEditor, writer: anytype) !void {
        const name = if (self.fields.items.len > 0) self.fields.items[0].value.items else "example";
        try writer.print("[[workflows]]\nname = \"{s}\"\n\n", .{name});
        try writer.writeAll("[[workflows.stages]]\nname = \"default\"\ntasks = []\n");
    }

    fn generateProfileToml(self: *ConfigEditor, writer: anytype) !void {
        const name = if (self.fields.items.len > 0) self.fields.items[0].value.items else "example";
        try writer.print("[profiles.{s}]\nenv = {{}}\n", .{name});
    }

    fn initTaskFields(allocator: Allocator, fields: *std.ArrayList(Field)) !void {
        try fields.append(allocator, Field{
            .name = "name",
            .prompt = "Task name",
            .value = std.ArrayList(u8){},
            .required = true,
            .help = "Unique identifier (alphanumeric, underscores, hyphens)",
        });
        try fields.append(allocator, Field{
            .name = "cmd",
            .prompt = "Command",
            .value = std.ArrayList(u8){},
            .required = true,
            .help = "Shell command to execute (e.g., 'npm run build')",
        });
        try fields.append(allocator, Field{
            .name = "description",
            .prompt = "Description",
            .value = std.ArrayList(u8){},
            .required = false,
            .help = "Brief description of what this task does",
        });
    }

    fn initWorkflowFields(allocator: Allocator, fields: *std.ArrayList(Field)) !void {
        try fields.append(allocator, Field{
            .name = "name",
            .prompt = "Workflow name",
            .value = std.ArrayList(u8){},
            .required = true,
            .help = "Unique workflow identifier",
        });
    }

    fn initProfileFields(allocator: Allocator, fields: *std.ArrayList(Field)) !void {
        try fields.append(allocator, Field{
            .name = "name",
            .prompt = "Profile name",
            .value = std.ArrayList(u8){},
            .required = true,
            .help = "Profile identifier (e.g., 'dev', 'prod')",
        });
    }
};

/// Entry point for `zr edit` command
pub fn cmdEdit(
    allocator: Allocator,
    entity_type: []const u8,
    args: []const []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    _ = args;

    const mode: ConfigEditor.EditorMode = blk: {
        if (std.mem.eql(u8, entity_type, "task")) break :blk .task;
        if (std.mem.eql(u8, entity_type, "workflow")) break :blk .workflow;
        if (std.mem.eql(u8, entity_type, "profile")) break :blk .profile;

        try color_mod.printError(ew, use_color, "Invalid entity type: {s}\n", .{entity_type});
        try ew.writeAll("Valid types: task, workflow, profile\n");
        return 1;
    };

    var editor = try ConfigEditor.init(allocator, mode);
    defer editor.deinit();

    return try editor.run(w, ew, use_color);
}

test "ConfigEditor.generateToml produces valid TOML" {
    const allocator = std.testing.allocator;
    var editor = try ConfigEditor.init(allocator, .task);
    defer editor.deinit();

    // Populate fields
    if (editor.fields.items.len > 0) {
        try editor.fields.items[0].value.appendSlice(allocator, "build");
    }
    if (editor.fields.items.len > 1) {
        try editor.fields.items[1].value.appendSlice(allocator, "npm run build");
    }
    if (editor.fields.items.len > 2) {
        try editor.fields.items[2].value.appendSlice(allocator, "Build the project");
    }

    const toml = try editor.generateToml();
    defer allocator.free(toml);

    try std.testing.expect(std.mem.indexOf(u8, toml, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml, "cmd = ") != null);
}

test "ConfigEditor generates workflow TOML" {
    const allocator = std.testing.allocator;
    var editor = try ConfigEditor.init(allocator, .workflow);
    defer editor.deinit();

    if (editor.fields.items.len > 0) {
        try editor.fields.items[0].value.appendSlice(allocator, "release");
    }

    const toml = try editor.generateToml();
    defer allocator.free(toml);

    try std.testing.expect(std.mem.indexOf(u8, toml, "[[workflows]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml, "[[workflows.stages]]") != null);
}

test "ConfigEditor generates profile TOML" {
    const allocator = std.testing.allocator;
    var editor = try ConfigEditor.init(allocator, .profile);
    defer editor.deinit();

    if (editor.fields.items.len > 0) {
        try editor.fields.items[0].value.appendSlice(allocator, "production");
    }

    const toml = try editor.generateToml();
    defer allocator.free(toml);

    try std.testing.expect(std.mem.indexOf(u8, toml, "[profiles.production]") != null);
}
