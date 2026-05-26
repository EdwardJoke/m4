const std = @import("std");
const serde = @import("serde");

pub const Severity = enum {
    @"error",
    warning,
    note,
    hint,

    pub const serde = .{ .enum_repr = .string };
};

pub const SourceLocation = struct {
    file: []const u8,
    line: u32,
    column: u32,
};

pub const Diagnostic = struct {
    severity: Severity,
    code: []const u8,
    message: []const u8,
    location: ?SourceLocation = null,
    hint: ?[]const u8 = null,
};

pub const Format = enum {
    zon,
    json,
    yaml,

    pub fn fromString(s: []const u8) ?Format {
        const map = std.StaticStringMap(Format).initComptime(.{
            .{ "zon", .zon },
            .{ "json", .json },
            .{ "yaml", .yaml },
        });
        return map.get(s);
    }
};

pub const DiagnosticList = struct {
    diagnostics: std.ArrayListUnmanaged(Diagnostic) = .{ .items = &.{}, .capacity = 0 },
    error_count: u32 = 0,
    warning_count: u32 = 0,

    pub fn init() DiagnosticList {
        return .{};
    }

    pub fn deinit(self: *DiagnosticList, allocator: std.mem.Allocator) void {
        self.diagnostics.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(self: *DiagnosticList, allocator: std.mem.Allocator, d: Diagnostic) !void {
        try self.diagnostics.append(allocator, d);
        switch (d.severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            else => {},
        }
    }

    pub fn hasErrors(self: *const DiagnosticList) bool {
        return self.error_count > 0;
    }

    pub fn items(self: *const DiagnosticList) []const Diagnostic {
        return self.diagnostics.items;
    }
};

pub fn formatDiagnostics(
    allocator: std.mem.Allocator,
    diagnostics: []const Diagnostic,
    format: Format,
) ![]const u8 {
    return switch (format) {
        .zon => try serde.zon.toSlice(allocator, diagnostics),
        .json => try serde.json.toSlice(allocator, diagnostics),
        .yaml => try serde.yaml.toSlice(allocator, diagnostics),
    };
}

// ── Error code registry ─────────────────────────────────────────────

pub const ErrorInfo = struct {
    code: []const u8,
    title: []const u8,
    description: []const u8,
};

pub const ERROR_DB = [_]ErrorInfo{
    // Parse errors
    .{ .code = "p001", .title = "Parse Error", .description = "The source contains a syntax error — an unexpected token, missing delimiter, or malformed expression." },

    // Type errors
    .{ .code = "t001", .title = "Type Mismatch", .description = "A value was used in a context that expects a different type. This includes passing the wrong type to a function, assigning an incompatible value, or using an operator on unsupported types." },

    // Compile errors
    .{ .code = "c001", .title = "Compile Error", .description = "The compiler could not translate the AST into bytecode. This is usually caused by an unsupported language construct or an internal compiler limit." },
    .{ .code = "c002", .title = "Continue Outside Loop", .description = "A `continue` statement was used outside of a loop body." },
    .{ .code = "c003", .title = "Esc Outside Loop", .description = "An `esc` (escape/break) statement was used outside of a loop body." },
    .{ .code = "c004", .title = "Too Many Constants", .description = "The chunk constant table exceeded the maximum size (65535 entries). Split the code into smaller functions." },

    // Runtime errors
    .{ .code = "r001", .title = "Undefined Variable", .description = "A global variable was referenced before being assigned a value." },
    .{ .code = "r002", .title = "Type Mismatch in Binary Operation", .description = "A binary operator (+, -, *, /) was applied to incompatible types — e.g., adding an integer to a boolean." },
    .{ .code = "r003", .title = "Type Mismatch in Modulo", .description = "The modulo operator (%) was applied to non-integer values. Modulo requires both operands to be integers." },
    .{ .code = "r004", .title = "Type Mismatch in Negation", .description = "The unary negation operator (-) was applied to a non-numeric value." },
    .{ .code = "r005", .title = "Type Mismatch in Comparison", .description = "A comparison operator (>, <, >=, <=) was applied to incompatible types. Comparisons require both operands to be numbers or both operands to be strings." },
    .{ .code = "r006", .title = "Stack Overflow", .description = "The call stack exceeded the maximum depth of 64 frames. This is usually caused by infinite recursion." },
    .{ .code = "r007", .title = "Value Not Callable", .description = "A value that is not a function was used as the callee in a call expression." },
    .{ .code = "r008", .title = "Index Out of Bounds", .description = "A vector/string index was outside the valid range [0, length)." },
    .{ .code = "r009", .title = "Not Indexable", .description = "An index operation was applied to a value that is not a vector or string." },
    .{ .code = "r010", .title = "Nil Propagation", .description = "A nil value was unwrapped with the `!` (try) operator. Nil values must be handled before unwrapping." },
    .{ .code = "r011", .title = "Unknown Opcode", .description = "The VM encountered an unrecognized bytecode instruction. This indicates either a compiler bug or corrupted bytecode." },
};

pub fn explainError(allocator: std.mem.Allocator, code: []const u8, format: ?Format) ![]const u8 {
    const info = lookupError(code) orelse {
        return std.fmt.allocPrint(allocator, "Unknown error code: {s}", .{code});
    };

    if (format) |fmt| {
        return switch (fmt) {
            .zon => try serde.zon.toSlice(allocator, info),
            .json => try serde.json.toSlice(allocator, info),
            .yaml => try serde.yaml.toSlice(allocator, info),
        };
    }

    return std.fmt.allocPrint(allocator,
        \\[{s}] {s}
        \\
        \\{s}
    , .{ info.code, info.title, info.description });
}

fn lookupError(code: []const u8) ?ErrorInfo {
    for (ERROR_DB) |info| {
        if (std.mem.eql(u8, info.code, code)) return info;
    }
    return null;
}
