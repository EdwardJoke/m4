const std = @import("std");
const Value = @import("value.zig");
const Chunk = @import("chunk.zig").Chunk;

pub const FunObj = struct {
    name: []const u8,
    chunk: Chunk,
    param_count: u8,
};

pub const VecObj = struct {
    items: std.ArrayList(Value.Value),
};

pub const MapObj = struct {
    entries: std.StringHashMap(Value.Value),
};

pub const StringBuilderObj = struct {
    buf: std.ArrayList(u8),
};

pub const StructObj = struct {
    fields: std.StringHashMap(Value.Value),
};
