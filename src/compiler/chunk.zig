const std = @import("std");
const Value = @import("value.zig");
const OpCode = @import("opcode.zig");

pub const Chunk = struct {
    allocator: std.mem.Allocator,
    code: std.ArrayListAligned(u32, null),
    constants: std.ArrayList(Value.Value),
    lines: std.ArrayList(u32),

    /// Initialize an empty bytecode chunk with the given allocator.
    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .allocator = allocator,
            .code = std.ArrayListAligned(u32, null).empty,
            .constants = std.ArrayList(Value.Value).empty,
            .lines = std.ArrayList(u32).empty,
        };
    }

    /// Deinitialize the chunk, freeing code, constants, and line info.
    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    /// Append a bytecode instruction with its source line number.
    pub fn write(self: *Chunk, inst: u32, line: u32) !void {
        try self.code.append(self.allocator, inst);
        try self.lines.append(self.allocator, line);
    }

    /// Add a constant value to the chunk's constant table. Returns its index (max 65535).
    pub fn addConstant(self: *Chunk, value: Value.Value) !u16 {
        const idx = self.constants.items.len;
        if (idx > 0xFFFF) return error.TooManyConstants;
        try self.constants.append(self.allocator, value);
        return @intCast(idx);
    }

    /// Get the source line number for the instruction at the given offset.
    pub fn getLine(self: *const Chunk, offset: usize) u32 {
        if (offset < self.lines.items.len) {
            return self.lines.items[offset];
        }
        return 0;
    }

    /// Return the number of instructions in the chunk.
    pub fn len(self: *const Chunk) usize {
        return self.code.items.len;
    }
};

test "chunk: write and read instruction" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    const inst = OpCode.encodeABx(.load_const, 0, 0);
    try c.write(inst, 1);
    try std.testing.expectEqual(@as(usize, 1), c.len());
    try std.testing.expectEqual(inst, c.code.items[0]);
    try std.testing.expectEqual(@as(u32, 1), c.lines.items[0]);
}

test "chunk: add constant and reference" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    const idx = try c.addConstant(.{ .int = 42 });
    try std.testing.expectEqual(@as(u16, 0), idx);
    try std.testing.expectEqual(@as(usize, 1), c.constants.items.len);
    try std.testing.expectEqual(@as(i64, 42), c.constants.items[0].int);
}
