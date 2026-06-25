const std = @import("std");
const ast = @import("ast.zig");
const Type = @import("type.zig");
const err = @import("error.zig");

const Symbol = struct {
    name: []const u8,
    typ: *const Type.Type,
    mutable: bool,
};

pub const TypeEnv = struct {
    parent: ?*const TypeEnv,
    symbols: std.StringHashMap(Symbol),
    return_type: ?*const Type.Type,
    in_loop: bool,

        /// Create a new root type environment with no parent scope.
    pub fn init(allocator: std.mem.Allocator) TypeEnv {
        return .{
            .parent = null,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .return_type = null,
            .in_loop = false,
        };
    }

    /// Create a child scope that inherits the parent's return type and loop context.
    pub fn child(self: *const TypeEnv, allocator: std.mem.Allocator) TypeEnv {
        return .{
            .parent = self,
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .return_type = self.return_type,
            .in_loop = self.in_loop,
        };
    }

    /// Deinitialize the type environment, freeing the symbols hash map.
    pub fn deinit(self: *TypeEnv) void {
        self.symbols.deinit();
    }

    /// Define a new symbol in the current scope with the given type and mutability.
    pub fn define(self: *TypeEnv, name: []const u8, typ: *const Type.Type, mutable: bool) !void {
        try self.symbols.put(name, .{ .name = name, .typ = typ, .mutable = mutable });
    }

    /// Look up a symbol by name, searching up through parent scopes. Returns null if not found.
    pub fn lookup(self: *const TypeEnv, name: []const u8) ?Symbol {
        if (self.symbols.get(name)) |s| return s;
        if (self.parent) |p| return p.lookup(name);
        return null;
    }
};

pub const Checker = struct {
    allocator: std.mem.Allocator,
    arena: *ast.NodeArena,
    type_arena: std.heap.ArenaAllocator,
    root_env: TypeEnv,
    error_count: u32,
    type_defs: std.StringHashMap(*const Type.Type),
    diag: ?*err.DiagnosticList = null,

    const Ctx = struct {
        checker: *Checker,
        env: *TypeEnv,
    };

    /// Initialize a new type checker with the given allocator and AST arena.
    pub fn init(allocator: std.mem.Allocator, arena: *ast.NodeArena) Checker {
        return .{
            .allocator = allocator,
            .arena = arena,
            .type_arena = std.heap.ArenaAllocator.init(allocator),
            .root_env = TypeEnv.init(allocator),
            .error_count = 0,
            .type_defs = std.StringHashMap(*const Type.Type).init(allocator),
        };
    }

    /// Deinitialize the type checker, freeing all owned resources.
    pub fn deinit(self: *Checker) void {
        self.root_env.deinit();
        self.type_arena.deinit();
        self.type_defs.deinit();
    }

    fn typeError(self: *Checker, comptime code: []const u8, msg: []const u8) void {
        self.error_count += 1;
        if (self.diag) |diag| {
            diag.add(self.allocator, .{
                .severity = .@"error",
                .code = code,
                .message = msg,
            }) catch {};
        } else {
            err.printDiagnostic(code, "Type Error", msg, null);
        }
    }

    fn allocType(self: *Checker, t: Type.Type) *const Type.Type {
        const ptr = self.type_arena.allocator().create(Type.Type) catch @panic("OOM");
        ptr.* = t;
        return ptr;
    }

    fn resolveTypeExpr(self: *Checker, node_idx: usize) !*const Type.Type {
        const node = self.arena.get(node_idx);
        switch (node) {
            .ident => {
                if (Type.parseTypeName(node.ident)) |p| {
                    return self.allocType(.{ .primitive = p });
                }
                if (self.type_defs.get(node.ident)) |t| return t;
                self.typeError("t001", "Unknown type");
                return self.allocType(.{ .primitive = .i32 });
            },
            .type_ident => |name| {
                if (Type.parseTypeName(name)) |p| {
                    return self.allocType(.{ .primitive = p });
                }
                if (self.type_defs.get(name)) |t| return t;
                self.typeError("t001", "Unknown type");
                return self.allocType(.{ .primitive = .i32 });
            },
            .type_vec => |inner| {
                const elem_t = try self.resolveTypeExpr(inner);
                return self.allocType(.{ .vec = @constCast(elem_t) });
            },
            .type_map => |m| {
                const kt = try self.resolveTypeExpr(m.key);
                const vt = try self.resolveTypeExpr(m.val);
                return self.allocType(.{ .map = .{ .key = @constCast(kt), .val = @constCast(vt) } });
            },
            .type_opt => |inner| {
                const t = try self.resolveTypeExpr(inner);
                return self.allocType(.{ .opt = @constCast(t) });
            },
            .type_res => |r| {
                const ok_t = try self.resolveTypeExpr(r.ok);
                const err_t = try self.resolveTypeExpr(r.err);
                return self.allocType(.{ .res = .{ .ok = @constCast(ok_t), .err = @constCast(err_t) } });
            },
            else => {
                self.typeError("t001", "Invalid type expression");
                return self.allocType(.{ .primitive = .i32 });
            },
        }
    }

    /// Run two-pass type checking: collect type declarations first, then check all statements.
    pub fn check(self: *Checker, stmts: []const usize) (error{OutOfMemory})!void {
        // Pass 1: collect type declarations and register native functions
        for (stmts) |stmt_idx| {
            const node = self.arena.get(stmt_idx);
            if (node == .type_decl) {
                try self.checkTypeDecl(stmt_idx);
            } else if (node == .use_stmt) {
                try self.registerNativeFunctions(node.use_stmt.path);
            }
        }

        // Pass 2: check all statements
        for (stmts) |stmt_idx| {
            try self.checkStmtInEnv(&self.root_env, stmt_idx);
        }
    }

    fn registerNativeFunctions(self: *Checker, module: []const u8) !void {
        // Register native function types for known modules
        if (std.mem.eql(u8, module, "std")) {
            try self.root_env.define("std.println", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("std.print", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("std.readln", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.{ .primitive = .str })) } }), false);
            try self.root_env.define("std.read", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.{ .primitive = .str })) } }), false);
            try self.root_env.define("std.readChar", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.{ .primitive = .char })) } }), false);
            try self.root_env.define("std.range", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .i32 }, .{ .primitive = .i32 }}, .ret = @constCast(self.allocType(.{ .vec = @constCast(self.allocType(.{ .primitive = .i32 })) })) } }), false);
        } else if (std.mem.eql(u8, module, "fs")) {
            try self.root_env.define("fs.read", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.{ .primitive = .str })) } }), false);
            try self.root_env.define("fs.write", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }, .{ .primitive = .str }}, .ret = @constCast(self.allocType(.{ .primitive = .bool })) } }), false);
            try self.root_env.define("fs.exists", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.{ .primitive = .bool })) } }), false);
            try self.root_env.define("fs.delete", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.{ .primitive = .bool })) } }), false);
        } else if (std.mem.eql(u8, module, "str")) {
            try self.root_env.define("str.len", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.{ .primitive = .i32 })) } }), false);
            try self.root_env.define("str.slice", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }, .{ .primitive = .i32 }, .{ .primitive = .i32 }}, .ret = @constCast(self.allocType(.{ .primitive = .str })) } }), false);
        } else if (std.mem.eql(u8, module, "thread")) {
            try self.root_env.define("thread.spawn", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .str }}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("thread.join", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("thread.channel", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("thread.send", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.void_type)) } }), false);
            try self.root_env.define("thread.recv", self.allocType(.{ .func = .{ .params = &.{}, .ret = @constCast(self.allocType(.void_type)) } }), false);
        } else if (std.mem.eql(u8, module, "range")) {
            try self.root_env.define("range.range", self.allocType(.{ .func = .{ .params = &.{.{ .primitive = .i32 }, .{ .primitive = .i32 }}, .ret = @constCast(self.allocType(.{ .vec = @constCast(self.allocType(.{ .primitive = .i32 })) })) } }), false);
        }
    }

    fn checkTypeDecl(self: *Checker, node_idx: usize) !void {
        const td = self.arena.get(node_idx).type_decl;
        const t = self.allocType(.{ .named = td.name });
        try self.type_defs.put(td.name, t);
    }

    fn checkStmtInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const node = self.arena.get(node_idx);
        switch (node) {
            .let_stmt => try self.checkLetInEnv(env, node_idx),
            .fun_stmt => try self.checkFunInEnv(env, node_idx),
            .expr_stmt => _ = try self.checkExprInEnv(env, node.expr_stmt),
            .if_stmt => try self.checkIfInEnv(env, node_idx),
            .loop_stmt => try self.checkLoopInEnv(env, node_idx),
            .for_stmt => try self.checkForInEnv(env, node_idx),
            .ret_stmt => try self.checkRetInEnv(env, node_idx),
            .continue_stmt, .esc_stmt => {
                if (!env.in_loop) self.typeError("t001", "continue/esc outside of loop");
            },
            .block => {
                var child_env = env.child(self.allocator);
                defer child_env.deinit();
                for (node.block) |s| try self.checkStmtInEnv(&child_env, s);
            },
            .type_decl, .use_stmt => {},
            else => {},
        }
    }

    fn checkLetInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const ls = self.arena.get(node_idx).let_stmt;

        var declared_type: ?*const Type.Type = null;
        if (ls.type_annot) |ta| {
            declared_type = try self.resolveTypeExpr(ta);
        }

        var final_type = declared_type orelse self.allocType(.{ .primitive = .i32 });
        if (ls.value) |val_idx| {
            const val_type = try self.checkExprInEnv(env, val_idx);
            if (declared_type) |dt| {
                // Check if value type is compatible with declared type
                if (!isCompatible(val_type, dt)) {
                    self.typeError("t004", "Type mismatch in variable declaration");
                }
                // Use declared type as final type
                final_type = dt;
            } else {
                // No declared type, infer from value
                final_type = val_type;
            }
        }
        try env.define(ls.name, final_type, ls.mutable);
    }

    fn checkFunInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const fs = self.arena.get(node_idx).fun_stmt;

        var param_types = std.ArrayList(Type.Type).empty;
        defer param_types.deinit(self.allocator);

        for (fs.params) |p| {
            const t = if (p.type_annot) |ta|
                try self.resolveTypeExpr(ta)
            else
                self.allocType(.{ .primitive = .i32 });
            try param_types.append(self.allocator, t.*);
        }

        const ret_type = if (fs.ret_type) |rt|
            try self.resolveTypeExpr(rt)
        else
            self.allocType(.void_type);

        const func_type = self.allocType(.{ .func = .{
            .params = try param_types.toOwnedSlice(self.allocator),
            .ret = @constCast(ret_type),
        } });

        try env.define(fs.name, func_type, false);

        var child_env = env.child(self.allocator);
        defer child_env.deinit();
        child_env.return_type = ret_type;

        for (fs.params) |p| {
            const pt = if (p.type_annot) |ta|
                try self.resolveTypeExpr(ta)
            else
                self.allocType(.{ .primitive = .i32 });
            try child_env.define(p.name, pt, false);
        }

        const body = self.arena.get(fs.body);
        if (body == .block) {
            for (body.block) |s| try self.checkStmtInEnv(&child_env, s);
        }
    }

    fn checkRetInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const rs = self.arena.get(node_idx).ret_stmt;
        if (env.return_type == null) {
            self.typeError("t009", "ret outside of function");
            return;
        }
        if (rs) |val_idx| {
            const val_type = try self.checkExprInEnv(env, val_idx);
            if (!isCompatible(val_type, env.return_type.?)) {
                self.typeError("t005", "Return type mismatch");
            }
        }
    }

    fn checkIfInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const ifs = self.arena.get(node_idx).if_stmt;

        // Allow any value as if condition (truthy/falsy coercion at runtime)
        _ = try self.checkExprInEnv(env, ifs.cond);

        try self.checkStmtInEnv(env, ifs.then_branch);
        for (ifs.elifs) |elif| {
            // Allow any value as elif condition
            _ = try self.checkExprInEnv(env, elif.cond);
            try self.checkStmtInEnv(env, elif.body);
        }
        if (ifs.else_branch) |else_idx| {
            try self.checkStmtInEnv(env, else_idx);
        }
    }

    fn checkLoopInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        var child_env = env.child(self.allocator);
        defer child_env.deinit();
        child_env.in_loop = true;
        try self.checkStmtInEnv(&child_env, self.arena.get(node_idx).loop_stmt);
    }

    fn checkForInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!void {
        const fs = self.arena.get(node_idx).for_stmt;
        const iter_type = try self.checkExprInEnv(env, fs.iterable);

        var child_env = env.child(self.allocator);
        defer child_env.deinit();
        child_env.in_loop = true;

        const elem_type = switch (iter_type.*) {
            .vec => |v| v,
            else => self.allocType(.{ .primitive = .i32 }),
        };
        try child_env.define(fs.var_name, elem_type, false);
        try self.checkStmtInEnv(&child_env, fs.body);
    }

    fn checkExprInEnv(self: *Checker, env: *TypeEnv, node_idx: usize) (error{OutOfMemory})!*const Type.Type {
        const node = self.arena.get(node_idx);
        return switch (node) {
            .int_lit => self.allocType(.{ .primitive = .i32 }),
            .float_lit => self.allocType(.{ .primitive = .f64 }),
            .bool_lit => self.allocType(.{ .primitive = .bool }),
            .str_lit => self.allocType(.{ .primitive = .str }),
            .char_lit => self.allocType(.{ .primitive = .char }),
            .nil_lit => self.allocType(.void_type),
            .ident => |name| {
                if (env.lookup(name)) |s| return s.typ;
                self.typeError("t002", "Undefined variable");
                return self.allocType(.{ .primitive = .i32 });
            },
            .field => |f| {
                // Try module.function lookup (e.g., fs.write)
                const obj_node = self.arena.get(f.object);
                if (obj_node == .ident) {
                    const full_name = try std.fmt.allocPrint(self.type_arena.allocator(), "{s}.{s}", .{ obj_node.ident, f.field_name });
                    if (env.lookup(full_name)) |s| return s.typ;
                }
                // Fallback: field access on a value (struct field) — return i32 for now
                return self.allocType(.{ .primitive = .i32 });
            },
            .binary => |b| self.checkBinaryInEnv(env, b),
            .unary => |u| self.checkUnaryInEnv(env, u),
            .call => |c| self.checkCallInEnv(env, c),
            .vec_lit => |items| self.checkVecLitInEnv(env, items),
            .struct_lit => |sl| {
                if (self.type_defs.get(sl.type_name)) |t| return t;
                return self.allocType(.{ .primitive = .i32 });
            },
            .assign => |a| self.checkAssignInEnv(env, a),
            else => self.allocType(.{ .primitive = .i32 }),
        };
    }

    fn checkBinaryInEnv(self: *Checker, env: *TypeEnv, b: anytype) (error{OutOfMemory})!*const Type.Type {
        const lt = try self.checkExprInEnv(env, b.left);
        const rt = try self.checkExprInEnv(env, b.right);

        switch (b.op) {
            .add, .sub, .mul, .div, .mod => {
                if (isNumeric(lt) and isNumeric(rt)) return self.allocType(widenNumeric(lt, rt));
                if (lt.* == .primitive and lt.primitive == .str and
                    rt.* == .primitive and rt.primitive == .str)
                {
                    if (b.op == .add) return self.allocType(.{ .primitive = .str });
                }
                self.typeError("t007", "Arithmetic requires numeric operands");
                return self.allocType(.{ .primitive = .i32 });
            },
            .eq, .neq, .gt, .lt, .gte, .lte => {
                if (isComparable(lt, rt)) return self.allocType(.{ .primitive = .bool });
                self.typeError("t007", "Incomparable types");
                return self.allocType(.{ .primitive = .bool });
            },
            .and_, .or_ => {
                if (isBoolish(lt) and isBoolish(rt)) return self.allocType(.{ .primitive = .bool });
                self.typeError("t007", "Logical operators require boolean operands");
                return self.allocType(.{ .primitive = .bool });
            },
        }
    }

    fn checkUnaryInEnv(self: *Checker, env: *TypeEnv, u: anytype) (error{OutOfMemory})!*const Type.Type {
        const ot = try self.checkExprInEnv(env, u.operand);
        switch (u.op) {
            .neg => {
                if (isNumeric(ot)) return ot;
                self.typeError("t007", "Negation requires numeric operand");
                return self.allocType(.{ .primitive = .i32 });
            },
            .not => {
                if (isBoolish(ot)) return self.allocType(.{ .primitive = .bool });
                self.typeError("t007", "Not requires boolean operand");
                return self.allocType(.{ .primitive = .bool });
            },
        }
    }

    fn checkCallInEnv(self: *Checker, env: *TypeEnv, c: anytype) (error{OutOfMemory})!*const Type.Type {
        const callee_type = try self.checkExprInEnv(env, c.callee);
        for (c.args) |arg_idx| {
            _ = try self.checkExprInEnv(env, arg_idx);
        }
        // Return the function's return type
        if (callee_type.* == .func) {
            return callee_type.func.ret;
        }
        return self.allocType(.void_type);
    }

    fn checkVecLitInEnv(self: *Checker, env: *TypeEnv, items: []const usize) (error{OutOfMemory})!*const Type.Type {
        if (items.len == 0) {
            return self.allocType(.{ .vec = @constCast(self.allocType(.{ .primitive = .i32 })) });
        }
        const elem_type = try self.checkExprInEnv(env, items[0]);
        for (items[1..]) |item_idx| {
            const t = try self.checkExprInEnv(env, item_idx);
            if (!isCompatible(t, elem_type)) {
                self.typeError("t001", "Vec elements must have same type");
            }
        }
        return self.allocType(.{ .vec = @constCast(elem_type) });
    }

    fn checkAssignInEnv(self: *Checker, env: *TypeEnv, a: anytype) (error{OutOfMemory})!*const Type.Type {
        const target = self.arena.get(a.target);
        if (target != .ident) {
            self.typeError("t001", "Can only assign to variables");
            return self.allocType(.{ .primitive = .i32 });
        }
        const name = target.ident;
        const sym = env.lookup(name) orelse {
            self.typeError("t002", "Assignment to undefined variable");
            return self.allocType(.{ .primitive = .i32 });
        };
        if (!sym.mutable) self.typeError("t008", "Cannot assign to immutable variable");
        const val_type = try self.checkExprInEnv(env, a.value);
        if (!isCompatible(val_type, sym.typ)) self.typeError("t004", "Assignment type mismatch");
        return sym.typ;
    }
};

fn isNumeric(t: *const Type.Type) bool {
    return switch (t.*) {
        .primitive => |p| switch (p) {
            .i8, .i16, .i32, .i64,
            .u8, .u16, .u32, .u64,
            .f32, .f64,
            => true,
            else => false,
        },
        else => false,
    };
}

fn isBoolish(t: *const Type.Type) bool {
    return t.* == .primitive and t.primitive == .bool;
}

fn isComparable(a: *const Type.Type, b: *const Type.Type) bool {
    if (isNumeric(a) and isNumeric(b)) return true;
    if (isBoolish(a) and isBoolish(b)) return true;
    if (a.* == .primitive and a.primitive == .str and
        b.* == .primitive and b.primitive == .str) return true;
    return false;
}

fn isCompatible(a: *const Type.Type, b: *const Type.Type) bool {
    if (a.eql(b)) return true;
    if (b.* == .void_type) return true;
    // Allow any numeric-to-numeric assignment (compiler handles conversion)
    if (isNumeric(a) and isNumeric(b)) return true;
    return false;
}

fn numericSize(p: Type.Primitive) u8 {
    return switch (p) {
        .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32, .f32 => 4,
        .i64, .u64, .f64 => 8,
        else => 0,
    };
}

fn widenNumeric(a: *const Type.Type, b: *const Type.Type) Type.Type {
    const sa = numericSize(a.primitive);
    const sb = numericSize(b.primitive);
    if (sa >= sb) return a.*;
    return b.*;
}
