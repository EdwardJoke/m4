const std = @import("std");
const Io = std.Io;

const main_m4 =
    \\use std
    \\
    \\pub fun main() i32
    \\    std.println("Hello, m4!")
    \\    ret 0
    \\
;

const wasup_toml_fmt =
    \\[repo]
    \\name = "{s}"
    \\current_version = "v0.1.0"
    \\next_version = "v0.1.0"
    \\
    \\[repo.branches]
    \\dev = "dev"
    \\main = "master"
    \\
;

pub fn run(io: Io, allocator: std.mem.Allocator, args: []const []const u8) !void {
    const project_name = if (args.len > 0 and args[0].len > 0)
        args[0]
    else
        return error.MissingProjectName;

    if (!isValidProjectName(project_name))
        return error.InvalidProjectName;

    const mkdir_cmd = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "mkdir", "-p", project_name },
    });
    allocator.free(mkdir_cmd.stdout);
    allocator.free(mkdir_cmd.stderr);

    const subdir_path = try std.fs.path.join(allocator, &.{ project_name, ".wasup" });
    defer allocator.free(subdir_path);
    const mkdir_sub = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "mkdir", "-p", subdir_path },
    });
    allocator.free(mkdir_sub.stdout);
    allocator.free(mkdir_sub.stderr);

    const main_path = try std.fs.path.join(allocator, &.{ project_name, "main.m4" });
    defer allocator.free(main_path);
    if (fileExists(main_path)) {
        std.debug.print("mein init: '{s}' already exists, skipping\n", .{main_path});
    } else {
        _ = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "cat > {s} << 'EOF'\n{s}\nEOF", .{ main_path, main_m4 }) },
        });
    }

    const wasup_path = try std.fs.path.join(allocator, &.{ project_name, ".wasup", "wasup.toml" });
    defer allocator.free(wasup_path);
    if (fileExists(wasup_path)) {
        std.debug.print("mein init: '{s}' already exists, skipping\n", .{wasup_path});
    } else {
        const wasup_content = try std.fmt.allocPrint(allocator, wasup_toml_fmt, .{project_name});
        defer allocator.free(wasup_content);
        _ = try std.process.run(allocator, io, .{
            .argv = &[_][]const u8{ "sh", "-c", try std.fmt.allocPrint(allocator, "cat > {s} << 'EOF'\n{s}\nEOF", .{ wasup_path, wasup_content }) },
        });
    }

    std.debug.print("Created m4 project '{s}'\n", .{project_name});
    std.debug.print("  {s}/\n", .{project_name});
    std.debug.print("  {s}/main.m4\n", .{project_name});
    std.debug.print("  {s}/.wasup/wasup.toml\n", .{project_name});
    std.debug.print("\nRun with: m4c {s}/main.m4\n", .{project_name});
}

extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(stream: *anyopaque) c_int;

fn fileExists(path: []const u8) bool {
    const path_z = std.fmt.allocPrint(std.heap.page_allocator, "{s}\x00", .{path}) catch return false;
    defer std.heap.page_allocator.free(path_z);
    const f = fopen(@ptrCast(path_z.ptr), "r");
    if (f) |handle| {
        _ = fclose(handle);
        return true;
    }
    return false;
}

fn isValidProjectName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name, 0..) |c, i| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => {},
            '.' => {
                if (i == 0) return false;
                if (name[i - 1] == '.') return false;
            },
            else => return false,
        }
    }
    return true;
}
