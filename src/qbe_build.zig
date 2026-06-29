const std = @import("std");
const Parser = @import("parser.zig").Parser;
const qbe = @import("qbe.zig");

/// Embedded m4rt.c source code — embedded at compile time via @embedFile.
const m4rt_c_src = @embedFile("runtime/m4rt.c");

/// Embedded m4rt.h source code — embedded at compile time via @embedFile.
const m4rt_h_src = @embedFile("runtime/m4rt.h");

/// Results from a native build.
pub const BuildResult = struct {
    output_path: []const u8,
};

/// Build a native binary from an m4 source file.
///
/// Parameters:
///   allocator    — memory allocator (must outlive the returned result)
///   io           — I/O interface
///   source       — the m4 source code
///   output_path  — path for the final executable
///   target       — target architecture (e.g. "arm64", "amd64_apple", "amd64_sysv", "rv64")
///                  If null, auto-detects from the host.
///   qbe_opt      — QBE optimization level: "fast" or "small", or null for default
///
pub fn buildNative(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: []const u8,
    output_path: []const u8,
    target: ?[]const u8,
    qbe_opt: ?[]const u8,
) !BuildResult {
    // ── Step 1: Parse ──────────────────────────────────────────────────
    var parser = Parser.init(allocator, source);
    defer parser.deinit();

    const stmts = try parser.parse();
    const stmts_owned = try allocator.dupe(usize, stmts);
    defer allocator.free(stmts_owned);

    // ── Step 2: Emit QBE IR ────────────────────────────────────────────
    const qbe_ir = try qbe.emitProgram(allocator, &parser.arena, stmts_owned, .{});
    defer allocator.free(qbe_ir);

    // ── Step 3: Create temp directory ───────────────────────────────────
    const tmp_dir_path = ".m4_cache";
    // Ensure directory exists
    {
        const mkdir_result = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "mkdir", "-p", tmp_dir_path },
        });
        allocator.free(mkdir_result.stdout);
        allocator.free(mkdir_result.stderr);
    }

    const ssa_path = ".m4_cache/prog.ssa";
    const asm_path = ".m4_cache/prog.s";

    // Write files using C stdio (project links libc)
    {
        const f = fopen(ssa_path, "w") orelse return error.FileWriteError;
        _ = fwrite(qbe_ir.ptr, 1, qbe_ir.len, f);
        _ = fclose(f);
    }
    {
        const f = fopen(".m4_cache/m4rt.c", "w") orelse return error.FileWriteError;
        _ = fwrite(m4rt_c_src.ptr, 1, m4rt_c_src.len, f);
        _ = fclose(f);
    }
    {
        const f = fopen(".m4_cache/m4rt.h", "w") orelse return error.FileWriteError;
        _ = fwrite(m4rt_h_src.ptr, 1, m4rt_h_src.len, f);
        _ = fclose(f);
    }

    // ── Step 4: Compile .ssa → .s via QBE library ──────────────────────
    const resolved_target = target orelse getHostTarget();

    // Runtime object path keyed by hash of runtime source + target
    const rt_cache_key = blk: {
        var h: u64 = 0;
        for (m4rt_c_src) |b| h = h *% 31 +% b;
        for (resolved_target) |b| h = h *% 31 +% b;
        break :blk h;
    };
    const rt_obj_path = try std.fmt.allocPrint(allocator, ".m4_cache/m4rt_{x}.o", .{rt_cache_key});
    const rt_obj_path_z = try allocator.dupeZ(u8, rt_obj_path);
    defer {
        allocator.free(rt_obj_path);
        allocator.free(rt_obj_path_z);
    }

    // Need null-terminated strings for C FFI
    const ssa_path_z = try allocator.dupeZ(u8, ssa_path);
    defer allocator.free(ssa_path_z);
    const asm_path_z = try allocator.dupeZ(u8, asm_path);
    defer allocator.free(asm_path_z);
    const target_z = try allocator.dupeZ(u8, resolved_target);
    defer allocator.free(target_z);
    const qbe_opt_z = if (qbe_opt) |opt| try allocator.dupeZ(u8, opt) else null;
    defer if (qbe_opt_z) |z| allocator.free(z);
    const qbe_opt_ptr: ?[*:0]const u8 = if (qbe_opt_z) |z| @ptrFromInt(@intFromPtr(z.ptr)) else null;

    const qbe_result = qbe_compile_ssa(ssa_path_z, asm_path_z, target_z, qbe_opt_ptr);
    if (qbe_result != 0) {
        std.debug.print("m4 build: QBE compilation failed (error {d})\n", .{qbe_result});
        return error.QbeCompileError;
    }

    // ── Step 5: Compile m4rt.c → m4rt.o (cached by source+target hash) ──
    {
        const exists = check: {
            const f = fopen(rt_obj_path_z, "r");
            if (f) |handle| {
                _ = fclose(handle);
                break :check true;
            }
            break :check false;
        };

        if (!exists) {
            const host_target = getHostTarget();
            const is_cross = !std.mem.eql(u8, resolved_target, host_target);

            const cc_args = if (is_cross)
                &[_][]const u8{ "cc", "-c", "-std=c99", "-I.m4_cache", "-target", targetToClangTarget(resolved_target), ".m4_cache/m4rt.c", "-o", rt_obj_path }
            else
                &[_][]const u8{ "cc", "-c", "-std=c99", "-I.m4_cache", ".m4_cache/m4rt.c", "-o", rt_obj_path };

            const result = try std.process.run(allocator, io, .{ .argv = cc_args });
            defer {
                allocator.free(result.stdout);
                allocator.free(result.stderr);
            }
            if (result.term != .exited or result.term.exited != 0) {
                std.debug.print("m4 build: runtime compilation failed\n{s}\n", .{result.stderr});
                return error.RuntimeCompileError;
            }
        }
    }

    // ── Step 6: Assemble .s + link → final binary ────────────────────────
    {
        const host_target = getHostTarget();
        const is_cross = !std.mem.eql(u8, resolved_target, host_target);

        // Build argv: cc [arch] [target] -std=c99 -o output prog.s m4rt.o
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(allocator);
        try argv.append(allocator, "cc");
        if (isMacOS() and !is_cross) {
            const as_arch = targetToAsArch(resolved_target) orelse "x86_64";
            try argv.append(allocator, "-arch");
            try argv.append(allocator, as_arch);
        }
        try argv.append(allocator, "-std=c99");
        try argv.append(allocator, "-I.m4_cache");
        if (is_cross) {
            try argv.append(allocator, "-target");
            try argv.append(allocator, targetToClangTarget(resolved_target));
        }
        try argv.append(allocator, "-o");
        try argv.append(allocator, output_path);
        try argv.append(allocator, asm_path);
        try argv.append(allocator, rt_obj_path);

        const result = try std.process.run(allocator, io, .{
            .argv = try argv.toOwnedSlice(allocator),
        });
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }
        if (result.term != .exited or result.term.exited != 0) {
            std.debug.print("m4 build: assembly/linking failed\n{s}\n", .{result.stderr});
            return error.CompileLinkError;
        }
    }

    // ── Step 8: Make executable ────────────────────────────────────────
    {
        // Use chmod via process.run (portable)
        _ = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "chmod", "0755", output_path },
        });
    }

    return BuildResult{ .output_path = output_path };
}

// ─── C FFI ─────────────────────────────────────────────────────────────────

/// C function from the linked qbe_wrap.c
extern "c" fn qbe_compile_ssa(input_path: [*:0]const u8, output_path: [*:0]const u8, target: [*:0]const u8, qbe_opt: ?[*:0]const u8) c_int;

/// C stdio functions (project links libc)
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fwrite(ptr: [*]const u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;

// ─── Host Architecture Detection ───────────────────────────────────────────

fn getHostArch() std.Target.Cpu.Arch {
    return @import("builtin").target.cpu.arch;
}

/// Detect whether we're on macOS (for amd64_apple vs amd64_sysv).
fn isMacOS() bool {
    return @import("builtin").target.os.tag == .macos;
}

/// Get the default QBE target name for the host.
fn getHostTarget() []const u8 {
    return switch (getHostArch()) {
        .aarch64 => if (isMacOS()) "arm64_apple" else "arm64",
        .x86_64 => if (isMacOS()) "amd64_apple" else "amd64_sysv",
        .riscv64 => "rv64",
        else => "amd64_sysv",
    };
}

// ─── Cross-Compilation Target Mapping ──────────────────────────────────────

/// Map QBE target name to Apple assembler -arch flag value.
/// Returns null for targets that need a cross toolchain.
fn targetToAsArch(target: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, target, "arm64_apple")) return "arm64";
    if (std.mem.eql(u8, target, "amd64_apple")) return "x86_64";
    return null;
}

/// Map QBE target name to clang -target triple.
fn targetToClangTarget(target: []const u8) []const u8 {
    if (std.mem.eql(u8, target, "arm64_apple")) return "arm64-apple-macos";
    if (std.mem.eql(u8, target, "amd64_apple")) return "x86_64-apple-macos";
    if (std.mem.eql(u8, target, "arm64")) return "aarch64-linux-gnu";
    if (std.mem.eql(u8, target, "amd64_sysv")) return "x86_64-linux-gnu";
    if (std.mem.eql(u8, target, "rv64")) return "riscv64-linux-gnu";
    return target;
}

// ─── Tests ─────────────────────────────────────────────────────────────────

test "qbe_build: host target detection" {
    const host = getHostTarget();
    try std.testing.expect(host.len > 0);
}

test "qbe_build: embedded m4rt.c is non-empty" {
    try std.testing.expect(m4rt_c_src.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, m4rt_c_src, "m4_new_int") != null);
}

test "qbe_build: embedded m4rt.h is non-empty" {
    try std.testing.expect(m4rt_h_src.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, m4rt_h_src, "m4_new_int") != null);
}
