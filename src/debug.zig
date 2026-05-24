const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("opcode.zig");

pub fn disassemble(chunk: *const Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *const Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset});

    const line = chunk.getLine(offset);
    if (offset > 0 and line == chunk.getLine(offset - 1)) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{line});
    }

    const inst = chunk.code.items[offset];
    const op = OpCode.decodeOp(inst);

    switch (op.format()) {
        .iABC => {
            const dec = OpCode.decodeABC(inst);
            std.debug.print("{s:<12} r{d} r{d} r{d}\n", .{ @tagName(op), dec.a, dec.b, dec.c });
        },
        .iABx => {
            const dec = OpCode.decodeABx(inst);
            std.debug.print("{s:<12} r{d} {d}\n", .{ @tagName(op), dec.a, dec.bx });
        },
        .iAsBx => {
            const dec = OpCode.decodeAsBx(inst);
            std.debug.print("{s:<12} r{d} {d}\n", .{ @tagName(op), dec.a, dec.sbx });
        },
        .iAx => {
            const dec = OpCode.decodeAx(inst);
            std.debug.print("{s:<12} r{d}\n", .{ @tagName(op), dec });
        },
    }

    return offset + 1;
}

test "debug: disassemble simple chunk" {
    var c = Chunk.init(std.testing.allocator);
    defer c.deinit();

    const idx = try c.addConstant(.{ .int = 42 });
    try c.write(OpCode.encodeABx(.load_const, 0, idx), 1);
    try c.write(OpCode.encodeAx(.halt, 0), 1);

    disassemble(&c, "test");
}
