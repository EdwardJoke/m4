const std = @import("std");
const posix = std.posix;
const m4 = @import("m4");
const build_options = @import("build_options");
const serde = @import("serde");
const cli_info = @import("cli_info.zig");

const Parser = m4.Parser;
const Compiler = m4.Compiler;
const VM = m4.VM;
const debug = m4.debug;

const VERSION = build_options.version;

const Flags = struct {
    debug_mode: bool = false,
    lint_mode: bool = false,
    format_mode: bool = false,
    subcommand_help: ?[]const u8 = null,
    native_mode: bool = false,
    build_mode: bool = false,
    file_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    build_target: ?[]const u8 = null,
    qbe_opt: ?[]const u8 = null,
    should_exit: bool = false,
    error_format: ?m4.err.Format = null,
    output_format: ?m4.err.Format = null,
    explain_code: ?[]const u8 = null,
    help_mode: bool = false,
    version_mode: bool = false,
    pretty_mode: bool = false,
};

// ── Structured help metadata (re-exported from cli_info.zig) ──────

pub const FlagInfo = cli_info.FlagInfo;
pub const SubcommandInfo = cli_info.SubcommandInfo;
pub const UsageMode = cli_info.UsageMode;
pub const HelpInfo = cli_info.HelpInfo;
pub const VersionInfo = cli_info.VersionInfo;

/// Main CLI entry point. Parses flags, dispatches to subcommands (help, version, lint, build, explain),
/// or runs/executes m4 source files. Launches REPL if no file is provided.
pub fn run(init: std.process.Init) !void {
    const arena_alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena_alloc);

    const flags = try parseFlags(args);
    if (flags.should_exit) return;

    // Enable pretty output if requested
    m4.err.pretty = flags.pretty_mode;

    if (flags.help_mode) {
        try runHelp(arena_alloc, flags.output_format);
        return;
    }

    if (flags.subcommand_help) |name| {
        try runSubcommandHelp(arena_alloc, name, flags.output_format);
        return;
    }

    if (flags.version_mode) {
        try runVersion(arena_alloc, flags.output_format);
        return;
    }

    if (flags.explain_code) |code| {
        try runExplain(arena_alloc, code, flags.error_format);
        return;
    }

    if (flags.build_mode) {
        if (flags.file_path) |path| {
            try runBuild(arena_alloc, init.io, path, flags);
        } else {
            std.debug.print("m4c build: missing file path. Usage: m4c build <file.m4> [-o <output>] [-target <arch>]\n", .{});
            return error.InvalidFlag;
        }
        return;
    }

    if (flags.lint_mode) {
        if (flags.file_path) |path| {
            try runLint(arena_alloc, init.io, path, flags);
        } else {
            std.debug.print("m4c lint: missing file path. Usage: m4c lint <file.m4>\n", .{});
            return error.InvalidFlag;
        }
        return;
    }

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
        // 'help' subcommand — show CLI help (text or structured)
        if (std.mem.eql(u8, arg, "help")) {
            flags.help_mode = true;
            i += 1;
            while (i < args.len) : (i += 1) {
                const sub = args[i];
                if (std.mem.eql(u8, sub, "--zon")) {
                    flags.output_format = .zon;
                } else if (std.mem.eql(u8, sub, "--json")) {
                    flags.output_format = .json;
                } else if (std.mem.eql(u8, sub, "--yaml")) {
                    flags.output_format = .yaml;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    std.debug.print("m4c: 'help' takes no positional arguments. Try 'm4c help' or 'm4c help --json'.\n", .{});
                    return error.InvalidFlag;
                } else {
                    std.debug.print("m4c: unknown help flag '{s}'. Valid: --zon, --json, --yaml\n", .{sub});
                    return error.InvalidFlag;
                }
            }
            continue;
        }
        // 'version' subcommand — show version (text or structured)
        if (std.mem.eql(u8, arg, "version")) {
            flags.version_mode = true;
            i += 1;
            while (i < args.len) : (i += 1) {
                const sub = args[i];
                if (std.mem.eql(u8, sub, "help")) {
                    flags.subcommand_help = "version";
                } else if (std.mem.eql(u8, sub, "--zon")) {
                    flags.output_format = .zon;
                } else if (std.mem.eql(u8, sub, "--json")) {
                    flags.output_format = .json;
                } else if (std.mem.eql(u8, sub, "--yaml")) {
                    flags.output_format = .yaml;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    std.debug.print("m4c: 'version' takes no positional arguments. Try 'm4c version' or 'm4c version --json'.\n", .{});
                    return error.InvalidFlag;
                } else {
                    std.debug.print("m4c: unknown version flag '{s}'. Valid: --zon, --json, --yaml\n", .{sub});
                    return error.InvalidFlag;
                }
            }
            continue;
        }
        // Special: "-" means stdin
        if (std.mem.eql(u8, arg, "-")) {
            flags.file_path = "-";
            continue;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            flags.help_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            flags.version_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            flags.debug_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--pretty") or std.mem.eql(u8, arg, "-p")) {
            flags.pretty_mode = true;
            continue;
        }
        // 'lint' subcommand — parse and type-check only
        if (std.mem.eql(u8, arg, "lint")) {
            flags.lint_mode = true;
            i += 1;
            while (i < args.len) : (i += 1) {
                const sub = args[i];
                if (std.mem.eql(u8, sub, "help")) {
                    flags.subcommand_help = "lint";
                } else if (std.mem.eql(u8, sub, "--zon")) {
                    flags.error_format = .zon;
                    flags.output_format = .zon;
                } else if (std.mem.eql(u8, sub, "--json")) {
                    flags.error_format = .json;
                    flags.output_format = .json;
                } else if (std.mem.eql(u8, sub, "--yaml")) {
                    flags.error_format = .yaml;
                    flags.output_format = .yaml;
                } else if (std.mem.eql(u8, sub, "-")) {
                    flags.file_path = "-";
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    flags.file_path = sub;
                } else {
                    std.debug.print("m4c: unknown lint flag '{s}'. Try 'm4c lint help' for usage.\n", .{sub});
                    return error.InvalidFlag;
                }
            }
            continue;
        }
        if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            flags.format_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--native")) {
            flags.native_mode = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--zon")) {
            flags.error_format = .zon;
            continue;
        }
        if (std.mem.eql(u8, arg, "--json")) {
            flags.error_format = .json;
            continue;
        }
        if (std.mem.eql(u8, arg, "--yaml")) {
            flags.error_format = .yaml;
            continue;
        }
        // explain subcommand
        if (std.mem.eql(u8, arg, "explain")) {
            i += 1;
            if (i >= args.len or std.mem.startsWith(u8, args[i], "-")) {
                std.debug.print("m4c: 'explain' requires an error code. Try 'm4c explain r001'.\n", .{});
                return error.InvalidFlag;
            }
            if (std.mem.eql(u8, args[i], "help")) {
                flags.subcommand_help = "explain";
                i += 1;
                while (i < args.len) : (i += 1) {
                    const sub = args[i];
                    if (std.mem.eql(u8, sub, "--json")) {
                        flags.output_format = .json;
                    } else if (std.mem.eql(u8, sub, "--yaml")) {
                        flags.output_format = .yaml;
                    } else if (std.mem.eql(u8, sub, "--zon")) {
                        flags.output_format = .zon;
                    } else {
                        std.debug.print("m4c: unknown explain flag '{s}'\n", .{sub});
                        return error.InvalidFlag;
                    }
                }
                continue;
            }
            flags.explain_code = args[i];
            continue;
        }
        // 'build' subcommand — compile to native binary
        if (std.mem.eql(u8, arg, "build")) {
            flags.build_mode = true;
            i += 1;
            if (i < args.len and std.mem.eql(u8, args[i], "help")) {
                flags.subcommand_help = "build";
                i += 1;
                while (i < args.len) : (i += 1) {
                    const sub = args[i];
                    if (std.mem.eql(u8, sub, "--json")) {
                        flags.output_format = .json;
                    } else if (std.mem.eql(u8, sub, "--yaml")) {
                        flags.output_format = .yaml;
                    } else if (std.mem.eql(u8, sub, "--zon")) {
                        flags.output_format = .zon;
                    } else if (std.mem.eql(u8, sub, "-o") or std.mem.eql(u8, sub, "--output")) {
                        if (i + 1 >= args.len) {
                            std.debug.print("m4c: --output requires a path argument\n", .{});
                            return error.InvalidFlag;
                        }
                        i += 1;
                        flags.output_path = args[i];
                    } else if (std.mem.eql(u8, sub, "-target") or std.mem.eql(u8, sub, "--target")) {
                        if (i + 1 >= args.len) {
                            std.debug.print("m4c: --target requires an argument\n", .{});
                            return error.InvalidFlag;
                        }
                        i += 1;
                        flags.build_target = args[i];
                    } else if (std.mem.eql(u8, sub, "-O")) {
                        if (i + 1 >= args.len) {
                            std.debug.print("m4c: -O requires an optimization level\n", .{});
                            return error.InvalidFlag;
                        }
                        i += 1;
                        flags.qbe_opt = args[i];
                    } else {
                        std.debug.print("m4c: unknown build flag '{s}'\n", .{sub});
                        return error.InvalidFlag;
                    }
                }
                continue;
            }
            // Parse remaining arguments for the build subcommand
            while (i < args.len) : (i += 1) {
                const sub = args[i];
                if (std.mem.eql(u8, sub, "-o") or std.mem.eql(u8, sub, "--output")) {
                    if (i + 1 >= args.len) {
                        std.debug.print("m4c: --output requires a path argument\n", .{});
                        return error.InvalidFlag;
                    }
                    i += 1;
                    flags.output_path = args[i];
                } else if (std.mem.eql(u8, sub, "-target") or std.mem.eql(u8, sub, "--target")) {
                    if (i + 1 >= args.len) {
                        std.debug.print("m4c: --target requires an architecture name\n", .{});
                        return error.InvalidFlag;
                    }
                    i += 1;
                    flags.build_target = args[i];
                } else if (std.mem.eql(u8, sub, "-D")) {
                    if (i + 1 >= args.len) {
                        std.debug.print("m4c: -D requires an optimization level (fast|small)\n", .{});
                        return error.InvalidFlag;
                    }
                    i += 1;
                    const opt = args[i];
                    if (!std.mem.eql(u8, opt, "fast") and !std.mem.eql(u8, opt, "small")) {
                        std.debug.print("m4c: invalid -D value '{s}', expected 'fast' or 'small'\n", .{opt});
                        return error.InvalidFlag;
                    }
                    flags.qbe_opt = opt;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    flags.file_path = sub;
                } else {
                    std.debug.print("m4c: unknown build flag '{s}'.\nUsage: m4c build <file.m4> [-o <output>] [-target <arch>] [-D fast|small]\n", .{sub});
                    return error.InvalidFlag;
                }
            }
            continue;
        }

        if (!std.mem.startsWith(u8, arg, "-")) {
            flags.file_path = arg;
            continue;
        }
        std.debug.print("m4c: unknown flag '{s}'.\nTry 'm4c help' for usage.\n", .{arg});
        return error.InvalidFlag;
    }
    return flags;
}

fn runSource(allocator: std.mem.Allocator, source: []const u8, flags: Flags) !void {
    var diag_list = m4.err.DiagnosticList.init();
    defer diag_list.deinit(allocator);

    var parser = Parser.init(allocator, source);
    defer parser.deinit();
    if (flags.error_format != null) {
        parser.diag = &diag_list;
    }

    const stmts = parser.parse() catch |err| {
        if (err == error.ParseError) {
            if (flags.error_format) |fmt| {
                const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            }
            return error.ParseError;
        }
        m4.err.printDiagnostic("p001", "Parse Error", @errorName(err), null);
        return error.ParseError;
    };

    // Type checking
    if (flags.native_mode) {
        // Emit QBE IR instead of running via bytecode VM
        if (flags.error_format != null) {
            std.debug.print("m4c: --native does not support structured error output yet\n", .{});
            return;
        }
        const qbe_ir = try m4.qbe.emitProgram(allocator, &parser.arena, stmts, .{});
        defer allocator.free(qbe_ir);
        if (flags.file_path) |path| {
            std.debug.print("// QBE IR for: {s}\n", .{path});
        }
        std.debug.print("{s}", .{qbe_ir});
        return;
    }

    if (flags.format_mode) {
        for (stmts) |s| {
            m4.fmt.formatNode(&parser.arena, s, 0);
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
    if (flags.error_format != null) compiler.diag = &diag_list;

    compiler.compile(stmts) catch |err| {
        if (err == error.CompileError) {
            if (flags.error_format) |fmt| {
                const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            }
            return error.CompileError;
        }
        m4.err.printDiagnostic("c001", "Compile Error", "out of memory", null);
        return error.CompileError;
    };

    if (flags.debug_mode) {
        debug.disassemble(&compiler.chunk, if (flags.file_path) |p| p else "<source>");
    }

    if (flags.error_format != null) vm.diag = &diag_list;
    vm.interpret(&compiler.chunk) catch |err| {
        if (err == error.RuntimeError) {
            if (flags.error_format) |fmt| {
                const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            }
            return error.RuntimeError;
        }
        m4.err.printDiagnostic("r011", "Runtime Error", "unexpected error", null);
        return error.RuntimeError;
    };
}

fn resolveUses(vm: *VM, arena: *m4.ast.NodeArena, stmts: []const usize) !void {
    for (stmts) |stmt_idx| {
        const node = arena.get(stmt_idx);
        if (node == .use_stmt) {
            const path = node.use_stmt.path;
            if (std.mem.eql(u8, path, "std")) {
                try m4.stdlib.std.register(vm);
            } else if (std.mem.eql(u8, path, "thread")) {
                try m4.stdlib.thread.register(vm);
            } else if (std.mem.eql(u8, path, "range")) {
                try m4.stdlib.range.register(vm);
            } else if (std.mem.eql(u8, path, "fs")) {
                try m4.stdlib.fs.register(vm);
            } else if (std.mem.eql(u8, path, "str")) {
                try m4.stdlib.str.register(vm);
            }
        }
    }
}

fn runExplain(allocator: std.mem.Allocator, code: []const u8, format: ?m4.err.Format) !void {
    const out = try m4.err.explainError(allocator, code, format);
    defer allocator.free(out);
    std.debug.print("{s}\n", .{out});
}

fn runLint(allocator: std.mem.Allocator, io: std.Io, path: []const u8, flags: Flags) !void {
    const source = if (std.mem.eql(u8, path, "-"))
        try readStdin(allocator, io)
    else
        try readFile(allocator, io, path);

    var diag_list = m4.err.DiagnosticList.init();
    defer diag_list.deinit(allocator);

    var parser = Parser.init(allocator, source);
    defer parser.deinit();
    if (flags.error_format != null) {
        parser.diag = &diag_list;
    }

    const stmts = parser.parse() catch |err| {
        if (err == error.ParseError) {
            if (flags.error_format) |fmt| {
                const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
                defer allocator.free(out);
                std.debug.print("{s}\n", .{out});
            }
            return error.ParseError;
        }
        m4.err.printDiagnostic("p001", "Parse Error", @errorName(err), null);
        return error.ParseError;
    };

    var checker = m4.type_check.Checker.init(allocator, &parser.arena);
    defer checker.deinit();
    if (flags.error_format != null) checker.diag = &diag_list;
    checker.check(stmts) catch |err| {
        if (flags.error_format) |fmt| {
            const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
            defer allocator.free(out);
            std.debug.print("{s}\n", .{out});
        } else {
            m4.err.printDiagnostic("t001", "Type Error", @errorName(err), null);
        }
        return error.ParseError;
    };
    if (checker.error_count > 0) {
        if (flags.error_format) |fmt| {
            const out = try m4.err.formatDiagnostics(allocator, diag_list.items(), fmt);
            defer allocator.free(out);
            std.debug.print("{s}\n", .{out});
        } else {
            std.debug.print("{d} type error(s) found.\n", .{checker.error_count});
        }
        return error.ParseError;
    } else {
        std.debug.print("Type checking passed.\n", .{});
    }
}

fn runHelp(allocator: std.mem.Allocator, format: ?m4.err.Format) !void {
    if (format) |fmt| {
        const info = buildHelpInfo(allocator);
        const out = try switch (fmt) {
            .zon => serde.zon.toSlice(allocator, info),
            .json => serde.json.toSlice(allocator, info),
            .yaml => serde.yaml.toSlice(allocator, info),
        };
        defer allocator.free(out);
        std.debug.print("{s}\n", .{out});
    } else {
        printHelp();
    }
}

fn runSubcommandHelp(allocator: std.mem.Allocator, name: []const u8, format: ?m4.err.Format) !void {
    if (format) |fmt| {
        const info = buildSubcommandHelpInfo(allocator, name);
        const out = try switch (fmt) {
            .zon => serde.zon.toSlice(allocator, info),
            .json => serde.json.toSlice(allocator, info),
            .yaml => serde.yaml.toSlice(allocator, info),
        };
        defer allocator.free(out);
        std.debug.print("{s}\n", .{out});
    } else {
        printSubcommandHelp(name);
    }
}

fn buildSubcommandHelpInfo(allocator: std.mem.Allocator, name: []const u8) HelpInfo {
    var full = buildHelpInfo(allocator);
    for (full.subcommands, 0..) |sc, idx| {
        if (std.mem.eql(u8, sc.name, name)) {
            full.subcommands = full.subcommands[idx .. idx + 1];
            return full;
        }
    }
    full.subcommands = &.{};
    return full;
}

fn printSubcommandHelp(name: []const u8) void {
    if (std.mem.eql(u8, name, "lint")) {
        std.debug.print(
            \\m4c lint — Parse and type-check a source file without executing
            \\
            \\Usage:
            \\  m4c lint <file.m4> [--zon|--json|--yaml]
            \\
            \\Options:
            \\  --zon, --json, --yaml  Structured error output format
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "build")) {
        std.debug.print(
            \\m4c build — Compile to native binary
            \\
            \\Usage:
            \\  m4c build <file.m4> [-o <output>] [--target <arch>] [-D fast|small]
            \\
            \\Options:
            \\  -o, --output <path>   Output binary path (default: <file>.out)
            \\  --target <arch>       Target architecture (amd64_apple, arm64_apple, arm64, amd64_sysv, rv64)
            \\  -D <level>            QBE optimization: fast or small
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "explain")) {
        std.debug.print(
            \\m4c explain — Explain an error code
            \\
            \\Usage:
            \\  m4c explain <code> [--zon|--json|--yaml]
            \\
            \\Options:
            \\  --zon, --json, --yaml  Structured output format
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "version")) {
        std.debug.print(
            \\m4c version — Show version information
            \\
            \\Usage:
            \\  m4c version [--zon|--json|--yaml]
            \\
            \\Options:
            \\  --zon, --json, --yaml  Output format
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "help")) {
        std.debug.print(
            \\m4c help — Show CLI help
            \\
            \\Usage:
            \\  m4c help [--zon|--json|--yaml]
            \\
            \\Options:
            \\  --zon, --json, --yaml  Output format
            \\
        , .{});
    } else {
        std.debug.print("m4c: no help available for '{s}'. Try 'm4c help'.\n", .{name});
    }
}

fn buildHelpInfo(allocator: std.mem.Allocator) HelpInfo {
    _ = allocator;
    return HelpInfo{
        .name = "m4c",
        .version = VERSION,
        .description = "Statically typed, AI-native scripting language",
        .usage = &.{
            UsageMode{ .mode = "run-file", .syntax = "m4c [flags] <file.m4>" },
            UsageMode{ .mode = "run-stdin", .syntax = "m4c [flags] -" },
            UsageMode{ .mode = "repl", .syntax = "m4c" },
        },
        .subcommands = &.{
            SubcommandInfo{
                .name = "help",
                .description = "Show CLI help (text or structured)",
                .usage = "m4c help [--zon|--json|--yaml]",
                .flags = &.{
                    FlagInfo{ .name = "--zon", .description = "Output help as ZON" },
                    FlagInfo{ .name = "--json", .description = "Output help as JSON" },
                    FlagInfo{ .name = "--yaml", .description = "Output help as YAML" },
                },
            },
            SubcommandInfo{
                .name = "version",
                .description = "Show version (text or structured)",
                .usage = "m4c version [--zon|--json|--yaml]",
                .flags = &.{
                    FlagInfo{ .name = "--zon", .description = "Output version as ZON" },
                    FlagInfo{ .name = "--json", .description = "Output version as JSON" },
                    FlagInfo{ .name = "--yaml", .description = "Output version as YAML" },
                },
            },
            SubcommandInfo{
                .name = "lint",
                .description = "Parse and type-check a source file (no execution)",
                .usage = "m4c lint <file.m4> [--zon|--json|--yaml]",
                .flags = &.{
                    FlagInfo{ .name = "--zon", .description = "Structured error output as ZON" },
                    FlagInfo{ .name = "--json", .description = "Structured error output as JSON" },
                    FlagInfo{ .name = "--yaml", .description = "Structured error output as YAML" },
                },
            },
            SubcommandInfo{
                .name = "build",
                .description = "Compile to native binary",
                .usage = "m4c build <file.m4> [-o <output>] [-target <arch>] [-D fast|small]",
                .flags = &.{
                    FlagInfo{ .name = "--output", .short = "-o", .description = "Output binary path (default: <file>.out)" },
                    FlagInfo{ .name = "--target", .description = "Target architecture (amd64_apple, arm64_apple, arm64, amd64_sysv, rv64)" },
                    FlagInfo{ .name = "-D", .description = "QBE optimization level: fast (fast compile, large binary) or small (slow compile, small binary)" },
                },
            },
            SubcommandInfo{
                .name = "explain",
                .description = "Explain an error code",
                .usage = "m4c explain <code> [--zon|--json|--yaml]",
                .flags = &.{
                    FlagInfo{ .name = "--zon", .description = "Output explanation as ZON" },
                    FlagInfo{ .name = "--json", .description = "Output explanation as JSON" },
                    FlagInfo{ .name = "--yaml", .description = "Output explanation as YAML" },
                },
            },
        },
        .flags = &.{
            FlagInfo{ .name = "--debug", .short = "-d", .description = "Show bytecode before execution" },
            FlagInfo{ .name = "--format", .short = "-f", .description = "Format source code and print" },
            FlagInfo{ .name = "--pretty", .short = "-p", .description = "Colored error output for terminal readability" },
            FlagInfo{ .name = "--native", .description = "Emit QBE IR instead of running via bytecode VM" },
            FlagInfo{ .name = "--zon", .description = "Structured error output in ZON format" },
            FlagInfo{ .name = "--json", .description = "Structured error output in JSON format" },
            FlagInfo{ .name = "--yaml", .description = "Structured error output in YAML format" },
        },
    };
}

fn runVersion(allocator: std.mem.Allocator, format: ?m4.err.Format) !void {
    if (format) |fmt| {
        const info = VersionInfo{ .name = "m4c", .version = VERSION };
        const out = try switch (fmt) {
            .zon => serde.zon.toSlice(allocator, info),
            .json => serde.json.toSlice(allocator, info),
            .yaml => serde.yaml.toSlice(allocator, info),
        };
        defer allocator.free(out);
        std.debug.print("{s}\n", .{out});
    } else {
        printVersion();
    }
}

fn runRepl(arena: std.mem.Allocator) !void {
    std.debug.print("m4c v{s} REPL  (:h help, :q quit)\n\n", .{VERSION});

    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(arena);

    while (true) {
        std.debug.print("> ", .{});

        line_buf.clearRetainingCapacity();
        var byte: [1]u8 = undefined;
        while (true) {
            const n = posix.read(posix.STDIN_FILENO, &byte) catch |err| {
                if (err == error.WouldBlock) continue;
                m4.err.printDiagnostic("r016", "I/O Error", "stdin read failed", null);
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
            if (err != error.ParseError) m4.err.printDiagnostic("p001", "Parse Error", "unexpected error", null);
            continue;
        };

        var compiler = Compiler.init(arena, &parser.arena);
        defer compiler.deinit();

        compiler.compile(stmts) catch |err| {
            if (err != error.CompileError) m4.err.printDiagnostic("c001", "Compile Error", "unexpected error", null);
            continue;
        };

        var vm = VM.init(arena);
        defer vm.deinit();

        try m4.stdlib.std.register(&vm);
        try resolveUses(&vm, &parser.arena, stmts);

        vm.interpret(&compiler.chunk) catch |err| {
            if (err != error.RuntimeError) m4.err.printDiagnostic("r011", "Runtime Error", "unexpected error", null);
            continue;
        };
    }
}

fn wrapReplInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const stmt_starts = [_][]const u8{
        "let",      "mut",  "fun",  "pub",  "type", "use",
        "if",       "elif", "else", "loop", "for",  "ret",
        "continue", "esc",
    };
    for (stmt_starts) |kw| {
        if (std.mem.startsWith(u8, input, kw)) {
            if (input.len == kw.len or input[kw.len] == ' ' or input[kw.len] == '(') {
                return input;
            }
        }
    }

    // Don't wrap function calls like std.println(...) or foo(...)
    if (looksLikeCall(input)) return input;

    const wrapped = try allocator.alloc(u8, "std.println(".len + input.len + ")".len);
    @memcpy(wrapped[0.."std.println(".len], "std.println(");
    @memcpy(wrapped["std.println(".len .. "std.println(".len + input.len], input);
    @memcpy(wrapped["std.println(".len + input.len ..], ")");
    return wrapped;
}

fn looksLikeCall(input: []const u8) bool {
    for (input, 0..) |c, i| {
        if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') continue;
        return c == '(' and i > 0;
    }
    return false;
}

fn runBuild(allocator: std.mem.Allocator, io: std.Io, path: []const u8, flags: Flags) !void {
    const source = try readFile(allocator, io, path);

    const output_path = flags.output_path orelse blk: {
        // Derive output name from input: replace .m4 extension or add .out
        if (std.mem.endsWith(u8, path, ".m4")) {
            break :blk try std.fmt.allocPrint(allocator, "{s}.out", .{path[0..path.len - 3]});
        } else {
            break :blk try std.fmt.allocPrint(allocator, "{s}.out", .{path});
        }
    };

    std.debug.print("m4c build: compiling '{s}' -> '{s}'\n", .{ path, output_path });

    const result = try m4.qbe_build.buildNative(
        allocator,
        io,
        source,
        output_path,
        flags.build_target,
        flags.qbe_opt,
    );
    _ = result;

    std.debug.print("m4c build: done -> '{s}'\n", .{output_path});
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, std.Io.Limit.limited(1024 * 1024)) catch |err| {
        const clean_msg: []const u8 = switch (err) {
            error.FileNotFound => "file not found",
            error.AccessDenied => "permission denied",
            error.IsDir => "is a directory",
            else => @errorName(err),
        };
        if (m4.err.pretty) {
            std.debug.print("\x1b[1mm4c:\x1b[0m \x1b[91merror:\x1b[0m cannot read '{s}': \x1b[37m{s}\x1b[0m\n", .{ path, clean_msg });
        } else {
            std.debug.print("m4c: error: cannot read '{s}': {s}\n", .{ path, clean_msg });
        }
        return error.ParseError;
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
        \\m4c v{s} — statically typed, AI-native scripting language
        \\
        \\Usage:
        \\  m4c [options] <file.m4>     Run file
        \\  m4c [options] -             Run from stdin
        \\  m4c                         Launch REPL
        \\
        \\Commands:
        \\  help [--fmt]              Show this help
        \\  version [--fmt]           Show version
        \\  lint <file.m4> [--fmt]    Parse and type-check only
        \\  build <file.m4> [options] Compile to native binary
        \\  explain <code> [--fmt]    Explain an error code
        \\
        \\Run 'm4c <command> help' for command-specific options (e.g. 'm4c lint help').
        \\
        \\Options:
        \\  -v, --version          Show version
        \\  -d, --debug            Show bytecode before execution
        \\  -f, --format           Format source code and print
        \\  -p, --pretty           Colored error output for terminal readability
        \\  --native               Emit QBE IR instead of running via bytecode VM
        \\  --zon, --json, --yaml  Structured output format (replace --fmt above)
        \\
    , .{VERSION});
}

fn printVersion() void {
    std.debug.print("m4c v{s}\n", .{VERSION});
}

test "cli: -D fast is accepted" {
    const args = &[_][]const u8{ "m4c", "build", "file.m4", "-D", "fast" };
    const flags = try parseFlags(args);
    try std.testing.expectEqualStrings("fast", flags.qbe_opt.?);
}

test "cli: -D small is accepted" {
    const args = &[_][]const u8{ "m4c", "build", "file.m4", "-D", "small" };
    const flags = try parseFlags(args);
    try std.testing.expectEqualStrings("small", flags.qbe_opt.?);
}

test "cli: -D missing argument returns InvalidFlag" {
    const args = &[_][]const u8{ "m4c", "build", "file.m4", "-D" };
    try std.testing.expectError(error.InvalidFlag, parseFlags(args));
}

test "cli: -D with invalid value returns InvalidFlag" {
    const args = &[_][]const u8{ "m4c", "build", "file.m4", "-D", "invalid" };
    try std.testing.expectError(error.InvalidFlag, parseFlags(args));
}
