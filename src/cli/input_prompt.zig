const std = @import("std");
const types = @import("../config/types.zig");

/// Errors from input collection and validation.
pub const InputError = error{
    RequiredInputMissing,
    InvalidInputType,
    InvalidInputChoice,
    InputMissing,
};

/// Validate a value against an InputPrompt's type and choices constraints.
pub fn validateInputValue(
    ip: types.InputPrompt,
    value: []const u8,
) InputError!void {
    // Type validation
    if (std.mem.eql(u8, ip.type, "number")) {
        _ = std.fmt.parseFloat(f64, value) catch {
            return InputError.InvalidInputType;
        };
    } else if (std.mem.eql(u8, ip.type, "bool")) {
        const valid = std.mem.eql(u8, value, "true") or
            std.mem.eql(u8, value, "false") or
            std.mem.eql(u8, value, "1") or
            std.mem.eql(u8, value, "0") or
            std.mem.eql(u8, value, "yes") or
            std.mem.eql(u8, value, "no");
        if (!valid) {
            return InputError.InvalidInputType;
        }
    }

    // Choices validation
    if (ip.choices.len > 0) {
        var valid_choice = false;
        for (ip.choices) |choice| {
            if (std.mem.eql(u8, value, choice)) {
                valid_choice = true;
                break;
            }
        }
        if (!valid_choice) {
            return InputError.InvalidInputChoice;
        }
    }
}

/// Collect all input values for the given input_prompts array.
/// Returns a map of name -> value for all collected inputs.
/// For non-interactive mode, uses defaults or fails for required inputs.
pub fn collectInputs(
    allocator: std.mem.Allocator,
    input_prompts: []const types.InputPrompt,
    cli_inputs: *const std.StringHashMap([]const u8),
    non_interactive: bool,
) !std.StringHashMap([]const u8) {
    var result = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = result.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }

    for (input_prompts) |ip| {
        // Priority 1: --input flag
        if (cli_inputs.get(ip.name)) |val| {
            try validateInputValue(ip, val);
            try result.put(try allocator.dupe(u8, ip.name), try allocator.dupe(u8, val));
            continue;
        }

        // Priority 2: default value (if non-interactive or not in tty)
        if (non_interactive) {
            if (ip.default) |def| {
                try result.put(try allocator.dupe(u8, ip.name), try allocator.dupe(u8, def));
            } else {
                return InputError.RequiredInputMissing;
            }
        } else {
            // Priority 3: interactive prompt (not implemented yet — use default)
            if (ip.default) |def| {
                try result.put(try allocator.dupe(u8, ip.name), try allocator.dupe(u8, def));
            } else {
                return InputError.RequiredInputMissing;
            }
        }
    }

    return result;
}

test "InputPrompt: validate number type accepts float" {
    const ip = types.InputPrompt{
        .name = "timeout",
        .prompt = "Timeout in seconds:",
        .type = "number",
    };
    try validateInputValue(ip, "3.14");
}

test "InputPrompt: validate number type rejects non-numeric" {
    const ip = types.InputPrompt{
        .name = "count",
        .prompt = "Count:",
        .type = "number",
    };
    try std.testing.expectError(InputError.InvalidInputType, validateInputValue(ip, "not-a-number"));
}

test "InputPrompt: validate bool type accepts true/false" {
    const ip = types.InputPrompt{
        .name = "debug",
        .prompt = "Enable debug:",
        .type = "bool",
    };
    try validateInputValue(ip, "true");
    try validateInputValue(ip, "false");
}

test "InputPrompt: validate bool type rejects invalid" {
    const ip = types.InputPrompt{
        .name = "verbose",
        .prompt = "Verbose:",
        .type = "bool",
    };
    try std.testing.expectError(InputError.InvalidInputType, validateInputValue(ip, "maybe"));
}

test "InputPrompt: validate choices constraint" {
    var choice_data = [_][]const u8{ "prod", "staging" };
    const ip = types.InputPrompt{
        .name = "env",
        .prompt = "Environment:",
        .choices = &choice_data,
    };

    try validateInputValue(ip, "prod");
    try std.testing.expectError(InputError.InvalidInputChoice, validateInputValue(ip, "invalid"));
}

test "InputPrompt: collectInputs with cli_inputs" {
    const allocator = std.testing.allocator;
    var cli_inputs = std.StringHashMap([]const u8).init(allocator);
    defer cli_inputs.deinit();
    try cli_inputs.put("ENV", "prod");

    const input_prompts = try allocator.alloc(types.InputPrompt, 1);
    defer allocator.free(input_prompts);
    input_prompts[0] = types.InputPrompt{
        .name = try allocator.dupe(u8, "ENV"),
        .prompt = try allocator.dupe(u8, "Environment:"),
        .type = try allocator.dupe(u8, "string"),
    };
    defer {
        for (input_prompts) |*ip| ip.deinit(allocator);
    }

    var result = try collectInputs(allocator, input_prompts, &cli_inputs, true);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }

    try std.testing.expectEqualStrings("prod", result.get("ENV").?);
}

test "InputPrompt: collectInputs uses default when non-interactive" {
    const allocator = std.testing.allocator;
    var cli_inputs = std.StringHashMap([]const u8).init(allocator);
    defer cli_inputs.deinit();

    const input_prompts = try allocator.alloc(types.InputPrompt, 1);
    defer allocator.free(input_prompts);
    input_prompts[0] = types.InputPrompt{
        .name = try allocator.dupe(u8, "TAG"),
        .prompt = try allocator.dupe(u8, "Tag:"),
        .default = try allocator.dupe(u8, "v1.0.0"),
        .type = try allocator.dupe(u8, "string"),
    };
    defer {
        for (input_prompts) |*ip| ip.deinit(allocator);
    }

    var result = try collectInputs(allocator, input_prompts, &cli_inputs, true);
    defer {
        var it = result.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }

    try std.testing.expectEqualStrings("v1.0.0", result.get("TAG").?);
}

test "InputPrompt: collectInputs fails for required input when non-interactive" {
    const allocator = std.testing.allocator;
    var cli_inputs = std.StringHashMap([]const u8).init(allocator);
    defer cli_inputs.deinit();

    const input_prompts = try allocator.alloc(types.InputPrompt, 1);
    defer allocator.free(input_prompts);
    input_prompts[0] = types.InputPrompt{
        .name = try allocator.dupe(u8, "PASSWORD"),
        .prompt = try allocator.dupe(u8, "Password:"),
        .type = try allocator.dupe(u8, "string"),
    };
    defer {
        for (input_prompts) |*ip| ip.deinit(allocator);
    }

    const result = collectInputs(allocator, input_prompts, &cli_inputs, true);
    try std.testing.expectError(InputError.RequiredInputMissing, result);
}
