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
    code: []const u32,
    constants: []const Value.Value,
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
/// Tracks heap-allocated string slices owned by the VM, freed on deinit.
allocated_strings: std.ArrayList([]const u8),

/// Initialize a new VM with the given allocator. All registers default to nil.
pub fn init(allocator: std.mem.Allocator) VM {
    return .{
        .allocator = allocator,
        .registers = [_]Value.Value{.{ .nil = {} }} ** REGISTER_COUNT,
        .chunk = null,
        .pc = 0,
        .frames = undefined,
        .frame_count = 0,
        .globals = std.StringHashMap(Value.Value).init(allocator),
        .allocated_strings = std.ArrayList([]const u8).empty,
    };
}

/// Deinitialize the VM, freeing the globals hash map and VM-owned heap objects.
/// NOTE: FunObj instances are owned by the Compiler and freed there, not here.
pub fn deinit(self: *VM) void {
    // Free VM-owned heap objects in global variables (StringBuilderObj is
    // created at runtime by string concat, not by the compiler)
    var iter = self.globals.iterator();
    while (iter.next()) |entry| {
        const val = entry.value_ptr.*;
        if (val == .string_builder) {
            const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(val.string_builder));
            sb.buf.deinit(self.allocator);
            self.allocator.destroy(sb);
        }
    }
    self.globals.deinit();
    // Free tracked string allocations from stdlib (readln/readAll)
    for (self.allocated_strings.items) |s| {
        self.allocator.free(s);
    }
    self.allocated_strings.deinit(self.allocator);
}

/// Register a native function by name, making it callable from m4 code.
pub fn registerNative(self: *VM, name: []const u8, ptr: *anyopaque) !void {
    try self.globals.put(name, .{ .@"fn" = ptr });
}

/// Interpret (execute) a compiled bytecode chunk. Sets up the initial call frame and runs.
pub fn interpret(self: *VM, chunk: *const Chunk) !void {
    self.chunk = chunk;
    self.pc = 0;
    self.frame_count = 1;
    self.frames[0] = .{ .chunk = chunk, .code = chunk.code.items, .constants = chunk.constants.items, .pc = 0, .base_reg = 0, .ret_pc = 0, .ret_dst = 0 };
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
        err_mod.printDiagnostic(code, "Runtime Error", msg, null);
    }
    return error.RuntimeError;
}

inline fn cacheGetGlobal(self: *VM, name: []const u8) ?Value.Value {
    // Search for a hit — promote to front if found
    for (&self.global_cache, 0..) |*entry, i| {
        if (entry.name.ptr == name.ptr and entry.name.len == name.len) {
            const val = entry.value;
            // Found at index i — promote to position 0
            // Shift entries [0..i-1] right by 1 so they occupy [1..i]
            var j: usize = i;
            while (j > 0) : (j -= 1) {
                self.global_cache[j] = self.global_cache[j - 1];
            }
            self.global_cache[0] = .{ .name = name, .value = val };
            return val;
        }
    }
    // Miss — fetch from globals, insert at front, evict position 3
    if (self.globals.get(name)) |val| {
        // Right-shift: 0→1, 1→2, 2→3 (3 is evicted)
        self.global_cache[3] = self.global_cache[2];
        self.global_cache[2] = self.global_cache[1];
        self.global_cache[1] = self.global_cache[0];
        self.global_cache[0] = .{ .name = name, .value = val };
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
        .string_builder => false,
        .@"fn" => a.@"fn" == b.@"fn",
        .fun_obj => a.fun_obj == b.fun_obj,
        .thread_handle => a.thread_handle == b.thread_handle,
        .channel => a.channel == b.channel,
        .vec => a.vec == b.vec,
    };
}

/// Main VM dispatch loop. Executes bytecode instructions until halt or error.
pub fn run(self: *VM) !void {
    var frame: *CallFrame = &self.frames[0];
    var code: []const u32 = frame.code;
    var constants: []const Value.Value = frame.constants;
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
                self.registers[base + dec.a] = self.registers[base + dec.bx];
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
                self.registers[base + dec.bx] = self.registers[base + dec.a];
                pc += 1;
            },

            // ── Arithmetic: int-int fast path inlined ─────────────────
            .add => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    const ov = @addWithOverflow(a.int, b.int);
                    if (ov[1] != 0) return self.runtimeError("r017", "integer overflow in + operation", .{});
                    self.registers[base + d.a] = .{ .int = ov[0] };
                } else if ((a == .string or a == .string_builder) and (b == .string or b == .string_builder)) {
                    self.registers[base + d.a] = concatStrings(self.allocator, a, b) catch return self.runtimeError("r014", "out of memory", .{});
                } else {
                    self.registers[base + d.a] = binaryOp(.add, a, b, self.allocator) catch return self.runtimeError("r002", "type mismatch in + operation", .{});
                }
                pc += 1;
            },
            .sub => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    const ov = @subWithOverflow(a.int, b.int);
                    if (ov[1] != 0) return self.runtimeError("r017", "integer overflow in - operation", .{});
                    self.registers[base + d.a] = .{ .int = ov[0] };
                } else {
                    self.registers[base + d.a] = binaryOp(.sub, a, b, self.allocator) catch return self.runtimeError("r002", "type mismatch in - operation", .{});
                }
                pc += 1;
            },
            .mul => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    const ov = @mulWithOverflow(a.int, b.int);
                    if (ov[1] != 0) return self.runtimeError("r017", "integer overflow in * operation", .{});
                    self.registers[base + d.a] = .{ .int = ov[0] };
                } else {
                    self.registers[base + d.a] = binaryOp(.mul, a, b, self.allocator) catch return self.runtimeError("r002", "type mismatch in * operation", .{});
                }
                pc += 1;
            },
            .div_op => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    if (b.int == 0) return self.runtimeError("r012", "division by zero", .{});
                    if (a.int == std.math.minInt(i64) and b.int == -1) return self.runtimeError("r017", "integer overflow in / operation", .{});
                    self.registers[base + d.a] = .{ .int = @divTrunc(a.int, b.int) };
                } else {
                    self.registers[base + d.a] = binaryOp(.div_op, a, b, self.allocator) catch return self.runtimeError("r002", "type mismatch in / operation", .{});
                }
                pc += 1;
            },
            .mod_op => {
                const d = OpCode.decodeABC(inst);
                const a = self.registers[base + d.b];
                const b = self.registers[base + d.c];
                if (a == .int and b == .int) {
                    if (b.int == 0) return self.runtimeError("r013", "modulo by zero", .{});
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
                    .int => |i| blk: {
                        if (i == std.math.minInt(i64)) return self.runtimeError("r017", "integer overflow in negation", .{});
                        break :blk .{ .int = -i };
                    },
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
                const a_val = self.registers[base + d.b];
                const b_val = self.registers[base + d.c];
                self.registers[base + d.a] = if (isStringLike(a_val) or isStringLike(b_val))
                    .{ .bool = std.mem.eql(u8, stringSlice(a_val), stringSlice(b_val)) }
                else
                    .{ .bool = fastEql(a_val, b_val) };
                pc += 1;
            },
            .neq => {
                const d = OpCode.decodeABC(inst);
                const a_val = self.registers[base + d.b];
                const b_val = self.registers[base + d.c];
                self.registers[base + d.a] = if (isStringLike(a_val) or isStringLike(b_val))
                    .{ .bool = !std.mem.eql(u8, stringSlice(a_val), stringSlice(b_val)) }
                else
                    .{ .bool = !fastEql(a_val, b_val) };
                pc += 1;
            },
            .gt => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int > r.int };
                } else if (isStringLike(l) and isStringLike(r)) {
                    self.registers[base + d.a] = try cmpSlow(.gt, l, r);
                } else {
                    self.registers[base + d.a] = cmpSlow(.gt, l, r) catch return self.runtimeError("r005", "cannot compare values of different types", .{});
                }
                pc += 1;
            },
            .lt => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int < r.int };
                } else if (isStringLike(l) and isStringLike(r)) {
                    self.registers[base + d.a] = try cmpSlow(.lt, l, r);
                } else {
                    self.registers[base + d.a] = cmpSlow(.lt, l, r) catch return self.runtimeError("r005", "cannot compare values of different types", .{});
                }
                pc += 1;
            },
            .gte => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int >= r.int };
                } else if (isStringLike(l) and isStringLike(r)) {
                    self.registers[base + d.a] = try cmpSlow(.gte, l, r);
                } else {
                    self.registers[base + d.a] = cmpSlow(.gte, l, r) catch return self.runtimeError("r005", "cannot compare values of different types", .{});
                }
                pc += 1;
            },
            .lte => {
                const d = OpCode.decodeABC(inst);
                const l = self.registers[base + d.b];
                const r = self.registers[base + d.c];
                if (l == .int and r == .int) {
                    self.registers[base + d.a] = .{ .bool = l.int <= r.int };
                } else if (isStringLike(l) and isStringLike(r)) {
                    self.registers[base + d.a] = try cmpSlow(.lte, l, r);
                } else {
                    self.registers[base + d.a] = cmpSlow(.lte, l, r) catch return self.runtimeError("r005", "cannot compare values of different types", .{});
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
                    const arg_count = dec.c;
                    self.frame_count += 1;
                    frame = &self.frames[self.frame_count - 1];
                    frame.chunk = &fun.chunk;
                    frame.code = fun.chunk.code.items;
                    frame.constants = fun.chunk.constants.items;
                    frame.pc = 0;
                    frame.base_reg = new_base;
                    frame.ret_pc = 0;
                    frame.ret_dst = base + dec.a;
                    // Copy args — unrolled for small arg counts (hot path for Fibonacci)
                    const arg_base = base + dec.b + 1;
                    switch (arg_count) {
                        0 => {},
                        1 => self.registers[new_base] = self.registers[arg_base],
                        2 => {
                            self.registers[new_base] = self.registers[arg_base];
                            self.registers[new_base + 1] = self.registers[arg_base + 1];
                        },
                        else => for (0..arg_count) |i| {
                            self.registers[new_base + i] = self.registers[arg_base + i];
                        },
                    }
                    code = frame.code;
                    constants = frame.constants;
                    pc = 0;
                } else if (callee == .@"fn") {
                    const native: NativeFn = @ptrCast(@alignCast(callee.@"fn"));
                    // Finalize any string_builder args to plain strings before native call
                    for (0..dec.c) |i| {
                        const arg_reg = base + dec.b + 1 + i;
                        if (self.registers[arg_reg] == .string_builder) {
                            const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(self.registers[arg_reg].string_builder));
                            self.registers[arg_reg] = .{ .string = sb.buf.items };
                        }
                    }
                    const result = native(self, self.registers[(base + dec.b + 1)..(base + dec.b + 1 + dec.c)]);
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
                    code = frame.code;
                    constants = frame.constants;
                    pc = frame.pc;
                    self.registers[ret_dst] = ret_val;
                } else {
                    return;
                }
            },

            .new_vec => {
                const d = OpCode.decodeABx(inst);
                const v = try self.allocator.create(VecObj);
                v.items = std.ArrayList(Value.Value).initCapacity(self.allocator, d.bx) catch return self.runtimeError("r014", "out of memory", .{});
                for (0..d.bx) |_| v.items.appendAssumeCapacity(.nil);
                self.registers[base + d.a] = .{ .vec = v };
                pc += 1;
            },
            .index_get => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                const idx = self.registers[base + d.c];
                if (idx != .int) return self.runtimeError("r009", "index must be an integer", .{});
                const i: usize = @intCast(idx.int);
                switch (obj) {
                    .vec => {
                        const v: *VecObj = @ptrCast(@alignCast(obj.vec));
                        if (i < v.items.items.len) {
                            self.registers[base + d.a] = v.items.items[i];
                        } else return self.runtimeError("r008", "index out of bounds", .{});
                    },
                    .string => {
                        if (i < obj.string.len) {
                            self.registers[base + d.a] = .{ .char = obj.string[i] };
                        } else return self.runtimeError("r008", "index out of bounds", .{});
                    },
                    .string_builder => {
                        const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(obj.string_builder));
                        if (i < sb.buf.items.len) {
                            self.registers[base + d.a] = .{ .char = sb.buf.items[i] };
                        } else return self.runtimeError("r008", "index out of bounds", .{});
                    },
                    else => return self.runtimeError("r009", "cannot index non-indexable value", .{}),
                }
                pc += 1;
            },
            .index_len => {
                const d = OpCode.decodeABC(inst);
                const obj = self.registers[base + d.b];
                switch (obj) {
                    .vec => {
                        const v: *VecObj = @ptrCast(@alignCast(obj.vec));
                        self.registers[base + d.a] = .{ .int = @intCast(v.items.items.len) };
                    },
                    .string => {
                        self.registers[base + d.a] = .{ .int = @intCast(obj.string.len) };
                    },
                    .string_builder => {
                        const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(obj.string_builder));
                        self.registers[base + d.a] = .{ .int = @intCast(sb.buf.items.len) };
                    },
                    else => return self.runtimeError("r009", "cannot get length of non-indexable value", .{}),
                }
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

fn concatStrings(allocator: std.mem.Allocator, a: Value.Value, b: Value.Value) !Value.Value {
    const b_slice = stringSlice(b);
    // If left operand is already a StringBuilder, append to it — this is the hot path for repeated "s = s + \"a\""
    if (a == .string_builder) {
        const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(a.string_builder));
        try sb.buf.appendSlice(allocator, b_slice);
        return a;
    }
    // If right operand is a StringBuilder but left isn't, prepend left to it
    if (b == .string_builder) {
        const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(b.string_builder));
        const a_slice = stringSlice(a);
        try sb.buf.insertSlice(allocator, 0, a_slice);
        return b;
    }
    // Both are .string — create a brand new StringBuilder with over-allocation
    const sb = try allocator.create(Object.StringBuilderObj);
    const a_slice = stringSlice(a);
    const cap = a_slice.len + b_slice.len + @max(a_slice.len, b_slice.len);
    sb.buf = try std.ArrayList(u8).initCapacity(allocator, cap);
    sb.buf.appendSliceAssumeCapacity(a_slice);
    sb.buf.appendSliceAssumeCapacity(b_slice);
    return .{ .string_builder = sb };
}

inline fn isStringLike(v: Value.Value) bool {
    return v == .string or v == .string_builder;
}

fn stringSlice(v: Value.Value) []const u8 {
    return switch (v) {
        .string => |s| s,
        .string_builder => blk: {
            const sb: *Object.StringBuilderObj = @ptrCast(@alignCast(v.string_builder));
            break :blk sb.buf.items;
        },
        else => unreachable,
    };
}

fn binaryOp(op: OpCode.OpCode, a: Value.Value, b: Value.Value, allocator: std.mem.Allocator) !Value.Value {
    _ = allocator;
    return switch (op) {
        .add => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| {
                    const ov = @addWithOverflow(ai, bi);
                    if (ov[1] != 0) return error.RuntimeError;
                    return .{ .int = ov[0] };
                },
                .float => |bf| .{ .float = @as(f64, @floatFromInt(ai)) + bf },
                else => error.RuntimeError,
            },
            .float => |af| switch (b) {
                .int => |bi| .{ .float = af + @as(f64, @floatFromInt(bi)) },
                .float => |bf| .{ .float = af + bf },
                else => error.RuntimeError,
            },
            else => error.RuntimeError,
        },
        .sub => switch (a) {
            .int => |ai| switch (b) {
                .int => |bi| {
                    const ov = @subWithOverflow(ai, bi);
                    if (ov[1] != 0) return error.RuntimeError;
                    return .{ .int = ov[0] };
                },
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
                .int => |bi| {
                    const ov = @mulWithOverflow(ai, bi);
                    if (ov[1] != 0) return error.RuntimeError;
                    return .{ .int = ov[0] };
                },
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
                .int => |bi| {
                    if (bi == 0) return error.RuntimeError;
                    if (ai == std.math.minInt(i64) and bi == -1) return error.RuntimeError;
                    return .{ .int = @divTrunc(ai, bi) };
                },
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
        OpCode.OpCode.gt => cmpOrder(OpCode.OpCode.gt, l, r),
        OpCode.OpCode.lt => cmpOrder(OpCode.OpCode.lt, l, r),
        OpCode.OpCode.gte => cmpOrder(OpCode.OpCode.gte, l, r),
        OpCode.OpCode.lte => cmpOrder(OpCode.OpCode.lte, l, r),
        else => error.RuntimeError,
    };
}

fn cmpOrder(op: OpCode.OpCode, l: Value.Value, r: Value.Value) !Value.Value {
    const order = try cmpValues(l, r);
    return switch (op) {
        .gt => .{ .bool = order == std.math.Order.gt },
        .lt => .{ .bool = order == std.math.Order.lt },
        .gte => .{ .bool = order != std.math.Order.lt },
        .lte => .{ .bool = order != std.math.Order.gt },
        else => error.RuntimeError,
    };
}

fn cmpValues(l: Value.Value, r: Value.Value) !std.math.Order {
    return switch (l) {
        .int => |li| switch (r) {
            .int => @as(std.math.Order, if (li < r.int) .lt else if (li > r.int) .gt else .eq),
            .float => |rf| {
                const lf = @as(f64, @floatFromInt(li));
                return if (lf < rf) std.math.Order.lt else if (lf > rf) std.math.Order.gt else std.math.Order.eq;
            },
            else => error.RuntimeError,
        },
        .float => |lf| switch (r) {
            .int => |ri| {
                const rf = @as(f64, @floatFromInt(ri));
                return if (lf < rf) std.math.Order.lt else if (lf > rf) std.math.Order.gt else std.math.Order.eq;
            },
            .float => |rf| if (lf < rf) std.math.Order.lt else if (lf > rf) std.math.Order.gt else std.math.Order.eq,
            else => error.RuntimeError,
        },
        .string_builder, .string => switch (r) {
            .string_builder, .string => std.mem.order(u8, stringSlice(l), stringSlice(r)),
            else => error.RuntimeError,
        },
        else => error.RuntimeError,
    };
}

const VecObj = struct {
    items: std.ArrayList(Value.Value),
};

test "vm: string equality comparison" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_abc = try chunk.addConstant(.{ .string = "abc" });
    const idx_abd = try chunk.addConstant(.{ .string = "abd" });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_abc), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_abd), 1);
    try chunk.write(OpCode.encodeABC(.eq, 2, 0, 1), 1); // r2 = "abc" == "abd" → false
    try chunk.write(OpCode.encodeABC(.neq, 3, 0, 1), 1); // r3 = "abc" != "abd" → true
    try chunk.write(OpCode.encodeABC(.eq, 4, 0, 0), 1); // r4 = "abc" == "abc" → true
    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpret(&chunk);

    try std.testing.expect(!vm.registers[2].bool);
    try std.testing.expect(vm.registers[3].bool);
    try std.testing.expect(vm.registers[4].bool);
}

test "vm: string ordering comparison" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_abc = try chunk.addConstant(.{ .string = "abc" });
    const idx_abd = try chunk.addConstant(.{ .string = "abd" });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_abc), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_abd), 1);

    try chunk.write(OpCode.encodeABC(.lt, 2, 0, 1), 1); // r2 = "abc" < "abd" → true
    try chunk.write(OpCode.encodeABC(.gt, 3, 0, 1), 1); // r3 = "abc" > "abd" → false
    try chunk.write(OpCode.encodeABC(.lte, 4, 0, 1), 1); // r4 = "abc" <= "abd" → true
    try chunk.write(OpCode.encodeABC(.gte, 5, 0, 1), 1); // r5 = "abc" >= "abd" → false
    try chunk.write(OpCode.encodeABC(.lte, 6, 0, 0), 1); // r6 = "abc" <= "abc" → true
    try chunk.write(OpCode.encodeABC(.gte, 7, 0, 0), 1); // r7 = "abc" >= "abc" → true
    try chunk.write(OpCode.encodeABC(.lt, 8, 1, 0), 1); // r8 = "abd" < "abc" → false

    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpret(&chunk);

    try std.testing.expect(vm.registers[2].bool);
    try std.testing.expect(!vm.registers[3].bool);
    try std.testing.expect(vm.registers[4].bool);
    try std.testing.expect(!vm.registers[5].bool);
    try std.testing.expect(vm.registers[6].bool);
    try std.testing.expect(vm.registers[7].bool);
    try std.testing.expect(!vm.registers[8].bool);
}

test "vm: string length" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_hello = try chunk.addConstant(.{ .string = "hello" });
    const idx_empty = try chunk.addConstant(.{ .string = "" });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_hello), 1);
    try chunk.write(OpCode.encodeABC(.index_len, 1, 0, 0), 1); // r1 = len("hello") = 5
    try chunk.write(OpCode.encodeABx(.load_const, 2, idx_empty), 1);
    try chunk.write(OpCode.encodeABC(.index_len, 3, 2, 0), 1); // r3 = len("") = 0

    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpret(&chunk);

    try std.testing.expectEqual(@as(i64, 5), vm.registers[1].int);
    try std.testing.expectEqual(@as(i64, 0), vm.registers[3].int);
}

test "vm: string indexing" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_hello = try chunk.addConstant(.{ .string = "hello" });
    const idx_0 = try chunk.addConstant(.{ .int = 0 });
    const idx_1 = try chunk.addConstant(.{ .int = 1 });
    const idx_4 = try chunk.addConstant(.{ .int = 4 });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_hello), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_0), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 2, idx_1), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 3, idx_4), 1);

    try chunk.write(OpCode.encodeABC(.index_get, 4, 0, 1), 1); // r4 = "hello"[0] = 'h'
    try chunk.write(OpCode.encodeABC(.index_get, 5, 0, 2), 1); // r5 = "hello"[1] = 'e'
    try chunk.write(OpCode.encodeABC(.index_get, 6, 0, 3), 1); // r6 = "hello"[4] = 'o'

    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpret(&chunk);

    try std.testing.expectEqual(@as(u8, 'h'), vm.registers[4].char);
    try std.testing.expectEqual(@as(u8, 'e'), vm.registers[5].char);
    try std.testing.expectEqual(@as(u8, 'o'), vm.registers[6].char);
}

test "vm: string indexing out of bounds" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_hi = try chunk.addConstant(.{ .string = "hi" });
    const idx_99 = try chunk.addConstant(.{ .int = 99 });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_hi), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_99), 1);
    try chunk.write(OpCode.encodeABC(.index_get, 2, 0, 1), 1); // r2 = "hi"[99] → out of bounds
    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.RuntimeError, vm.interpret(&chunk));
}

test "vm: string concatenation" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_hello = try chunk.addConstant(.{ .string = "hello" });
    const idx_world = try chunk.addConstant(.{ .string = " world" });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_hello), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_world), 1);
    try chunk.write(OpCode.encodeABC(.add, 0, 0, 1), 1); // r0 = "hello" + " world"
    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpret(&chunk);

    try std.testing.expectEqualStrings("hello world", vm.registers[0].string);
}

test "vm: string type mismatch on comparison" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();

    const idx_str = try chunk.addConstant(.{ .string = "hello" });
    const idx_int = try chunk.addConstant(.{ .int = 42 });

    try chunk.write(OpCode.encodeABx(.load_const, 0, idx_str), 1);
    try chunk.write(OpCode.encodeABx(.load_const, 1, idx_int), 1);
    try chunk.write(OpCode.encodeABC(.lt, 2, 0, 1), 1); // r2 = "hello" < 42 → type mismatch error
    try chunk.write(OpCode.encodeAx(.halt, 0), 1);

    var vm = VM.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.RuntimeError, vm.interpret(&chunk));
}
