const std = @import("std");
const OpCode = @import("opcode.zig");
const Value = @import("value.zig");
const Chunk = @import("chunk.zig").Chunk;
const Object = @import("object.zig");
const err_mod = @import("error.zig");

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

const GlobalCache = struct {
    name: []const u8,
    value: Value.Value,
};

pub const VM = @This();

allocator: std.mem.Allocator,
registers: [REGISTER_COUNT]Value.Value,
chunk: ?*const Chunk,
pc: usize,
frames: [FRAMES_MAX]CallFrame,
frame_count: usize,
globals: std.StringHashMap(Value.Value),
diag: ?*err_mod.DiagnosticList = null,
global_cache: [4]GlobalCache = [_]GlobalCache{.{ .name = "", .value = .nil }} ** 4,

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

fn runtimeError(self: *VM, code: []const u8, comptime fmt: []const u8, args: anytype) error{RuntimeError} {
    const msg = std.fmt.allocPrint(self.allocator, fmt, args) catch "runtime error";
    if (self.diag) |diag| {
        diag.add(self.allocator, .{
            .severity = .@"error",
            .code = code,
            .message = msg,
        }) catch {};
    } else {
        std.debug.print("Runtime error [{s}]: {s}\n", .{ code, msg });
    }
    return error.RuntimeError;
}

fn cacheGetGlobal(self: *VM, name: []const u8) ?Value.Value {
    for (&self.global_cache) |*entry| {
        if (entry.name.ptr == name.ptr and entry.name.len == name.len) {
            return entry.value;
        }
    }
    if (self.globals.get(name)) |val| {
        self.global_cache[0] = self.global_cache[1];
        self.global_cache[1] = self.global_cache[2];
        self.global_cache[2] = self.global_cache[3];
        self.global_cache[3] = .{ .name = name, .value = val };
        return val;
    }
    return null;
}

// Inline truthiness check — avoids function call overhead on every branch
inline fn isTruthy(v: Value.Value) bool {
    return switch (v) {
        .nil => false,
        .bool => |b| b,
        .int => |i| i != 0,
        .float => |f| f != 0.0,
        else => true,
    };
}

// Inline equality check for the fast path (same-type, no string)
inline fn fastEql(a: Value.Value, b: Value.Value) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;
    return switch (a) {
        .nil => true,
        .bool => a.bool == b.bool,
        .int => a.int == b.int,
        .float => a.float == b.float,
        .char => a.char == b.char,
        .string => std.mem.eql(u8, a.string, b.string),
        .@"fn" => a.@"fn" == b.@"fn",
        .fun_obj => a.fun_obj == b.fun_obj,
        .vec => a.vec == b.vec,
    };
}

pub fn run(self: *VM) !void {
    var code: []const u32 = self.chunk.?.code.items;
    var constants: []const Value.Value = self.chunk.?.constants.items;
    var frame: *CallFrame = &self.frames[0];
    var pc: usize = self.pc;

    while (true) {
        if (pc >= code.len) break;
        const inst = code[pc];
        const op = OpCode.decodeOp(inst);
        const base = frame.base_reg;

        switch (op) {
            .halt => return,

            .load_const => {
                const dec = OpCode.decodeABx(inst);
                self.registers[base + dec.a] = constants[dec.bx];
                pc += 1;
            },
            .load_true => {
                self.registers[base + OpCode.decodeAx(inst)] = .{ .bool = true };
                pc += 1;
            },
            .load_false => {
                self.registers[base + OpCode.decodeAx(inst)] = .{ .bool = false };
                pc += 1;
            },
            .load_nil => {
                self.registers[base + OpCode.decodeAx(inst)] = .nil;
                pc += 1;
            },
            .load_global => {
                const dec = OpCode.decodeABx(inst);
                const name = constants[dec.bx].string;
                if (self.cacheGetGlobal(name)) |val| {
                    self.registers[base + dec.a] = val;
                } else {
                    return self.runtimeError("r001", "undefined variable '{s}'", .{name});
                }
                pc += 1;
            },
            .load_local => {
                const dec = OpCode.decodeABx(inst);
                self.registers[base + dec.a] = self.registers[frame.base_reg + dec.bx];
                pc += 1;
            },
            .store_global => {
                const dec = OpCode.decodeABx(inst);
                const name = constants[dec.bx].string;
                const val = self.registers[base + dec.a];
                try self.globals.put(name, val);
                for (&self.global_cache) |*entry| {
                    if (entry.name.ptr == name.ptr and entry.name.len == name.len) {
                        entry.value = val;
                        break;
                    }
                }
                pc += 1;
            },
            .store_local => {
                const dec = OpCode.decodeABx(inst);
                self.registers[frame.base_reg + dec.bx] = self.registers[base + dec.a];
                pc += 1;
            },

            // ── Arithmetic: int-int fast path inlined ─────────────────
            .add => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    self.registers[base + d.a] = .{ .int = a.int + b.int };
                } else {
                    self.registers[base + d.a] = binaryOp(.add, a, b) catch return self.runtimeError("r002", "type mismatch in + operation", .{});
                }
                pc += 1;
            },
            .sub => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    self.registers[base + d.a] = .{ .int = a.int - b.int };
                } else {
                    self.registers[base + d.a] = binaryOp(.sub, a, b) catch return self.runtimeError("r002", "type mismatch in - operation", .{});
                }
                pc += 1;
            },
            .mul => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    self.registers[base + d.a] = .{ .int = a.int * b.int };
                } else {
                    self.registers[base + d.a] = binaryOp(.mul, a, b) catch return self.runtimeError("r002", "type mismatch in * operation", .{});
                }
                pc += 1;
            },
            .div_op => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    self.registers[base + d.a] = .{ .int = @divTrunc(a.int, b.int) };
                } else {
                    self.registers[base + d.a] = binaryOp(.div_op, a, b) catch return self.runtimeError("r002", "type mismatch in / operation", .{});
                }
                pc += 1;
            },
            .mod_op => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    self.registers[base + d.a] = .{ .int = @mod(a.int, b.int) };
                } else {
                    return self.runtimeError("r003", "modulo requires integer operands", .{});
                }
                pc += 1;
            },

            .neg => {
                const r = base + OpCode.decodeAx(inst);
                const v = self.registers[r];
                self.registers[r] = switch (v) {
                    .int => |i| .{ .int = -i },
                    .float => |f| .{ .float = -f },
                    else => return self.runtimeError("r004", "cannot negate non-numeric value", .{}),
                };
                pc += 1;
            },
            .not_ => {
                const r = base + OpCode.decodeAx(inst);
                self.registers[r] = .{ .bool = !isTruthy(self.registers[r]) };
                pc += 1;
            },

            // ── Comparisons: int-int fast path ────────────────────────
            .eq => {
                const d = OpCode.decodeABC(inst);
                self.registers[base + d.a] = .{ .bool = fastEql(self.registers[base + d.b], self.registers[base + d.c]) };
                pc += 1;
            },
            .neq => {
                const d = OpCode.decodeABC(inst);
                self.registers[base + d.a] = .{ .bool = !fastEql(self.registers[base + d.b], self.registers[base + d.c]) };
                pc += 1;
            },
            .gt => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int > r.int };
                } else {
                    self.registers[base + d.a] = cmpSlow(.gt, l, r) catch return self.runtimeError("r005", "cannot compare non-numeric types", .{});
                }
                pc += 1;
            },
            .lt => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int < r.int };
                } else {
                    self.registers[base + d.a] = cmpSlow(.lt, l, r) catch return self.runtimeError("r005", "cannot compare non-numeric types", .{});
                }
                pc += 1;
            },
            .gte => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int >= r.int };
                } else {
                    self.registers[base + d.a] = cmpSlow(.gte, l, r) catch return self.runtimeError("r005", "cannot compare non-numeric types", .{});
                }
                pc += 1;
            },
            .lte => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int <= r.int };
                } else {
                    self.registers[base + d.a] = cmpSlow(.lte, l, r) catch return self.runtimeError("r005", "cannot compare non-numeric types", .{});
                }
                pc += 1;
            },
            .and_ => {
                const d = OpCode.decodeABC(inst);
                self.registers[base + d.a] = .{ .bool = isTruthy(self.registers[base + d.b]) and isTruthy(self.registers[base + d.c]) };
                pc += 1;
            },
            .or_ => {
                const d = OpCode.decodeABC(inst);
                self.registers[base + d.a] = .{ .bool = isTruthy(self.registers[base + d.b]) or isTruthy(self.registers[base + d.c]) };
                pc += 1;
            },

            .jump => {
                const d = OpCode.decodeAsBx(inst);
                pc = @intCast(@as(i32, @intCast(pc)) + d.sbx);
            },
            .jump_if_false => {
                const d = OpCode.decodeAsBx(inst);
                if (!isTruthy(self.registers[base + d.a])) {
                    pc = @intCast(@as(i32, @intCast(pc)) + d.sbx);
                } else {
                    pc += 1;
                }
            },
            .jump_if_true => {
                const d = OpCode.decodeAsBx(inst);
                if (isTruthy(self.registers[base + d.a])) {
                    pc = @intCast(@as(i32, @intCast(pc)) + d.sbx);
                } else {
                    pc += 1;
                }
            },

            // ── Call: user-function (fun_obj) checked first for hot path ──
            .call => {
                const dec = OpCode.decodeABC(inst);
                const callee = self.registers[base + dec.b];
                if (callee == .fun_obj) {
                    const fun: *Object.FunObj = @ptrCast(@alignCast(callee.fun_obj));
                    if (self.frame_count >= FRAMES_MAX) return self.runtimeError("r006", "stack overflow: too many nested calls", .{});
                    frame.pc = pc + 1;
                    const new_base = base + dec.b + 1 + dec.c;
                    self.frame_count += 1;
                    frame = &self.frames[self.frame_count - 1];
                    frame.chunk = &fun.chunk;
                    frame.pc = 0;
                    frame.base_reg = new_base;
                    frame.ret_pc = 0;
                    frame.ret_dst = base + dec.a;
                    // Copy args
                    for (0..dec.c) |i| {
                        self.registers[new_base + i] = self.registers[base + dec.b + 1 + i];
                    }
                    code = frame.chunk.code.items;
                    constants = frame.chunk.constants.items;
                    pc = 0;
                } else if (callee == .@"fn") {
                    const native: NativeFn = @ptrCast(@alignCast(callee.@"fn"));
                    const result = native(self, self.registers[(base + dec.b + 1) .. (base + dec.b + 1 + dec.c)]);
                    self.registers[base + dec.a] = result;
                    pc += 1;
                } else {
                    return self.runtimeError("r007", "value is not callable", .{});
                }
            },
            .ret => {
                if (self.frame_count > 1) {
                    const d = OpCode.decodeAx(inst);
                    const ret_val = self.registers[base + d];
                    const ret_dst = frame.ret_dst;
                    self.frame_count -= 1;
                    frame = &self.frames[self.frame_count - 1];
                    code = frame.chunk.code.items;
                    constants = frame.chunk.constants.items;
                    pc = frame.pc;
                    self.registers[ret_dst] = ret_val;
                } else {
                    return;
                }
            },

            .new_vec => {
                const d = OpCode.decodeABx(inst);
                const v = try self.allocator.create(VecObj);
                v.items = std.ArrayList(Value.Value).initCapacity(self.allocator, d.bx) catch return self.runtimeError("r012", "out of memory", .{});
                for (0..d.bx) |_| v.items.appendAssumeCapacity(.nil);
                self.registers[base + d.a] = .{ .vec = v };
                pc += 1;
            },
            .index_get => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                const idx = self.registers[base + d.c];
                if (obj == .vec and idx == .int) {
                    const v: *VecObj = @ptrCast(@alignCast(obj.vec));
                    const i: usize = @intCast(idx.int);
                    if (i < v.items.items.len) {
                        self.registers[base + d.a] = v.items.items[i];
                    } else return self.runtimeError("r008", "index out of bounds", .{});
                } else return self.runtimeError("r009", "cannot index non-vector value", .{});
                pc += 1;
            },
            .index_len => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                if (obj == .vec) {
                    const v: *VecObj = @ptrCast(@alignCast(obj.vec));
                    self.registers[base + d.a] = .{ .int = @intCast(v.items.items.len) };
                } else return self.runtimeError("r009", "cannot get length of non-indexable value", .{});
                pc += 1;
            },
            .vec_set => {
                const d = OpCode.decodeABC(inst);
                const v: *VecObj = @ptrCast(@alignCast(self.registers[base + d.a].vec));
                if (@as(usize, d.b) < v.items.items.len) v.items.items[@intCast(d.b)] = self.registers[base + d.c];
                pc += 1;
            },

            .move_op => {
                const d = OpCode.decodeABx(inst);
                self.registers[base + d.a] = self.registers[base + d.bx];
                pc += 1;
            },

            .new_struct => {
                const r = base + OpCode.decodeAx(inst);
                const s = try self.allocator.create(Object.StructObj);
                s.fields = std.StringHashMap(Value.Value).init(self.allocator);
                self.registers[r] = .{ .vec = @ptrCast(s) };
                pc += 1;
            },
            .struct_set => {
                const d = OpCode.decodeABx(inst);
                const s: *Object.StructObj = @ptrCast(@alignCast(self.registers[base + d.a].vec));
                const name = constants[d.bx].string;
                try s.fields.put(name, self.registers[base + d.a + 1]);
                pc += 1;
            },
            .get_field => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                if (obj == .vec) {
                    const s: *Object.StructObj = @ptrCast(@alignCast(obj.vec));
                    const name = constants[d.c].string;
                    self.registers[base + d.a] = s.fields.get(name) orelse .nil;
                } else {
                    self.registers[base + d.a] = .nil;
                }
                pc += 1;
            },

            .try_prop => {
                const r = base + OpCode.decodeAx(inst);
                if (self.registers[r] == .nil) return self.runtimeError("r010", "nil value unwrapped with ! operator", .{});
                pc += 1;
            },

            else => return self.runtimeError("r011", "unknown opcode", .{}),
        }
    }
    self.pc = pc;
    self.chunk = frame.chunk;
}

fn binaryOp(op: OpCode.OpCode, a: Value.Value, b: Value.Value) !Value.Value {
    return switch (op) {
        .add => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| .{ .int = ai + bi },
                .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) + bf },
                .string => |as| switch (b) {
                    .string => |bs| blk: {
                        const buf = try std.heap.page_allocator.alloc(u8, as.len + bs.len);
                        @memcpy(buf[0..as.len], as);
                        @memcpy(buf[as.len..], bs);
                        break :blk .{ .string = buf };
                    },
                    else => error.RuntimeError,
                },
                else => error.RuntimeError,
            },
            .float => |af| switch (b) {
                .int => |bi| .{ .float = af + @as(f64, @floatFromInt(bi)) },
                .float => |bf| .{ .float = af + bf },
                else => error.RuntimeError,
            },
            .string => |as| switch (b) {
                .string => |bs| blk: {
                    const buf = try std.heap.page_allocator.alloc(u8, as.len + bs.len);
                    @memcpy(buf[0..as.len], as);
                    @memcpy(buf[as.len..], bs);
                    break :blk .{ .string = buf };
                },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .sub => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| .{ .int = ai - bi },
                .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) - bf },
                else => error.RuntimeError,
            },
            .float => |af| switch (b) {
                .int => |bi| .{ .float = af - @as(f64, @floatFromInt(bi)) },
                .float => |bf| .{ .float = af - bf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .mul => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| .{ .int = ai * bi },
                .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) * bf },
                else => error.RuntimeError,
            },
            .float => |af| switch (b) {
                .int => |bi| .{ .float = af * @as(f64, @floatFromInt(bi)) },
                .float => |bf| .{ .float = af * bf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .div_op => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| .{ .int = @divTrunc(ai, bi) },
                .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) / bf },
                else => error.RuntimeError,
            },
            .float => |af| switch (b) {
                .int => |bi| .{ .float = af / @as(f64, @floatFromInt(bi)) },
                .float => |bf| .{ .float = af / bf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        else => error.RuntimeError,
    };
}

fn cmpSlow(op: OpCode.OpCode, l: Value.Value, r: Value.Value) !Value.Value {
    return switch (op) {
        .gt => switch (l) {
            .int => |li| switch (r) {
                .int => |ri| .{ .bool = li > ri },
                .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) > rf },
                else => error.RuntimeError,
            },
            .float => |lf| switch (r) {
                .int => |ri| .{ .bool = lf > @as(f64, @floatFromInt(ri)) },
                .float => |rf| .{ .bool = lf > rf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .lt => switch (l) {
            .int => |li| switch (r) {
                .int => |ri| .{ .bool = li < ri },
                .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) < rf },
                else => error.RuntimeError,
            },
            .float => |lf| switch (r) {
                .int => |ri| .{ .bool = lf < @as(f64, @floatFromInt(ri)) },
                .float => |rf| .{ .bool = lf < rf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .gte => switch (l) {
            .int => |li| switch (r) {
                .int => |ri| .{ .bool = li >= ri },
                .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) >= rf },
                else => error.RuntimeError,
            },
            .float => |lf| switch (r) {
                .int => |ri| .{ .bool = lf >= @as(f64, @floatFromInt(ri)) },
                .float => |rf| .{ .bool = lf >= rf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .lte => switch (l) {
            .int => |li| switch (r) {
                .int => |ri| .{ .bool = li <= ri },
                .float => |rf| .{ .bool = @as(f64, @floatFromInt(li)) <= rf },
                else => error.RuntimeError,
            },
            .float => |lf| switch (r) {
                .int => |ri| .{ .bool = lf <= @as(f64, @floatFromInt(ri)) },
                .float => |rf| .{ .bool = lf <= rf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        else => error.RuntimeError,
    };
}

const VecObj = struct { items: std.ArrayList(Value.Value), };
