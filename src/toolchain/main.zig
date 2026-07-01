const std = @import("std");

pub fn main(init: std.process.Init) void {
    _ = init;
    std.debug.print("mein v0.4.0 — m4 toolchain manager\n\n", .{});
    std.debug.print("Usage: mein <command>\n\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  init     Initialize a new m4 project\n", .{});
    std.debug.print("  new      Alias for init\n", .{});
    std.debug.print("  clean    Clean build artifacts\n", .{});
    std.debug.print("  help     Show this help\n", .{});
}
