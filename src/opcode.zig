const std = @import("std");

pub const Format = enum {
    iABC,
    iABx,
    iAsBx,
    iAx,
};

pub const OpCode = enum(u8) {
    // iABC: r[dst] = r[a] op r[b]
    add,
    sub,
    mul,
    div_op,
    mod_op,
    eq,
    neq,
    gt,
    lt,
    gte,
    lte,
    and_,
    or_,

    // iABx: r[dst] = constants[idx]
    load_const,
    // iABx: r[dst] = globals[name_idx]
    load_global,
    // iABx: r[dst] = locals[slot]
    load_local,
    // iABx: globals[name_idx] = r[src]
    store_global,
    // iABx: locals[slot] = r[src]
    store_local,

    // iA: single-register ops
    load_nil,
    load_true,
    load_false,
    not_,
    neg,
    move_op,
    ret,
    halt,

    // iAsBx: conditional/unconditional jumps (offset is signed i16 from pc)
    jump,
    jump_if_true,
    jump_if_false,

    // Special
    call, // iABC: r[dst]=result, a=callee_reg, b=arg_count

    // iABx: r[dst] = new_vec(const_idx_for_count)
    new_vec,
    // iABx: r[dst] = new_map(init_size)
    new_map,

    // iABx: r[dst] = r[obj].field(const_idx)
    get_field,
    // iABx: r[obj].field(const_idx) = r[src]
    set_field,

    // iABC: r[dst] = r[obj][r[idx]]
    index_get,
    // iABC: r[obj][r[idx]] = r[src]
    index_set,

    // iABC: r[dst] = len(r[obj])
    index_len,
    // iABC: vec_set vec_reg[idx] = r[src]
    vec_set,

    // Struct ops
    new_struct,
    struct_set,

    // iA: error propagation on r[dst]
    try_prop,

    pub fn format(self: OpCode) Format {
        return switch (self) {
            .add, .sub, .mul, .div_op, .mod_op,
            .eq, .neq, .gt, .lt, .gte, .lte,
            .and_, .or_,
            .call,
            .index_get, .index_set,
            .index_len, .vec_set,
            .new_struct,
            => .iABC,

            .struct_set => .iABx,

            .load_const, .load_global, .load_local,
            .store_global, .store_local,
            .new_vec, .new_map,
            .get_field, .set_field,
            => .iABx,

            .jump, .jump_if_true, .jump_if_false => .iAsBx,

            .load_nil, .load_true, .load_false,
            .not_, .neg,
            .ret, .halt, .try_prop,
            => .iAx,

            .move_op => .iABx,
        };
    }
};

/// Encode an iABC-format instruction: opcode[8] a[8] b[8] c[8]
pub fn encodeABC(op: OpCode, a: u8, b: u8, c: u8) u32 {
    return (@as(u32, @intFromEnum(op)) << 24) |
        (@as(u32, a) << 16) |
        (@as(u32, b) << 8) |
        (@as(u32, c));
}

/// Encode an iABx-format instruction: opcode[8] a[8] bx[16]
pub fn encodeABx(op: OpCode, a: u8, bx: u16) u32 {
    return (@as(u32, @intFromEnum(op)) << 24) |
        (@as(u32, a) << 16) |
        (@as(u32, bx));
}

/// Encode an iAsBx-format instruction (signed offset): opcode[8] a[8] sbx[16]
pub fn encodeAsBx(op: OpCode, a: u8, sbx: i16) u32 {
    return (@as(u32, @intFromEnum(op)) << 24) |
        (@as(u32, a) << 16) |
        (@as(u32, @as(u16, @bitCast(sbx))) & 0xFFFF);
}

/// Encode an iAx-format instruction (single register): opcode[8] a[8] 0[16]
pub fn encodeAx(op: OpCode, a: u8) u32 {
    return (@as(u32, @intFromEnum(op)) << 24) |
        (@as(u32, a) << 16);
}

/// Decode an iABC-format instruction into its fields.
pub fn decodeABC(inst: u32) struct { a: u8, b: u8, c: u8 } {
    return .{
        .a = @truncate((inst >> 16) & 0xFF),
        .b = @truncate((inst >> 8) & 0xFF),
        .c = @truncate(inst & 0xFF),
    };
}

/// Decode an iABx-format instruction into its fields.
pub fn decodeABx(inst: u32) struct { a: u8, bx: u16 } {
    return .{
        .a = @truncate((inst >> 16) & 0xFF),
        .bx = @truncate(inst & 0xFFFF),
    };
}

/// Decode an iAsBx-format instruction (signed offset) into its fields.
pub fn decodeAsBx(inst: u32) struct { a: u8, sbx: i16 } {
    return .{
        .a = @truncate((inst >> 16) & 0xFF),
        .sbx = @bitCast(@as(u16, @truncate(inst & 0xFFFF))),
    };
}

/// Decode an iAx-format instruction to extract the register operand.
pub fn decodeAx(inst: u32) u8 {
    return @truncate((inst >> 16) & 0xFF);
}

/// Extract the opcode from an encoded instruction.
pub fn decodeOp(inst: u32) OpCode {
    return @enumFromInt(@as(u8, @truncate(inst >> 24)));
}

/// Return the tag name of an opcode as a string.
pub fn opName(op: OpCode) []const u8 {
    return @tagName(op);
}
