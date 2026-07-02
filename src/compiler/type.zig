const std = @import("std");

pub const Primitive = enum {
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
    bool,
    char,
    str,
    bytes,
};

/// The m4 type system representation. A tagged union of primitive, generic, function, and named types.
pub const Type = union(enum) {
    primitive: Primitive,
    vec: *Type,
    map: struct { key: *Type, val: *Type },
    opt: *Type,
    res: struct { ok: *Type, err: *Type },
    func: struct { params: []const Type, ret: *Type },
    named: []const u8,
    void_type,

    /// Check structural equality between two types (recursing into generics and function params).
    pub fn eql(a: *const Type, b: *const Type) bool {
        if (@intFromEnum(a.*) != @intFromEnum(b.*)) return false;
        return switch (a.*) {
            .primitive => |pa| b.primitive == pa,
            .vec => |va| b.vec.eql(va),
            .map => |ma| b.map.key.eql(ma.key) and b.map.val.eql(ma.val),
            .opt => |oa| b.opt.eql(oa),
            .res => |ra| b.res.ok.eql(ra.ok) and b.res.err.eql(ra.err),
            .func => |fa| blk: {
                if (fa.params.len != b.func.params.len) break :blk false;
                for (fa.params, b.func.params) |pa, pb| {
                    if (!pa.eql(&pb)) break :blk false;
                }
                break :blk fa.ret.eql(b.func.ret);
            },
            .named => |na| std.mem.eql(u8, na, b.named),
            .void_type => true,
        };
    }

    /// Format a type for display (implements std.fmt.format).
    pub fn format(self: *const Type, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self.*) {
            .primitive => |p| try writer.print("{s}", .{@tagName(p)}),
            .vec => |v| try writer.print("vec[{any}]", .{v}),
            .map => |m| try writer.print("map[{any} {any}]", .{ m.key, m.val }),
            .opt => |o| try writer.print("opt[{any}]", .{o}),
            .res => |r| try writer.print("res[{any} {any}]", .{ r.ok, r.err }),
            .func => |f| {
                try writer.writeAll("fun(");
                for (f.params, 0..) |p, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("{any}", .{p});
                }
                try writer.writeAll(") ");
                try writer.print("{any}", .{f.ret});
            },
            .named => |n| try writer.print("{s}", .{n}),
            .void_type => try writer.writeAll("void"),
        }
    }
};

/// Parse a type name string into a Primitive enum. Returns null for non-primitive names.
pub fn parseTypeName(name: []const u8) ?Primitive {
    const m = std.StaticStringMap(Primitive).initComptime(.{
        .{ "i8", .i8 },
        .{ "i16", .i16 },
        .{ "i32", .i32 },
        .{ "i64", .i64 },
        .{ "u8", .u8 },
        .{ "u16", .u16 },
        .{ "u32", .u32 },
        .{ "u64", .u64 },
        .{ "f32", .f32 },
        .{ "f64", .f64 },
        .{ "bool", .bool },
        .{ "char", .char },
        .{ "str", .str },
        .{ "bytes", .bytes },
    });
    return m.get(name);
}

test "parseTypeName: all primitives" {
    try std.testing.expectEqual(Primitive.i32, parseTypeName("i32").?);
    try std.testing.expectEqual(Primitive.f64, parseTypeName("f64").?);
    try std.testing.expectEqual(Primitive.str, parseTypeName("str").?);
    try std.testing.expectEqual(Primitive.bool, parseTypeName("bool").?);
}
