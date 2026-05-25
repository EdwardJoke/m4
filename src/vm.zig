const std = @import("std");
const OpCode = @import("opcode.zig");
const Value = @import("value.zig");
const Chunk = @import("chunk.zig").Chunk;
const Object = @import("object.zig");

const REGISTER_COUNT = 256;
const FRAMES_MAX = 64;

const NativeFn = *const fn (*VM, []const Value.Value) Value.Value;

const CallFrame = struct {
    chunk: *const Chunk,
    pc: usize,
    base_reg: u8,
    ret_pc: usize,
    ret_dst: u8,
};

pub const VM = @This();

allocator: std.mem.Allocator,
registers: [REGISTER_COUNT]Value.Value,
chunk: ?*const Chunk,
pc: usize,
frames: [FRAMES_MAX]CallFrame,
frame_count: usize,
globals: std.StringHashMap(Value.Value),

pub fn init(allocator: std.mem.Allocator) VM {
    return .{
        .allocator = allocator,
        .registers = [_]Value.Value{.{ .nil = {} }} ** REGISTER_COUNT,
        .chunk = null,
        .pc = 0,
        .frames = undefined,
        .frame_count = 0,
        .globals = std.StringHashMap(Value.Value).init(allocator),
    };
}

pub fn deinit(self: *VM) void {
    self.globals.deinit();
}

pub fn registerNative(self: *VM, name: []const u8, ptr: *anyopaque) !void {
    try self.globals.put(name, .{ .@"fn" = ptr });
}

pub fn interpret(self: *VM, chunk: *const Chunk) !void {
    self.chunk = chunk;
    self.pc = 0;
    self.frame_count = 1;
    self.frames[0] = .{ .chunk = chunk, .pc = 0, .base_reg = 0, .ret_pc = 0, .ret_dst = 0 };
    return self.run();
}

pub fn run(self: *VM) !void {
    while (true) {
        if (self.pc >= self.chunk.?.code.items.len) break;
        const inst = self.chunk.?.code.items[self.pc];
        const op = OpCode.decodeOp(inst);
        const base = self.frames[self.frame_count - 1].base_reg;

        switch (op) {
            .halt => return,

            .load_const => {
                const dec = OpCode.decodeABx(inst);
                self.registers[base + dec.a] = self.chunk.?.constants.items[dec.bx];
                self.pc += 1;
            },
            .load_true => {
                self.registers[base + OpCode.decodeAx(inst)] = .{ .bool = true };
                self.pc += 1;
            },
            .load_false => {
                self.registers[base + OpCode.decodeAx(inst)] = .{ .bool = false };
                self.pc += 1;
            },
            .load_nil => {
                self.registers[base + OpCode.decodeAx(inst)] = .nil;
                self.pc += 1;
            },
            .load_global => {
                const dec = OpCode.decodeABx(inst);
                const name = self.chunk.?.constants.items[dec.bx].string;
                if (self.globals.get(name)) |val| {
                    self.registers[base + dec.a] = val;
                } else {
                    std.debug.print("Runtime error: undefined variable '{s}'\n", .{name});
                    return error.RuntimeError;
                }
                self.pc += 1;
            },
            .load_local => {
                const dec = OpCode.decodeABx(inst);
                const frame = &self.frames[self.frame_count - 1];
                self.registers[base + dec.a] = self.registers[frame.base_reg + dec.bx];
                self.pc += 1;
            },
            .store_global => {
                const dec = OpCode.decodeABx(inst);
                const name = self.chunk.?.constants.items[dec.bx].string;
                try self.globals.put(name, self.registers[base + dec.a]);
                self.pc += 1;
            },
            .store_local => {
                const dec = OpCode.decodeABx(inst);
                const frame = &self.frames[self.frame_count - 1];
                self.registers[frame.base_reg + dec.bx] = self.registers[base + dec.a];
                self.pc += 1;
            },
            .add => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = try binaryOp(.add, self.registers[base+d.b], self.registers[base+d.c]); self.pc += 1; },
            .sub => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = try binaryOp(.sub, self.registers[base+d.b], self.registers[base+d.c]); self.pc += 1; },
            .mul => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = try binaryOp(.mul, self.registers[base+d.b], self.registers[base+d.c]); self.pc += 1; },
            .div_op => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = try binaryOp(.div_op, self.registers[base+d.b], self.registers[base+d.c]); self.pc += 1; },
            .mod_op => { const d = OpCode.decodeABC(inst); const a = self.registers[base+d.b]; const b = self.registers[base+d.c]; if (a == .int and b == .int) { self.registers[base+d.a] = .{ .int = @mod(a.int, b.int) }; } else return error.RuntimeError; self.pc += 1; },
            .neg => { const r = base + OpCode.decodeAx(inst); self.registers[r] = switch (self.registers[r]) { .int => |i| .{ .int = -i }, .float => |f| .{ .float = -f }, else => return error.RuntimeError, }; self.pc += 1; },
            .not_ => { const r = base + OpCode.decodeAx(inst); self.registers[r] = .{ .bool = !self.registers[r].isTruthy() }; self.pc += 1; },
            .eq => { const d = OpCode.decodeABC(inst); const result = self.registers[base+d.b].eql(self.registers[base+d.c]); self.registers[base+d.a] = .{ .bool = result }; self.pc += 1; },
            .neq => { const d = OpCode.decodeABC(inst); const result = self.registers[base+d.b].eql(self.registers[base+d.c]); self.registers[base+d.a] = .{ .bool = !result }; self.pc += 1; },
            .gt => { const d = OpCode.decodeABC(inst); const l = self.registers[base+d.b]; const r = self.registers[base+d.c]; self.registers[base+d.a] = switch (l) { .int => |li| switch (r) { .int => |ri| .{ .bool = li > ri }, .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) > rf }, else => return error.RuntimeError, }, .float => |lf| switch (r) { .int => |ri| .{ .bool = lf > @as(f64, @floatFromInt(ri)) }, .float => |rf| .{ .bool = lf > rf }, else => return error.RuntimeError, }, else => return error.RuntimeError, }; self.pc += 1; },
            .lt => { const d = OpCode.decodeABC(inst); const l = self.registers[base+d.b]; const r = self.registers[base+d.c]; self.registers[base+d.a] = switch (l) { .int => |li| switch (r) { .int => |ri| .{ .bool = li < ri }, .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) < rf }, else => return error.RuntimeError, }, .float => |lf| switch (r) { .int => |ri| .{ .bool = lf < @as(f64, @floatFromInt(ri)) }, .float => |rf| .{ .bool = lf < rf }, else => return error.RuntimeError, }, else => return error.RuntimeError, }; self.pc += 1; },
            .gte => { const d = OpCode.decodeABC(inst); const l = self.registers[base+d.b]; const r = self.registers[base+d.c]; self.registers[base+d.a] = switch (l) { .int => |li| switch (r) { .int => |ri| .{ .bool = li >= ri }, .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) >= rf }, else => return error.RuntimeError, }, .float => |lf| switch (r) { .int => |ri| .{ .bool = lf >= @as(f64, @floatFromInt(ri)) }, .float => |rf| .{ .bool = lf >= rf }, else => return error.RuntimeError, }, else => return error.RuntimeError, }; self.pc += 1; },
            .lte => { const d = OpCode.decodeABC(inst); const l = self.registers[base+d.b]; const r = self.registers[base+d.c]; self.registers[base+d.a] = switch (l) { .int => |li| switch (r) { .int => |ri| .{ .bool = li <= ri }, .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) <= rf }, else => return error.RuntimeError, }, .float => |lf| switch (r) { .int => |ri| .{ .bool = lf <= @as(f64, @floatFromInt(ri)) }, .float => |rf| .{ .bool = lf <= rf }, else => return error.RuntimeError, }, else => return error.RuntimeError, }; self.pc += 1; },
            .and_ => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = .{ .bool = self.registers[base+d.b].isTruthy() and self.registers[base+d.c].isTruthy() }; self.pc += 1; },
            .or_ => { const d = OpCode.decodeABC(inst); self.registers[base+d.a] = .{ .bool = self.registers[base+d.b].isTruthy() or self.registers[base+d.c].isTruthy() }; self.pc += 1; },

            .jump => { const d = OpCode.decodeAsBx(inst); self.pc = @intCast(@as(i32, @intCast(self.pc)) + d.sbx); },
            .jump_if_false => { const d = OpCode.decodeAsBx(inst); if (!self.registers[base+d.a].isTruthy()) { self.pc = @intCast(@as(i32, @intCast(self.pc)) + d.sbx); } else { self.pc += 1; } },
            .jump_if_true => { const d = OpCode.decodeAsBx(inst); if (self.registers[base+d.a].isTruthy()) { self.pc = @intCast(@as(i32, @intCast(self.pc)) + d.sbx); } else { self.pc += 1; } },

            .call => {
                const dec = OpCode.decodeABC(inst);
                const callee = self.registers[base + dec.b];
                if (callee == .@"fn") {
                    const native: NativeFn = @ptrCast(@alignCast(callee.@"fn"));
                    const result = native(self, self.registers[(base + dec.b + 1) .. (base + dec.b + 1 + dec.c)]);
                    self.registers[base + dec.a] = result;
                    self.pc += 1;
                } else if (callee == .fun_obj) {
                    const fun: *Object.FunObj = @ptrCast(@alignCast(callee.fun_obj));
                    if (self.frame_count >= FRAMES_MAX) return error.RuntimeError;
                    self.frames[self.frame_count - 1].pc = self.pc + 1;
                    const new_base = base + dec.b + 1 + dec.c;
                    self.frames[self.frame_count] = .{ .chunk = &fun.chunk, .pc = 0, .base_reg = new_base, .ret_pc = 0, .ret_dst = base + dec.a };
                    for (0..dec.c) |i| {
                        self.registers[new_base + i] = self.registers[base + dec.b + 1 + i];
                    }
                    self.frame_count += 1;
                    self.chunk = &fun.chunk;
                    self.pc = 0;
                } else {
                    return error.RuntimeError;
                }
            },
            .ret => {
                if (self.frame_count > 1) {
                    const d = OpCode.decodeAx(inst);
                    const ret_val = self.registers[base + d];
                    const ret_dst = self.frames[self.frame_count - 1].ret_dst;
                    self.frame_count -= 1;
                    const cf = &self.frames[self.frame_count - 1];
                    self.chunk = cf.chunk;
                    self.pc = cf.pc;
                    self.registers[ret_dst] = ret_val;
                } else {
                    return;
                }
            },

            .new_vec => { const d = OpCode.decodeABx(inst); const v = try self.allocator.create(VecObj); v.items = std.ArrayList(Value.Value).empty; for (0..d.bx) |_| try v.items.append(self.allocator, .nil); self.registers[base+d.a] = .{ .vec = v }; self.pc += 1; },
            .index_get => { const d = OpCode.decodeABC(inst); const obj = self.registers[base+d.b]; const idx = self.registers[base+d.c]; if (obj == .vec and idx == .int) { const v: *VecObj = @ptrCast(@alignCast(obj.vec)); const i: usize = @intCast(idx.int); if (i < v.items.items.len) { self.registers[base+d.a] = v.items.items[i]; } else return error.RuntimeError; } else return error.RuntimeError; self.pc += 1; },
            .index_len => { const d = OpCode.decodeABC(inst); const obj = self.registers[base+d.b]; if (obj == .vec) { const v: *VecObj = @ptrCast(@alignCast(obj.vec)); self.registers[base+d.a] = .{ .int = @intCast(v.items.items.len) }; } else return error.RuntimeError; self.pc += 1; },
            .vec_set => { const d = OpCode.decodeABC(inst); const v: *VecObj = @ptrCast(@alignCast(self.registers[base+d.a].vec)); if (@as(usize, d.b) < v.items.items.len) v.items.items[@intCast(d.b)] = self.registers[base+d.c]; self.pc += 1; },

            .move_op => { const d = OpCode.decodeABx(inst); self.registers[base+d.a] = self.registers[base+d.bx]; self.pc += 1; },

            .new_struct => {
                const r = base + OpCode.decodeAx(inst);
                const s = try self.allocator.create(Object.StructObj);
                s.fields = std.StringHashMap(Value.Value).init(self.allocator);
                self.registers[r] = .{ .vec = @ptrCast(s) }; // reuse vec slot for struct
                self.pc += 1;
            },
            .struct_set => {
                const d = OpCode.decodeABx(inst);
                const s: *Object.StructObj = @ptrCast(@alignCast(self.registers[base+d.a].vec));
                const name = self.chunk.?.constants.items[d.bx].string;
                try s.fields.put(name, self.registers[base+d.a + 1]);
                self.pc += 1;
            },
            .get_field => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                if (obj == .vec) {
                    const s: *Object.StructObj = @ptrCast(@alignCast(obj.vec));
                    const name = self.chunk.?.constants.items[d.c].string;
                    if (s.fields.get(name)) |val| {
                        self.registers[base + d.a] = val;
                    } else {
                        self.registers[base + d.a] = .nil;
                    }
                } else {
                    self.registers[base + d.a] = .nil;
                }
                self.pc += 1;
            },

            .try_prop => {
                const r = base + OpCode.decodeAx(inst);
                if (self.registers[r] == .nil) return error.RuntimeError;
                self.pc += 1;
            },

            else => return error.RuntimeError,
        }
    }
}

fn binaryOp(op: OpCode.OpCode, a: Value.Value, b: Value.Value) !Value.Value {
    return switch (op) {
        .add => switch (a) { .int => |ai| switch (b) { .int => |bi| .{ .int = ai + bi }, .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) + bf }, .string => |as| switch (b) { .string => |bs| blk: { const buf = try std.heap.page_allocator.alloc(u8, as.len + bs.len); @memcpy(buf[0..as.len], as); @memcpy(buf[as.len..], bs); break :blk .{ .string = buf }; }, else => return error.RuntimeError, }, else => return error.RuntimeError, }, .float => |af| switch (b) { .int => |bi| .{ .float = af + @as(f64, @floatFromInt(bi)) }, .float => |bf| .{ .float = af + bf }, else => return error.RuntimeError, }, .string => |as| switch (b) { .string => |bs| blk: { const buf = try std.heap.page_allocator.alloc(u8, as.len + bs.len); @memcpy(buf[0..as.len], as); @memcpy(buf[as.len..], bs); break :blk .{ .string = buf }; }, else => return error.RuntimeError, }, else => return error.RuntimeError, },
        .sub => switch (a) { .int => |ai| switch (b) { .int => |bi| .{ .int = ai - bi }, .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) - bf }, else => return error.RuntimeError, }, .float => |af| switch (b) { .int => |bi| .{ .float = af - @as(f64, @floatFromInt(bi)) }, .float => |bf| .{ .float = af - bf }, else => return error.RuntimeError, }, else => return error.RuntimeError, },
        .mul => switch (a) { .int => |ai| switch (b) { .int => |bi| .{ .int = ai * bi }, .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) * bf }, else => return error.RuntimeError, }, .float => |af| switch (b) { .int => |bi| .{ .float = af * @as(f64, @floatFromInt(bi)) }, .float => |bf| .{ .float = af * bf }, else => return error.RuntimeError, }, else => return error.RuntimeError, },
        .div_op => switch (a) { .int => |ai| switch (b) { .int => |bi| .{ .int = @divTrunc(ai, bi) }, .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) / bf }, else => return error.RuntimeError, }, .float => |af| switch (b) { .int => |bi| .{ .float = af / @as(f64, @floatFromInt(bi)) }, .float => |bf| .{ .float = af / bf }, else => return error.RuntimeError, }, else => return error.RuntimeError, },
        else => return error.RuntimeError,
    };
}

const VecObj = struct { items: std.ArrayList(Value.Value), };
