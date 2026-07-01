const std = @import("std");
const Io = std.Io;
const build_options = @import("build_options");
const init_cmd = @import("init_cmd.zig");
const clean_cmd = @import("clean_cmd.zig");
const completions_cmd = @import("completions_cmd.zig");

const VERSION = build_options.version;

const Command = struct {
    name: []const u8,
    aliases: []const []const u8,
    runFn: *const fn (io: Io, allocator: std.mem.Allocator, args: []const []const u8) anyerror!void,
    description: []const u8,
};

const commands = [_]Command{
    .{
        .name = "init",
        .aliases = &.{"new"},
        .runFn = init_cmd.run,
        .description = "Initialize a new m4 project",
    },
    .{
        .name = "clean",
        .aliases = &.{},
        .runFn = clean_cmd.run,
        .description = "Clean build artifacts and caches",
    },
    .{
        .name = "completions",
        .aliases = &.{},
        .runFn = completions_cmd.run,
        .description = "Generate shell completion script",
    },
};

fn printUsage() void {
    std.debug.print(
        \\mein v{s} — m4 toolchain manager
        \\
        \\Usage:
        \\  mein <command> [options]
        \\
        \\Commands:
        \\
    , .{VERSION});
    for (&commands) |cmd| {
        var name_buf: [64]u8 = undefined;
        var name_len: usize = @intCast(cmd.name.len);
        @memcpy(name_buf[0..name_len], cmd.name);
        for (cmd.aliases) |alias| {
            if (name_len + 2 + alias.len > name_buf.len) break;
            name_buf[name_len] = ',';
            name_buf[name_len + 1] = ' ';
            @memcpy(name_buf[name_len + 2 .. name_len + 2 + alias.len], alias);
            name_len += 2 + alias.len;
        }
        std.debug.print("  {s: <20} {s}\n", .{ name_buf[0..name_len], cmd.description });
    }
    std.debug.print(
        \\  help                 Show this help
        \\
        \\Options:
        \\  -v, --version        Show version
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("mein v{s}\n", .{VERSION});
}

pub fn main(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = init.minimal.args.toSlice(arena) catch {
        printUsage();
        std.process.exit(1);
    };

    if (args.len < 2) {
        printUsage();
        return;
    }

    const subcmd = args[1];

    if (std.mem.eql(u8, subcmd, "-h") or std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "help")) {
        // Check for subcommand help (e.g. "mein help init" or "mein init --help")
        if (std.mem.eql(u8, subcmd, "help") and args.len > 2) {
            printSubcommandHelp(args[2]);
            return;
        }
        printUsage();
        return;
    }

    if (std.mem.eql(u8, subcmd, "-v") or std.mem.eql(u8, subcmd, "--version") or std.mem.eql(u8, subcmd, "version")) {
        printVersion();
        return;
    }

    for (&commands) |cmd| {
        const match = std.mem.eql(u8, subcmd, cmd.name) or blk: {
            for (cmd.aliases) |alias| {
                if (std.mem.eql(u8, subcmd, alias)) break :blk true;
            }
            break :blk false;
        };
        if (match) {
            if (args.len > 2) {
                const inner = args[2];
                if (std.mem.eql(u8, inner, "-h") or std.mem.eql(u8, inner, "--help")) {
                    printSubcommandHelp(cmd.name);
                    return;
                }
            }
            const cmd_args = if (args.len > 2) args[2..] else &.{};
            cmd.runFn(io, arena, cmd_args) catch |err| {
                printCommandError(cmd.name, err);
                std.process.exit(1);
            };
            return;
        }
    }

    std.debug.print("mein: unknown command '{s}'.\nRun 'mein help' for usage.\n", .{subcmd});
    std.process.exit(1);
}

fn printCommandError(_: []const u8, err: anyerror) void {
    const msg = if (err == error.MissingProjectName)
        "missing project name. Usage: mein init <project-name>"
    else if (err == error.InvalidProjectName)
        "invalid project name. Use letters, digits, hyphens, underscores, and dots."
    else
        @errorName(err);
    std.debug.print("mein: error: {s}\n", .{msg});
}

fn printSubcommandHelp(name: []const u8) void {
    if (std.mem.eql(u8, name, "init")) {
        std.debug.print(
            \\mein init — Initialize a new m4 project
            \\
            \\Usage:
            \\  mein init <project-name>
            \\  mein new <project-name>
            \\
            \\Arguments:
            \\  <project-name>  Name of the project to create
            \\
            \\Creates a new m4 project directory with main.m4 and .wasup/wasup.toml.
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "clean")) {
        std.debug.print(
            \\mein clean — Clean build artifacts and caches
            \\
            \\Usage:
            \\  mein clean
            \\
            \\Removes the .m4_cache directory.
            \\
        , .{});
    } else if (std.mem.eql(u8, name, "completions")) {
        std.debug.print(
            \\mein completions — Generate shell completion script
            \\
            \\Usage:
            \\  mein completions [bash|zsh] [m4c|mein]
            \\
            \\Arguments:
            \\  shell  Shell type: bash (default) or zsh
            \\  binary Binary to generate completions for: mein (default) or m4c
            \\
            \\Pipe the output to a file or source it directly:
            \\  mein completions bash > /usr/local/etc/bash_completion.d/mein
            \\
        , .{});
    } else {
        std.debug.print("mein: no help available for '{s}'. Run 'mein help'.\n", .{name});
    }
}
