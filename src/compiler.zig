const std = @import("std");
const ast = @import("ast.zig");
const OpCode = @import("opcode.zig");
const Chunk = @import("chunk.zig").Chunk;
const Value = @import("value.zig");
const Object = @import("object.zig");
const err_mod = @import("error.zig");

const Local = struct {
    name: []const u8,
    slot: u8,
    mutable: bool,
};

const Locals = struct {
    list: std.ArrayList(Local),
    map: std.StringHashMap(u8),

    fn init(allocator: std.mem.Allocator) Locals {
        return .{
            .list = std.ArrayList(Local).empty,
            .map = std.StringHashMap(u8).init(allocator),
        };
    }

    fn deinit(self: *Locals, allocator: std.mem.Allocator) void {
        self.list.deinit(allocator);
        self.map.deinit();
    }

    fn add(self: *Locals, allocator: std.mem.Allocator, name: []const u8, slot: u8, mutable: bool) !void {
        try self.list.append(allocator, .{ .name = name, .slot = slot, .mutable = mutable });
        try self.map.put(name, slot);
    }

    fn resolve(self: *const Locals, name: []const u8) ?u8 {
        return self.map.get(name);
    }
};

const LoopInfo = struct {
    start_pc: usize,
    exit_patches: std.ArrayList(usize),
};

pub const Error = error{ CompileError, OutOfMemory, TooManyConstants };

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    chunk: Chunk,
    arena: *ast.NodeArena,
    locals: Locals,
    reg_count: u8,
    loop_stack: std.ArrayList(LoopInfo),
    error_count: u32,
    diag: ?*err_mod.DiagnosticList = null,

    /// Initialize a new compiler with the given allocator and AST arena.
pub fn init(allocator: std.mem.Allocator, arena: *ast.NodeArena) Compiler {
        return .{
            .allocator = allocator,
            .chunk = Chunk.init(allocator),
            .arena = arena,
            .locals = Locals.init(allocator),
            .reg_count = 0,
            .loop_stack = std.ArrayList(LoopInfo).empty,
            .error_count = 0,
        };
    }

    /// Deinitialize the compiler, freeing all owned resources.
pub fn deinit(self: *Compiler) void {
        self.chunk.deinit();
        self.locals.deinit(self.allocator);
        for (self.loop_stack.items) |*lp| lp.exit_patches.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
    }

    fn compileError(self: *Compiler, code: []const u8, comptime fmt: []const u8, args: anytype) error{CompileError} {
        self.error_count += 1;
        const msg = std.fmt.allocPrint(self.allocator, fmt, args) catch "compile error";
        if (self.diag) |diag| {
            diag.add(self.allocator, .{
                .severity = .@"error",
                .code = code,
                .message = msg,
            }) catch {};
        } else {
            std.debug.print("[{s}] Compile Error: {s}\n", .{ code, msg });
        }
        return error.CompileError;
    }

    fn allocReg(self: *Compiler) u8 {
        while (true) {
            var conflict = false;
            for (self.locals.list.items) |l| {
                if (l.slot == self.reg_count) {
                    self.reg_count += 1;
                    conflict = true;
                    break;
                }
            }
            if (!conflict) break;
        }
        const reg = self.reg_count;
        self.reg_count += 1;
        return reg;
    }

    fn resetTemps(self: *Compiler) void {
        var max_slot: u8 = 0;
        for (self.locals.list.items) |l| {
            if (l.slot + 1 > max_slot) max_slot = l.slot + 1;
        }
        self.reg_count = max_slot;
    }

    fn addLocal(self: *Compiler, name: []const u8, mutable: bool) !u8 {
        const slot = self.allocReg();
        try self.locals.add(self.allocator, name, slot, mutable);
        return slot;
    }

    fn resolveLocal(self: *Compiler, name: []const u8) ?u8 {
        return self.locals.resolve(name);
    }

    /// Compile a list of AST statement indices into bytecode. Auto-calls main() if defined.
    pub fn compile(self: *Compiler, stmts: []const usize) Error!void {
        var has_main = false;
        for (stmts) |stmt_idx| {
            try self.compileDeclOrStmt(stmt_idx);
            for (self.locals.list.items) |l| {
                if (l.slot + 1 > self.reg_count) self.reg_count = l.slot + 1;
            }
            // Check if this statement defined a pub fun main
            const node = self.arena.get(stmt_idx);
            if (node == .fun_stmt and node.fun_stmt.public and std.mem.eql(u8, node.fun_stmt.name, "main")) {
                has_main = true;
            }
        }
        // Auto-call main() if defined
        if (has_main) {
            const cr = self.allocReg();
            const ci = try self.chunk.addConstant(.{ .string = "main" });
            try self.chunk.write(OpCode.encodeABx(.load_global, cr, ci), 1);
            const dr = self.allocReg();
            try self.chunk.write(OpCode.encodeABC(.call, dr, cr, 0), 1);
        }
        try self.chunk.write(OpCode.encodeAx(.halt, 0), 0);
    }

    fn compileDeclOrStmt(self: *Compiler, node_idx: usize) Error!void {
        const node = self.arena.get(node_idx);
        switch (node) {
            .let_stmt => try self.compileLet(node_idx),
            .fun_stmt => try self.compileFun(node_idx),
            .type_decl, .use_stmt => {},
            .if_stmt => try self.compileIf(node_idx),
            .loop_stmt => try self.compileLoop(node_idx),
            .for_stmt => try self.compileFor(node_idx),
            .continue_stmt => try self.compileContinue(),
            .esc_stmt => try self.compileEsc(),
            .ret_stmt => try self.compileRet(node_idx),
            .expr_stmt => _ = try self.compileExpr(node.expr_stmt),
            .block => {
                for (node.block) |s| {
                    try self.compileDeclOrStmt(s);
                }
            },
            else => return self.compileError("c001", "unsupported statement type", .{}),
        }
    }

    fn compileLet(self: *Compiler, node_idx: usize) Error!void {
        const ls = self.arena.get(node_idx).let_stmt;
        if (ls.value) |val_idx| {
            const val_reg = try self.compileExpr(val_idx);
            const slot = self.allocReg();
            if (val_reg != slot) {
                try self.chunk.write(OpCode.encodeABx(.move_op, slot, val_reg), 1);
            }
            try self.locals.add(self.allocator, ls.name, slot, ls.mutable);
            // Free the temp register used by compileExpr
            self.reg_count = val_reg;
        } else {
            const slot = self.allocReg();
            try self.chunk.write(OpCode.encodeAx(.load_nil, slot), 1);
            try self.locals.add(self.allocator, ls.name, slot, ls.mutable);
        }
    }

    fn compileFun(self: *Compiler, node_idx: usize) Error!void {
        const fs = self.arena.get(node_idx).fun_stmt;

        // Create a sub-compiler state for the function body
        var body_chunk = Chunk.init(self.allocator);
        var body_locals = Locals.init(self.allocator);
        defer body_locals.deinit(self.allocator);
        var body_loops = std.ArrayList(LoopInfo).empty;
        defer {
            for (body_loops.items) |*lp| lp.exit_patches.deinit(self.allocator);
            body_loops.deinit(self.allocator);
        }
        var body_regs: u8 = 0;

        // Params → locals
        for (fs.params) |p| {
            const s = body_regs;
            body_regs += 1;
            try body_locals.add(self.allocator, p.name, s, false);
        }

        // Compile function body
        const body = self.arena.get(fs.body);
        if (body == .block) {
            for (body.block) |s| {
                compileStmtToChunk(
                    self.allocator,
                    self.arena,
                    &body_chunk,
                    &body_locals,
                    &body_loops,
                    &body_regs,
                    s,
                ) catch |err| switch (err) {
                    error.CompileError => return self.compileError("c001", "compile error in function '{s}'", .{fs.name}),
                    else => return err,
                };
            }
        }

        // Implicit ret nil
        try body_chunk.write(OpCode.encodeAx(.load_nil, 0), 0);
        try body_chunk.write(OpCode.encodeAx(.ret, 0), 0);

        // Allocate FunObj — chunk ownership transfers
        const fun = try self.allocator.create(Object.FunObj);
        fun.name = fs.name;
        fun.chunk = body_chunk;
        fun.param_count = @intCast(fs.params.len);

        // Load fun_obj into register and store globally
        const ci = try self.chunk.addConstant(.{ .fun_obj = fun });
        const dst_reg = self.allocReg();
        try self.chunk.write(OpCode.encodeABx(.load_const, dst_reg, ci), 1);

        const name_ci = try self.chunk.addConstant(.{ .string = fs.name });
        try self.chunk.write(OpCode.encodeABx(.store_global, dst_reg, name_ci), 1);
        self.reg_count -= 1;
    }

    // ── Control flow ────────────────────────────────────────────────────────

    fn compileIf(self: *Compiler, node_idx: usize) Error!void {
        const ifs = self.arena.get(node_idx).if_stmt;
        const cond_reg = try self.compileExpr(ifs.cond);
        const jump_to_else_idx = self.chunk.len();
        try self.chunk.write(OpCode.encodeAsBx(.jump_if_false, cond_reg, 0), 1);
        try self.compileDeclOrStmt(ifs.then_branch);
        const jump_to_end_idx = self.chunk.len();
        try self.chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);

        var end_jumps = std.ArrayList(usize).empty;
        try end_jumps.append(self.allocator, jump_to_end_idx);

        const else_start = self.chunk.len();
        self.patchJump(jump_to_else_idx, else_start);

        for (ifs.elifs) |elif| {
            const ec_reg = try self.compileExpr(elif.cond);
            const jmp_idx = self.chunk.len();
            try self.chunk.write(OpCode.encodeAsBx(.jump_if_false, ec_reg, 0), 1);
            try self.compileDeclOrStmt(elif.body);
            const jmp_end = self.chunk.len();
            try self.chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);
            try end_jumps.append(self.allocator, jmp_end);
            self.patchJump(jmp_idx, self.chunk.len());
        }

        if (ifs.else_branch) |else_idx| {
            try self.compileDeclOrStmt(else_idx);
        }

        const after = self.chunk.len();
        for (end_jumps.items) |j| self.patchJump(j, after);
        end_jumps.deinit(self.allocator);
    }

    fn compileLoop(self: *Compiler, node_idx: usize) Error!void {
        const loop_start = self.chunk.len();
        const lp = LoopInfo{ .start_pc = loop_start, .exit_patches = std.ArrayList(usize).empty };
        const lp_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, lp);

        try self.compileDeclOrStmt(self.arena.get(node_idx).loop_stmt);

        const back: i16 = @intCast(@as(i32, @intCast(loop_start)) - @as(i32, @intCast(self.chunk.len())));
        try self.chunk.write(OpCode.encodeAsBx(.jump, 0, back), 1);

        const exit_pc = self.chunk.len();
        for (self.loop_stack.items[lp_idx].exit_patches.items) |p| self.patchJump(p, exit_pc);
        self.loop_stack.items[lp_idx].exit_patches.deinit(self.allocator);
        _ = self.loop_stack.pop();
    }

    fn compileFor(self: *Compiler, node_idx: usize) Error!void {
        const fs = self.arena.get(node_idx).for_stmt;
        const iter_reg = try self.compileExpr(fs.iterable);
        const var_slot = try self.addLocal(fs.var_name, false);
        const idx_reg = self.allocReg();
        try self.chunk.write(OpCode.encodeABx(.load_const, idx_reg, try self.chunk.addConstant(.{ .int = 0 })), 1);

        const loop_start = self.chunk.len();
        const len_reg = self.allocReg();
        try self.chunk.write(OpCode.encodeABC(.index_len, len_reg, iter_reg, 0), 1);
        const cmp_reg = self.allocReg();
        try self.chunk.write(OpCode.encodeABC(.lt, cmp_reg, idx_reg, len_reg), 1);
        const exit_jump = self.chunk.len();
        try self.chunk.write(OpCode.encodeAsBx(.jump_if_false, cmp_reg, 0), 1);

        // Reserve registers: push reg_count past all for-loop registers
        const for_loop_top = @max(iter_reg, @max(idx_reg, @max(len_reg, @max(cmp_reg, var_slot)))) + 1;
        if (self.reg_count < for_loop_top) self.reg_count = for_loop_top;

        try self.chunk.write(OpCode.encodeABC(.index_get, var_slot, iter_reg, idx_reg), 1);

        const lp = LoopInfo{ .start_pc = loop_start, .exit_patches = std.ArrayList(usize).empty };
        const lp_idx = self.loop_stack.items.len;
        try self.loop_stack.append(self.allocator, lp);

        const body_save = self.reg_count;
        try self.compileDeclOrStmt(fs.body);
        self.reg_count = body_save;

        const one_const = try self.chunk.addConstant(.{ .int = 1 });
        const one_reg = self.allocReg();
        try self.chunk.write(OpCode.encodeABx(.load_const, one_reg, one_const), 1);
        try self.chunk.write(OpCode.encodeABC(.add, idx_reg, idx_reg, one_reg), 1);

        const back: i16 = @intCast(@as(i32, @intCast(loop_start)) - @as(i32, @intCast(self.chunk.len())));
        try self.chunk.write(OpCode.encodeAsBx(.jump, 0, back), 1);

        const exit_pc = self.chunk.len();
        self.patchJump(exit_jump, exit_pc);
        for (self.loop_stack.items[lp_idx].exit_patches.items) |p| self.patchJump(p, exit_pc);
        self.loop_stack.items[lp_idx].exit_patches.deinit(self.allocator);
        _ = self.loop_stack.pop();
    }

    fn compileContinue(self: *Compiler) Error!void {
        if (self.loop_stack.items.len == 0) return self.compileError("c002", "continue outside loop", .{});
        const lp = &self.loop_stack.items[self.loop_stack.items.len - 1];
        const off: i16 = @intCast(@as(i32, @intCast(lp.start_pc)) - @as(i32, @intCast(self.chunk.len())));
        try self.chunk.write(OpCode.encodeAsBx(.jump, 0, off), 1);
    }

    fn compileEsc(self: *Compiler) Error!void {
        if (self.loop_stack.items.len == 0) return self.compileError("c003", "esc outside loop", .{});
        const lp = &self.loop_stack.items[self.loop_stack.items.len - 1];
        const patch_idx = self.chunk.len();
        try self.chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);
        try lp.exit_patches.append(self.allocator, patch_idx);
    }

    fn compileRet(self: *Compiler, node_idx: usize) Error!void {
        const rs = self.arena.get(node_idx).ret_stmt;
        var ret_reg: u8 = 0;
        if (rs) |val_idx| ret_reg = try self.compileExpr(val_idx);
        try self.chunk.write(OpCode.encodeAx(.ret, ret_reg), 0);
    }

    // ── Expressions ─────────────────────────────────────────────────────────

    fn compileExpr(self: *Compiler, node_idx: usize) Error!u8 {
        const node = self.arena.get(node_idx);
        return switch (node) {
            .int_lit => |v| self.compileImm(.{ .int = v }),
            .float_lit => |v| self.compileImm(.{ .float = v }),
            .bool_lit => |v| blk: {
                const r = self.allocReg();
                try self.chunk.write(OpCode.encodeAx(if (v) .load_true else .load_false, r), 1);
                break :blk r;
            },
            .nil_lit => blk: {
                const r = self.allocReg();
                try self.chunk.write(OpCode.encodeAx(.load_nil, r), 1);
                break :blk r;
            },
            .str_lit => |v| self.compileImm(.{ .string = v }),
            .ident => |name| {
                if (self.resolveLocal(name)) |slot| {
                    const r = self.allocReg();
                    try self.chunk.write(OpCode.encodeABx(.load_local, r, slot), 1);
                    return r;
                }
                const r = self.allocReg();
                const ci = try self.chunk.addConstant(.{ .string = name });
                try self.chunk.write(OpCode.encodeABx(.load_global, r, ci), 1);
                return r;
            },
            .binary => |b| {
                const lr = try self.compileExpr(b.left);
                const rr = try self.compileExpr(b.right);
                const op: OpCode.OpCode = switch (b.op) {
                    .add => .add, .sub => .sub, .mul => .mul, .div => .div_op,
                    .mod => .mod_op, .eq => .eq, .neq => .neq,
                    .gt => .gt, .lt => .lt, .gte => .gte, .lte => .lte,
                    .and_ => .and_, .or_ => .or_,
                };
                try self.chunk.write(OpCode.encodeABC(op, lr, lr, rr), 1);
                self.reg_count -= 1;
                return lr;
            },
            .unary => |u| {
                const or_ = try self.compileExpr(u.operand);
                const op: OpCode.OpCode = switch (u.op) { .neg => .neg, .not => .not_ };
                try self.chunk.write(OpCode.encodeAx(op, or_), 1);
                return or_;
            },
            .call => |c| {
                const callee_name = resolveCalleeName(self.arena, c.callee) catch |err| switch (err) {
                    error.CompileError => return self.compileError("c001", "cannot resolve callee name", .{}),
                    else => return err,
                };
                const cr = self.allocReg();
                const ci = try self.chunk.addConstant(.{ .string = callee_name });
                try self.chunk.write(OpCode.encodeABx(.load_global, cr, ci), 1);
                for (c.args, 0..) |a, i| {
                    const arg_reg = try self.compileExpr(a);
                    const expected = cr + 1 + @as(u8, @intCast(i));
                    if (arg_reg != expected) {
                        try self.chunk.write(OpCode.encodeABx(.move_op, expected, arg_reg), 1);
                        self.reg_count = arg_reg;
                    }
                }
                const dr = self.allocReg();
                try self.chunk.write(OpCode.encodeABC(.call, dr, cr, @intCast(c.args.len)), 1);
                self.reg_count = dr + 1;
                return dr;
            },
            .assign => |a| {
                const vr = try self.compileExpr(a.value);
                const target = self.arena.get(a.target);
                if (target == .ident) {
                    if (self.resolveLocal(target.ident)) |slot| {
                        try self.chunk.write(OpCode.encodeABx(.store_local, vr, slot), 1);
                    } else {
                        const ci = try self.chunk.addConstant(.{ .string = target.ident });
                        try self.chunk.write(OpCode.encodeABx(.store_global, vr, ci), 1);
                    }
                }
                return vr;
            },
            .vec_lit => |items| {
                const vr = self.allocReg();
                try self.chunk.write(OpCode.encodeABx(.new_vec, vr, @intCast(items.len)), 1);
                for (items, 0..) |it, i| {
                    const ir = try self.compileExpr(it);
                    try self.chunk.write(OpCode.encodeABC(.vec_set, vr, @intCast(i), ir), 1);
                    self.reg_count -= 1;
                }
                return vr;
            },
            .field => |f| {
                const obj_reg = try self.compileExpr(f.object);
                const nci = try self.chunk.addConstant(.{ .string = f.field_name });
                try self.chunk.write(OpCode.encodeABC(.get_field, obj_reg, obj_reg, @intCast(nci)), 1);
                return obj_reg;
            },
            .try_expr => |inner| {
                const r = try self.compileExpr(inner);
                try self.chunk.write(OpCode.encodeAx(.try_prop, r), 1);
                return r;
            },
            .index => |idx| {
                const obj_reg = try self.compileExpr(idx.object);
                const idx_reg = try self.compileExpr(idx.idx);
                const r = self.allocReg();
                try self.chunk.write(OpCode.encodeABC(.index_get, r, obj_reg, idx_reg), 1);
                return r;
            },
            .struct_lit => |sl| {
                const sr = self.allocReg();
                try self.chunk.write(OpCode.encodeAx(.new_struct, sr), 1);
                for (sl.fields) |f| {
                    const val_reg = try self.compileExpr(f.value);
                    // struct_set sr name_idx  (value expected at sr+1)
                    if (val_reg != sr + 1) {
                        try self.chunk.write(OpCode.encodeABx(.move_op, sr + 1, val_reg), 1);
                        self.reg_count = val_reg;
                    }
                    const nci = try self.chunk.addConstant(.{ .string = f.name });
                    try self.chunk.write(OpCode.encodeABx(.struct_set, sr, nci), 1);
                }
                self.reg_count = sr + 1;
                return sr;
            },
            else => return self.compileError("c001", "unsupported expression type", .{}),
        };
    }

    fn compileImm(self: *Compiler, val: Value.Value) Error!u8 {
        const r = self.allocReg();
        const ci = try self.chunk.addConstant(val);
        try self.chunk.write(OpCode.encodeABx(.load_const, r, ci), 1);
        return r;
    }

    fn patchJump(self: *Compiler, patch_idx: usize, target_pc: usize) void {
        const off: i16 = @intCast(@as(i32, @intCast(target_pc)) - @as(i32, @intCast(patch_idx)));
        const inst = self.chunk.code.items[patch_idx];
        const op = OpCode.decodeOp(inst);
        const a = OpCode.decodeAsBx(inst).a;
        self.chunk.code.items[patch_idx] = OpCode.encodeAsBx(op, a, off);
    }
};

// ── Helper: compile statement into a specific chunk ────────────────────────

fn compileStmtToChunk(
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    chunk: *Chunk,
    locals: *Locals,
    loops: *std.ArrayList(LoopInfo),
    reg_count: *u8,
    node_idx: usize,
) Error!void {
    const node = arena.get(node_idx);
    switch (node) {
        .let_stmt => {
            const ls = node.let_stmt;
            if (ls.value) |vi| {
                const val_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, vi);
                const slot = reg_count.*;
                reg_count.* += 1;
                if (val_reg != slot) {
                    try chunk.write(OpCode.encodeABx(.move_op, slot, val_reg), 1);
                }
                try locals.add(allocator, ls.name, slot, ls.mutable);
            } else {
                const slot = reg_count.*;
                reg_count.* += 1;
                try chunk.write(OpCode.encodeAx(.load_nil, slot), 1);
                try locals.add(allocator, ls.name, slot, ls.mutable);
            }
        },
        .expr_stmt => _ = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, node.expr_stmt),
        .ret_stmt => {
            var ret_reg: u8 = 0;
            if (node.ret_stmt) |vi| ret_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, vi);
            try chunk.write(OpCode.encodeAx(.ret, ret_reg), 0);
        },
        .block => {
            for (node.block) |s| {
                try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, s);
            }
        },
        .if_stmt => try compileIfToChunk(allocator, arena, chunk, locals, loops, reg_count, node_idx),
        .loop_stmt => try compileLoopToChunk(allocator, arena, chunk, locals, loops, reg_count, node_idx),
        .for_stmt => try compileForToChunk(allocator, arena, chunk, locals, loops, reg_count, node_idx),
        .continue_stmt => {
            if (loops.items.len == 0) return error.CompileError;
            const lp = &loops.items[loops.items.len - 1];
            const off: i16 = @intCast(@as(i32, @intCast(lp.start_pc)) - @as(i32, @intCast(chunk.len())));
            try chunk.write(OpCode.encodeAsBx(.jump, 0, off), 1);
        },
        .esc_stmt => {
            if (loops.items.len == 0) return error.CompileError;
            const lp = &loops.items[loops.items.len - 1];
            const pi = chunk.len();
            try chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);
            try lp.exit_patches.append(allocator, pi);
        },
        else => {},
    }
}

fn resolveCalleeName(arena: *ast.NodeArena, callee_idx: usize) ![]const u8 {
    const node = arena.get(callee_idx);
    return switch (node) {
        .ident => |name| name,
        .field => |f| {
            const obj_name = try resolveCalleeName(arena, f.object);
            const full = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.{s}", .{ obj_name, f.field_name });
            return full;
        },
        else => error.CompileError,
    };
}

fn patchJumpInChunk(chunk: *Chunk, patch_idx: usize, target_pc: usize) void {
    const off: i16 = @intCast(@as(i32, @intCast(target_pc)) - @as(i32, @intCast(patch_idx)));
    const inst = chunk.code.items[patch_idx];
    const op = OpCode.decodeOp(inst);
    const a = OpCode.decodeAsBx(inst).a;
    chunk.code.items[patch_idx] = OpCode.encodeAsBx(op, a, off);
}

fn compileExprToChunk(
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    chunk: *Chunk,
    locals: *Locals,
    reg_count: *u8,
    node_idx: usize,
) Error!u8 {
    const node = arena.get(node_idx);
    return switch (node) {
        .int_lit => |v| {
            const r = reg_count.*;
            reg_count.* += 1;
            const ci = try chunk.addConstant(.{ .int = v });
            try chunk.write(OpCode.encodeABx(.load_const, r, ci), 1);
            return r;
        },
        .float_lit => |v| {
            const r = reg_count.*;
            reg_count.* += 1;
            const ci = try chunk.addConstant(.{ .float = v });
            try chunk.write(OpCode.encodeABx(.load_const, r, ci), 1);
            return r;
        },
        .bool_lit => |v| {
            const r = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeAx(if (v) .load_true else .load_false, r), 1);
            return r;
        },
        .nil_lit => {
            const r = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeAx(.load_nil, r), 1);
            return r;
        },
        .str_lit => |v| {
            const r = reg_count.*;
            reg_count.* += 1;
            const ci = try chunk.addConstant(.{ .string = v });
            try chunk.write(OpCode.encodeABx(.load_const, r, ci), 1);
            return r;
        },
        .ident => |name| {
            if (locals.resolve(name)) |slot| {
                const r = reg_count.*;
                reg_count.* += 1;
                try chunk.write(OpCode.encodeABx(.load_local, r, slot), 1);
                return r;
            }
            // Global fallback
            const r = reg_count.*;
            reg_count.* += 1;
            const ci = try chunk.addConstant(.{ .string = name });
            try chunk.write(OpCode.encodeABx(.load_global, r, ci), 1);
            return r;
        },
        .field => |f| {
            const obj_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, f.object);
            const nci = try chunk.addConstant(.{ .string = f.field_name });
            try chunk.write(OpCode.encodeABC(.get_field, obj_reg, obj_reg, @intCast(nci)), 1);
            return obj_reg;
        },
        .binary => |b| {
            const lr = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, b.left);
            const rr = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, b.right);
            const op: OpCode.OpCode = switch (b.op) {
                .add => .add, .sub => .sub, .mul => .mul, .div => .div_op,
                .mod => .mod_op, .eq => .eq, .neq => .neq,
                .gt => .gt, .lt => .lt, .gte => .gte, .lte => .lte,
                .and_ => .and_, .or_ => .or_,
            };
            try chunk.write(OpCode.encodeABC(op, lr, lr, rr), 1);
            reg_count.* -= 1;
            return lr;
        },
        .unary => |u| {
            const or_ = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, u.operand);
            const op: OpCode.OpCode = switch (u.op) { .neg => .neg, .not => .not_ };
            try chunk.write(OpCode.encodeAx(op, or_), 1);
            return or_;
        },
        .call => |c| {
            const callee_name = try resolveCalleeName(arena, c.callee);
            const cr = reg_count.*;
            reg_count.* += 1;
            const ci = try chunk.addConstant(.{ .string = callee_name });
            try chunk.write(OpCode.encodeABx(.load_global, cr, ci), 1);
            for (c.args, 0..) |a, i| {
                const arg_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, a);
                const expected = cr + 1 + @as(u8, @intCast(i));
                if (arg_reg != expected) {
                    try chunk.write(OpCode.encodeABx(.move_op, expected, arg_reg), 1);
                    reg_count.* = arg_reg;
                }
            }
            const dr = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeABC(.call, dr, cr, @intCast(c.args.len)), 1);
            reg_count.* = dr + 1;
            return dr;
        },
        .assign => |a| {
            const vr = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, a.value);
            const target = arena.get(a.target);
            if (target == .ident) {
                if (locals.resolve(target.ident)) |slot| {
                    try chunk.write(OpCode.encodeABx(.store_local, vr, slot), 1);
                    return vr;
                }
                const ci = try chunk.addConstant(.{ .string = target.ident });
                try chunk.write(OpCode.encodeABx(.store_global, vr, ci), 1);
            }
            return vr;
        },
        .vec_lit => |items| {
            const vr = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeABx(.new_vec, vr, @intCast(items.len)), 1);
            for (items, 0..) |it, i| {
                const ir = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, it);
                try chunk.write(OpCode.encodeABC(.vec_set, vr, @intCast(i), ir), 1);
                reg_count.* -= 1;
            }
            return vr;
        },
        .struct_lit => |sl| {
            const sr = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeAx(.new_struct, sr), 1);
            for (sl.fields) |f| {
                const val_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, f.value);
                if (val_reg != sr + 1) {
                    try chunk.write(OpCode.encodeABx(.move_op, sr + 1, val_reg), 1);
                    reg_count.* = val_reg;
                }
                const nci = try chunk.addConstant(.{ .string = f.name });
                try chunk.write(OpCode.encodeABx(.struct_set, sr, nci), 1);
            }
            reg_count.* = sr + 1;
            return sr;
        },
        .index => |idx| {
            const obj_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, idx.object);
            const idx_reg = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, idx.idx);
            const r = reg_count.*;
            reg_count.* += 1;
            try chunk.write(OpCode.encodeABC(.index_get, r, obj_reg, idx_reg), 1);
            return r;
        },
        .try_expr => |inner| {
            const r = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, inner);
            try chunk.write(OpCode.encodeAx(.try_prop, r), 1);
            return r;
        },
        else => { return 0; },
    };
}

fn compileForToChunk(
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    chunk: *Chunk,
    locals: *Locals,
    loops: *std.ArrayList(LoopInfo),
    reg_count: *u8,
    node_idx: usize,
) Error!void {
    const fs = arena.get(node_idx).for_stmt;
    const iter_reg = reg_count.*;
    reg_count.* += 1;
    // Compile iterable and store in iter_reg
    const iter_tmp = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, fs.iterable);
    try chunk.write(OpCode.encodeABx(.move_op, iter_reg, iter_tmp), 1);
    reg_count.* -= 1;

    const var_slot = reg_count.*;
    reg_count.* += 1;
    // We'll store the loop variable here later, but first set up index
    const idx_reg = reg_count.*;
    reg_count.* += 1;
    try chunk.write(OpCode.encodeABx(.load_const, idx_reg, try chunk.addConstant(.{ .int = 0 })), 1);

    const loop_start = chunk.len();
    const len_reg = reg_count.*;
    reg_count.* += 1;
    try chunk.write(OpCode.encodeABC(.index_len, len_reg, iter_reg, 0), 1);
    const cmp_reg = reg_count.*;
    reg_count.* += 1;
    try chunk.write(OpCode.encodeABC(.lt, cmp_reg, idx_reg, len_reg), 1);
    const exit_jump = chunk.len();
    try chunk.write(OpCode.encodeAsBx(.jump_if_false, cmp_reg, 0), 1);

    try chunk.write(OpCode.encodeABC(.index_get, var_slot, iter_reg, idx_reg), 1);
    // Add loop variable as a local
    try locals.add(allocator, fs.var_name, var_slot, false);

    const lp = LoopInfo{ .start_pc = loop_start, .exit_patches = std.ArrayList(usize).empty };
    const lp_idx = loops.items.len;
    try loops.append(allocator, lp);

    const body_save = reg_count.*;
    try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, fs.body);
    reg_count.* = body_save;

    const one_const = try chunk.addConstant(.{ .int = 1 });
    const one_reg = reg_count.*;
    reg_count.* += 1;
    try chunk.write(OpCode.encodeABx(.load_const, one_reg, one_const), 1);
    try chunk.write(OpCode.encodeABC(.add, idx_reg, idx_reg, one_reg), 1);

    const back: i16 = @intCast(@as(i32, @intCast(loop_start)) - @as(i32, @intCast(chunk.len())));
    try chunk.write(OpCode.encodeAsBx(.jump, 0, back), 1);

    const exit_pc = chunk.len();
    patchJumpInChunk(chunk, exit_jump, exit_pc);
    for (loops.items[lp_idx].exit_patches.items) |p| patchJumpInChunk(chunk, p, exit_pc);
    loops.items[lp_idx].exit_patches.deinit(allocator);
    _ = loops.pop();
}

fn compileIfToChunk(
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    chunk: *Chunk,
    locals: *Locals,
    loops: *std.ArrayList(LoopInfo),
    reg_count: *u8,
    node_idx: usize,
) Error!void {
    const ifs = arena.get(node_idx).if_stmt;
    const cr = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, ifs.cond);
    const jmp_else = chunk.len();
    try chunk.write(OpCode.encodeAsBx(.jump_if_false, cr, 0), 1);
    try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, ifs.then_branch);
    const jmp_end = chunk.len();
    try chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);

    var end_jumps = std.ArrayList(usize).empty;
    try end_jumps.append(allocator, jmp_end);
    patchJumpInChunk(chunk, jmp_else, chunk.len());

    for (ifs.elifs) |elif| {
        const ec = try compileExprToChunk(allocator, arena, chunk, locals, reg_count, elif.cond);
        const ji = chunk.len();
        try chunk.write(OpCode.encodeAsBx(.jump_if_false, ec, 0), 1);
        try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, elif.body);
        const je = chunk.len();
        try chunk.write(OpCode.encodeAsBx(.jump, 0, 0), 1);
        try end_jumps.append(allocator, je);
        patchJumpInChunk(chunk, ji, chunk.len());
    }
    if (ifs.else_branch) |ei| {
        try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, ei);
    }
    const after = chunk.len();
    for (end_jumps.items) |j| patchJumpInChunk(chunk, j, after);
    end_jumps.deinit(allocator);
}

fn compileLoopToChunk(
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    chunk: *Chunk,
    locals: *Locals,
    loops: *std.ArrayList(LoopInfo),
    reg_count: *u8,
    node_idx: usize,
) Error!void {
    const loop_start_pc = chunk.len();
    const lp = LoopInfo{ .start_pc = loop_start_pc, .exit_patches = std.ArrayList(usize).empty };
    const lp_idx = loops.items.len;
    try loops.append(allocator, lp);

    try compileStmtToChunk(allocator, arena, chunk, locals, loops, reg_count, arena.get(node_idx).loop_stmt);

    const back: i16 = @intCast(@as(i32, @intCast(loop_start_pc)) - @as(i32, @intCast(chunk.len())));
    try chunk.write(OpCode.encodeAsBx(.jump, 0, back), 1);

    const exit_pc = chunk.len();
    for (loops.items[lp_idx].exit_patches.items) |p| patchJumpInChunk(chunk, p, exit_pc);
    loops.items[lp_idx].exit_patches.deinit(allocator);
    _ = loops.pop();
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "compiler: integer literal" {
    var arena = ast.NodeArena.init(std.testing.allocator);
    defer arena.deinit();
    const lit_idx = try arena.add(.{ .int_lit = 42 });
    const stmt_idx = try arena.add(.{ .expr_stmt = lit_idx });
    var c = Compiler.init(std.testing.allocator, &arena);
    defer c.deinit();
    try c.compile(&[_]usize{stmt_idx});
    try std.testing.expect(c.chunk.len() >= 2);
}

test "compiler: simple arithmetic" {
    var arena = ast.NodeArena.init(std.testing.allocator);
    defer arena.deinit();
    const left = try arena.add(.{ .int_lit = 2 });
    const right = try arena.add(.{ .int_lit = 3 });
    const bin = try arena.add(.{ .binary = .{ .op = .add, .left = left, .right = right } });
    const stmt = try arena.add(.{ .expr_stmt = bin });
    var c = Compiler.init(std.testing.allocator, &arena);
    defer c.deinit();
    try c.compile(&[_]usize{stmt});
    try std.testing.expect(c.chunk.len() >= 4);
}
