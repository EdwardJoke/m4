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

        /// Create an empty diagnostic list.
    pub fn init() DiagnosticList {
        return .{};
    }

    /// Deinitialize the diagnostic list, freeing all owned memory.
    pub fn deinit(self: *DiagnosticList, allocator: std.mem.Allocator) void {
        self.diagnostics.deinit(allocator);
        self.* = undefined;
    }

    /// Add a diagnostic to the list, incrementing the appropriate severity counter.
    pub fn add(self: *DiagnosticList, allocator: std.mem.Allocator, d: Diagnostic) !void {
        try self.diagnostics.append(allocator, d);
        switch (d.severity) {
            .@"error" => self.error_count += 1,
            .warning => self.warning_count += 1,
            else => {},
        }
    }

    /// Returns true if any error-severity diagnostics have been added.
    pub fn hasErrors(self: *const DiagnosticList) bool {
        return self.error_count > 0;
    }

    /// Return all diagnostics in the list.
    pub fn items(self: *const DiagnosticList) []const Diagnostic {
        return self.diagnostics.items;
    }
};

/// Serialize a slice of diagnostics to the given format (ZON, JSON, or YAML).
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

/// When true, error output includes ANSI color codes for terminal readability.
pub var pretty: bool = false;

pub const ERROR_DB = [_]ErrorInfo{
    // ── Parse errors (p001–p009) ──────────────────────────────────────
    .{ .code = "p001", .title = "Syntax Error", .description = "The source contains a syntax error — an unexpected token, missing delimiter, or malformed expression." },
    .{ .code = "p002", .title = "Unexpected End of Input", .description = "The source ended unexpectedly, usually due to an incomplete expression, missing block, or unclosed delimiter." },
    .{ .code = "p003", .title = "Indentation Error", .description = "The indentation level doesn't match any enclosing block. m4 uses indentation to define code blocks — check that indentation is consistent (spaces only, no tabs)." },
    .{ .code = "p004", .title = "Invalid Literal", .description = "A numeric literal (integer or float) couldn't be parsed. Check for invalid characters or formatting in the number." },

    // ── Type errors (t001–t009) ───────────────────────────────────────
    .{ .code = "t001", .title = "Type Mismatch", .description = "A value was used in a context that expects a different type. This includes passing the wrong type to a function, assigning an incompatible value, or using an operator on unsupported types." },
    .{ .code = "t002", .title = "Undefined Variable", .description = "A variable was referenced before being declared in the current or any enclosing scope." },
    .{ .code = "t003", .title = "Duplicate Declaration", .description = "A variable with the same name was already declared in the current scope. Each variable name must be unique within its scope." },
    .{ .code = "t004", .title = "Type Mismatch in Binding", .description = "The value provided doesn't match the declared type of the variable. This applies to both `let` declarations and `mut` assignments. Check the variable's type annotation." },
    .{ .code = "t005", .title = "Return Type Mismatch", .description = "A `ret` value doesn't match the declared return type of the enclosing function." },
    .{ .code = "t006", .title = "Arity Mismatch", .description = "A function was called with the wrong number of arguments. Check the function signature for the expected parameter count." },
    .{ .code = "t007", .title = "Invalid Operator for Type", .description = "An operator was used with types that don't support it — e.g., arithmetic on booleans, or comparison on nil." },
    .{ .code = "t008", .title = "Assignment to Immutable Variable", .description = "An attempt was made to assign a new value to a variable declared with `let` (immutable). Use `mut` to declare a mutable variable." },
    .{ .code = "t009", .title = "ret Outside Function", .description = "A `ret` statement was used outside of a function body. `ret` can only appear inside `fun` blocks." },

    // ── Compile errors (c001–c009) ────────────────────────────────────
    .{ .code = "c001", .title = "Compile Error", .description = "The compiler could not translate the AST into bytecode. This is usually caused by an unsupported language construct or an internal compiler limit." },
    .{ .code = "c002", .title = "Continue Outside Loop", .description = "A `continue` statement was used outside of a loop body." },
    .{ .code = "c003", .title = "Esc Outside Loop", .description = "An `esc` (escape/break) statement was used outside of a loop body." },
    .{ .code = "c004", .title = "Too Many Constants", .description = "The chunk constant table exceeded the maximum size (65535 entries). Split the code into smaller functions." },
    .{ .code = "c005", .title = "Too Many Locals", .description = "A function body declares more local variables than the VM supports (256 maximum). Reduce the number of local variables." },
    .{ .code = "c006", .title = "Compile Error in Function", .description = "An error occurred while compiling a function body. The error message will indicate which function and what went wrong." },

    // ── Runtime errors (r001–r019) ────────────────────────────────────
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
    .{ .code = "r012", .title = "Division by Zero", .description = "A division operation had zero as the divisor. Division by zero is undefined." },
    .{ .code = "r013", .title = "Modulo by Zero", .description = "A modulo operation had zero as the divisor. Modulo by zero is undefined." },
    .{ .code = "r014", .title = "Out of Memory", .description = "The system allocator failed to allocate memory. This usually means the process has exhausted available memory." },
    .{ .code = "r015", .title = "Invalid Argument", .description = "A native function received an argument of the wrong type or an invalid value — e.g., passing a negative number to str.slice." },
    .{ .code = "r016", .title = "I/O Error", .description = "An input/output operation failed — e.g., reading from a closed stdin, writing to a read-only file, or a broken pipe." },
    .{ .code = "r017", .title = "Integer Overflow", .description = "An integer arithmetic operation (+, -, *, /, negation) produced a result that exceeds the range of i64. m4 uses 64-bit signed integers and detects overflow at runtime to prevent silent data corruption." },
};

/// Look up an error code in ERROR_DB and return a human-readable explanation.
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

// ── Pretty-printed error output ───────────────────────────────────

/// Print a formatted diagnostic error to stderr. When pretty mode is enabled,
/// applies ANSI colors: bold code, colored stage name, dim location.
pub fn printDiagnostic(code: []const u8, stage: []const u8, msg: []const u8, line: ?u32) void {
    if (pretty) {
        const stage_color = if (std.mem.eql(u8, stage, "Parse Error") or
            std.mem.eql(u8, stage, "Compile Error"))
            "\x1b[91m" // bright red
        else if (std.mem.eql(u8, stage, "Type Error"))
            "\x1b[93m" // bright yellow
        else
            "\x1b[91m"; // bright red (runtime)
        std.debug.print("\x1b[1m[{s}]\x1b[0m {s}{s}\x1b[0m: \x1b[37m{s}\x1b[0m", .{
            code, stage_color, stage, msg,
        });
        if (line) |l| {
            std.debug.print(" \x1b[2m[line {d}]\x1b[0m", .{l});
        }
        std.debug.print("\n", .{});
    } else {
        if (line) |l| {
            std.debug.print("[{s}] {s}: {s} [line {d}]\n", .{ code, stage, msg, l });
        } else {
            std.debug.print("[{s}] {s}: {s}\n", .{ code, stage, msg });
        }
    }
}
