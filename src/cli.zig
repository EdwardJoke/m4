const std = @import("std");
const posix = std.posix;
const maple = @import("maple");
const build_options = @import("build_options");

const Parser = maple.Parser;
const Compiler = maple.Compiler;
const VM = maple.VM;
const debug = maple.debug;

const VERSION = build_options.version;

const Flags = struct {
    debug_mode: bool = false,
    check_only: bool = false,
    format_mode: bool = false,
    file_path: ?[]const u8 = null,
    should_exit: bool = false,
    error_format: ?maple.err.Format = null,
};

pub fn run(init: std.process.Init) !void {
    const arena_alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena_alloc);

    const flags = try parseFlags(args);
    if (flags.should_exit) return;

    if (flags.file_path) |path| {
        if (std.mem.eql(u8, path, "-")) {
            const source = try readStdin(arena_alloc, init.io);
            try runSource(arena_alloc, source, flags);
        } else {
            const source = try readFile(arena_alloc, init.io, path);
            try runSource(arena_alloc, source, flags);
        }
    } else {
        try runRepl(arena_alloc);
    }
}

fn parseFlags(args: []const []const u8) !Flags {
    var flags = Flags{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return Flags{ .should_exit = true };
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return Flags{ .should_exit = true };
        }
        // Special: "-" means stdin
        if (std.mem.eql(u8, arg, "-")) {
            flags.file_path = "-";
            continue;
        }
        if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            flags.debug_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--check")) {
            flags.check_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            flags.format_mode = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--error-format=")) {
            const fmt_str = arg["--error-format=".len..];
            flags.error_format = maple.err.Format.fromString(fmt_str) orelse {
                std.debug.print("maple: unknown error format '{s}'. Use zon, json, or yaml.\n", .{fmt_str});
                return error.InvalidFlag;
            };
            continue;
        }
        if (!std.mem.startsWith(u8, arg, "-")) {
            flags.file_path = arg;
            continue;
        }
        std.debug.print("maple: unknown flag '{s}'\n", .{arg});
        std.debug.print("Try 'maple --help' for usage.\n", .{});
        return error.InvalidFlag;
    }
    return flags;
}

fn runSource(allocator: std.mem.Allocator, source: []const u8, flags: Flags) !void {
    var diag_list = maple.err.DiagnosticList.init();
    defer diag_list.deinit(allocator);

    var parser = Parser.init(allocator, source);
    defer parser.deinit();
    if (flags.error_format != null) {
        parser.diag = &diag_list;
    }

    const stmts = parser.parse() catch |err| {
        if (err == error.ParseError) {
            if (flags.error_format) |fmt| {
                const out = try maple.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            }
            return;
        }
        std.debug.print("Parse error: {}\n", .{err});
        return;
    };

    // Type checking
    if (flags.check_only) {
        var checker = maple.type_check.Checker.init(allocator, &parser.arena);
        defer checker.deinit();
        if (flags.error_format != null) checker.diag = &diag_list;
        checker.check(stmts) catch |err| {
            std.debug.print("Type check error: {}\n", .{err});
            return;
        };
        if (checker.error_count > 0) {
            if (flags.error_format) |fmt| {
                const out = try maple.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            } else {
                std.debug.print("{d} type error(s) found.\n", .{checker.error_count});
            }
        } else {
            std.debug.print("Type checking passed.\n", .{});
        }
        return;
    }

    if (flags.format_mode) {
        for (stmts) |s| {
            maple.fmt.formatNode(&parser.arena, s, 0);
            std.debug.print("\n", .{});
        }
        return;
    }

    // Resolve use statements + register builtin modules before compilation
    var vm = VM.init(allocator);
    defer vm.deinit();
    try resolveUses(&vm, &parser.arena, stmts);

    var compiler = Compiler.init(allocator, &parser.arena);
    defer compiler.deinit();

    compiler.compile(stmts) catch |err| {
        if (err == error.CompileError) return;
        std.debug.print("Compile error: {}\n", .{err});
        return;
    };

    if (flags.debug_mode) {
        debug.disassemble(&compiler.chunk, if (flags.file_path) |p| p else "<source>");
    }

    vm.interpret(&compiler.chunk) catch |err| {
        if (err != error.RuntimeError) std.debug.print("Runtime error: {}\n", .{err});
        return;
    };
}

fn resolveUses(vm: *VM, arena: *maple.ast.NodeArena, stmts: []const usize) !void {
    for (stmts) |stmt_idx| {
        const node = arena.get(stmt_idx);
        if (node == .use_stmt) {
            const path = node.use_stmt.path;
            if (std.mem.eql(u8, path, "io")) {
                try maple.stdlib.io.register(vm);
            }
            if (std.mem.eql(u8, path, "thread")) {
                try maple.stdlib.thread.register(vm);
            }
        }
    }
}

fn runRepl(arena: std.mem.Allocator) !void {

    std.debug.print("Maple v{s} REPL  (:h for help, :q to quit)\n\n", .{VERSION});

    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(arena);

    while (true) {
        std.debug.print("> ", .{});

        line_buf.clearRetainingCapacity();
        var byte: [1]u8 = undefined;
        while (true) {
            const n = posix.read(posix.STDIN_FILENO, &byte) catch |err| {
                if (err == error.WouldBlock) continue;
                std.debug.print("Input error: {}\n", .{err});
                return;
            };
            if (n == 0) return; // EOF
            if (byte[0] == '\n') break;
            try line_buf.append(arena, byte[0]);
        }

        const line = std.mem.trim(u8, line_buf.items, " \t\r");
        if (line.len == 0) continue;

        if (std.mem.eql(u8, line, ":q") or std.mem.eql(u8, line, ":quit")) break;
        if (std.mem.eql(u8, line, ":h") or std.mem.eql(u8, line, ":help")) {
            std.debug.print("  Commands:  :q quit  :h help\n", .{});
            continue;
        }

        const wrapped = try wrapReplInput(arena, line);
        defer arena.free(wrapped);

        var parser = Parser.init(arena, wrapped);
        defer parser.deinit();

        const stmts = parser.parse() catch |err| {
            if (err != error.ParseError) std.debug.print("Parse error: {}\n", .{err});
            continue;
        };

        var compiler = Compiler.init(arena, &parser.arena);
        defer compiler.deinit();

        compiler.compile(stmts) catch |err| {
            if (err != error.CompileError) std.debug.print("Compile error: {}\n", .{err});
            continue;
        };

        var vm = VM.init(arena);
        defer vm.deinit();

        try maple.stdlib.io.register(&vm);
        try maple.stdlib.thread.register(&vm);
        try resolveUses(&vm, &parser.arena, stmts);

        vm.interpret(&compiler.chunk) catch |err| {
            if (err != error.RuntimeError) std.debug.print("Runtime error: {}\n", .{err});
            continue;
        };
    }
}

fn wrapReplInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const stmt_starts = [_][]const u8{
        "let", "mut", "fun", "pub", "type", "use",
        "if", "elif", "else", "loop", "for",
        "ret", "continue", "esc",
    };
    for (stmt_starts) |kw| {
        if (std.mem.startsWith(u8, input, kw)) {
            if (input.len == kw.len or input[kw.len] == ' ' or input[kw.len] == '(') {
                return input;
            }
        }
    }

    // Don't wrap function calls like io.println(...) or foo(...)
    if (looksLikeCall(input)) return input;

    const wrapped = try allocator.alloc(u8, "io.println(".len + input.len + ")".len);
    @memcpy(wrapped[0.."io.println(".len], "io.println(");
    @memcpy(wrapped["io.println(".len .. "io.println(".len + input.len], input);
    @memcpy(wrapped["io.println(".len + input.len ..], ")");
    return wrapped;
}

fn looksLikeCall(input: []const u8) bool {
    for (input, 0..) |c, i| {
        if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') continue;
        return c == '(' and i > 0;
    }
    return false;
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
        std.debug.print("maple: cannot read '{s}': {}\n", .{ path, err });
        return err;
    };
}

fn readStdin(allocator: std.mem.Allocator, _: std.Io) ![]const u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = posix.read(posix.STDIN_FILENO, &chunk) catch |err| {
            if (err == error.WouldBlock) continue;
            if (err == error.BrokenPipe) break;
            return err;
        };
        if (n == 0) break;
        try buf.appendSlice(allocator, chunk[0..n]);
    }
    return buf.toOwnedSlice(allocator);
}

fn printHelp() void {
    std.debug.print(
        \\Maple v{s} — statically typed, AI-native scripting language
        \\
        \\Usage:
        \\  maple [flags] <file.maple>   Run file
        \\  maple [flags] -              Run from stdin
        \\  maple                        Launch REPL
        \\
        \\Flags:
        \\  -d, --debug                  Show bytecode before execution
        \\  --check                      Parse and type-check only
        \\  --error-format=zon|json|yaml Structured error output format
        \\  -h, --help                   Show this help
        \\  --check         Parse only, no execution
        \\  -h, --help      Show this help
        \\  -v, --version   Show version
        \\
        \\Examples:
        \\  maple hello.maple
        \\  maple -d test.maple
        \\  echo 'io.println(42)' | maple -
        \\
    , .{VERSION});
}

fn printVersion() void {
    std.debug.print("Maple v{s}\n", .{VERSION});
}

