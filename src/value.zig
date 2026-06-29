const std = @import("std");

const Self = @This();

/// Runtime value representation for the m4 VM. A tagged union of all possible value types.
pub const Value = union(enum) {
    nil: void,
    bool: bool,
    int: i64,
    float: f64,
    char: u21,
    string: []const u8,
    string_builder: *anyopaque,
    @"fn": *anyopaque,
    fun_obj: *anyopaque,
    thread_handle: *anyopaque,
    channel: *anyopaque,
    vec: *anyopaque,

    /// Check structural equality between two values. Compares by type and content.
    pub fn eql(self: Value, other: Value) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;
        return switch (self) {
            .nil => true,
            .bool => |a| a == other.bool,
            .int => |a| a == other.int,
            .float => |a| a == other.float,
            .char => |a| a == other.char,
            .string => |a| std.mem.eql(u8, a, other.string),
            .string_builder => |a| blk: {
                const Object = @import("object.zig");
                const sa: *Object.StringBuilderObj = @ptrCast(@alignCast(a));
                const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(other.string_builder));
                break :blk std.mem.eql(u8, sa.buf.items, sb.buf.items);
            },
            .@"fn" => |a| a == other.@"fn",
            .fun_obj => |a| a == other.fun_obj,
            .thread_handle => |a| a == other.thread_handle,
            .channel => |a| a == other.channel,
            .vec => |a| a == other.vec,
        };
    }

    /// Return the truthiness of a value: nil and false are falsy, everything else is truthy.
    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .nil => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            else => true,
        };
    }

    /// Format a value for display (implements std.fmt.format).
    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => |b| try writer.print("{}", .{b}),
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .char => |c| try writer.print("{u}", .{c}),
            .string => |s| try writer.print("{s}", .{s}),
            .string_builder => |sb_ptr| {
                const Object = @import("object.zig");
                const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(sb_ptr));
                try writer.print("{s}", .{sb.buf.items});
            },
            .@"fn" => try writer.writeAll("<native-fn>"),
            .fun_obj => try writer.writeAll("<fun>"),
            .thread_handle => try writer.writeAll("<thread-handle>"),
            .channel => try writer.writeAll("<channel>"),
            .vec => try writer.writeAll("<vec>"),
        }
    }
};
