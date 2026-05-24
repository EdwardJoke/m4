const std = @import("std");

const Self = @This();

pub const Value = union(enum) {
    nil: void,
    bool: bool,
    int: i64,
    float: f64,
    char: u21,
    string: []const u8,
    @"fn": *anyopaque,
    fun_obj: *anyopaque,
    vec: *anyopaque,

    pub fn eql(self: Value, other: Value) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;
        return switch (self) {
            .nil => true,
            .bool => |a| a == other.bool,
            .int => |a| a == other.int,
            .float => |a| a == other.float,
            .char => |a| a == other.char,
            .string => |a| std.mem.eql(u8, a, other.string),
            .@"fn" => |a| a == other.@"fn",
            .fun_obj => |a| a == other.fun_obj,
            .vec => |a| a == other.vec,
        };
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .nil => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            else => true,
        };
    }

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .bool => |b| try writer.print("{}", .{b}),
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .char => |c| try writer.print("{u}", .{c}),
            .string => |s| try writer.print("{s}", .{s}),
            .@"fn" => try writer.writeAll("<native-fn>"),
            .fun_obj => try writer.writeAll("<fun>"),
            .vec => try writer.writeAll("<vec>"),
        }
    }
};
