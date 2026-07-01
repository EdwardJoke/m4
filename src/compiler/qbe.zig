const std = @import("std");
const ast = @import("ast.zig");

/// Options for the QBE IR emitter.
pub const EmitOptions = struct {
    /// Whether to skip comment annotations (slightly smaller output)
    compact: bool = false,
};

/// Emit QBE IR for a complete m4 program.
/// `stmts` is the flat list of top-level statement indices from the parser.
pub fn emitProgram(
    allocator: std.mem.Allocator,
    arena: *const ast.NodeArena,
    stmts: []const usize,
    opts: EmitOptions,
) ![]const u8 {
    var emitter = Emitter{
        .allocator = allocator,
        .buf = try std.ArrayList(u8).initCapacity(allocator, 0),
        .opts = opts,
        .arena = arena,
        .temp_counter = 0,
        .block_counter = 0,
        .str_counter = 0,
        .scope = std.StringHashMap(VarSlot).init(allocator),
        .scope_stack = try std.ArrayList(std.ArrayList([]const u8)).initCapacity(allocator, 0),
        .strings = std.StringHashMap([]const u8).init(allocator),
        .str_arena = std.heap.ArenaAllocator.init(allocator),
        .temp_boxed = std.StringHashMap(BoxKind).init(allocator),
        .loop_exit_label = null,
        .loop_continue_label = null,
        .current_fn = null,
    };
    defer {
        emitter.buf.deinit(allocator);
        emitter.scope.deinit();
        emitter.temp_boxed.deinit();
        // Free each scope-level key list, then the outer list
        for (emitter.scope_stack.items) |*level| level.deinit(allocator);
        emitter.scope_stack.deinit(allocator);
        emitter.strings.deinit();
        emitter.str_arena.deinit();
    }

    // Phase 1: collect all string literals
    try emitter.collectStrings(stmts);

    // Phase 2: emit data section
    try emitter.emitDataSection();

    // Phase 3: emit functions + inline code
    // First, separate function definitions from inline statements
    var fun_decls = try std.ArrayList(usize).initCapacity(allocator, 0);
    var inline_stmts = try std.ArrayList(usize).initCapacity(allocator, 0);
    defer fun_decls.deinit(allocator);
    defer inline_stmts.deinit(allocator);

    for (stmts) |stmt_idx| {
        const node = arena.get(stmt_idx);
        if (node == .fun_stmt) {
            try fun_decls.append(allocator, stmt_idx);
        } else if (node != .type_decl and node != .use_stmt) {
            try inline_stmts.append(allocator, stmt_idx);
        }
    }

    // Emit all function definitions
    for (fun_decls.items) |fd_idx| {
        try emitter.emitFunStmt(fd_idx);
    }

    // Emit main wrapper only if there are inline statements AND no user-defined `fun main`
    const has_user_main = blk: {
        var found = false;
        for (fun_decls.items) |fd_idx| {
            const node = arena.get(fd_idx);
            if (node == .fun_stmt and std.mem.eql(u8, node.fun_stmt.name, "main")) {
                found = true;
                break;
            }
        }
        break :blk found;
    };
    if (!has_user_main and inline_stmts.items.len > 0) {
        try emitter.emitMainWrapper(inline_stmts.items);
    }

    return emitter.buf.toOwnedSlice(allocator);
}

// ─── QBE Type ──────────────────────────────────────────────────────────────

/// QBE value type annotations.
const QbeType = enum {
    l, // long (64-bit, used for int and pointers on amd64)
    w, // word (32-bit, used for bool/char)
    d, // double (64-bit float)

    fn fmt(self: QbeType) []const u8 {
        return @tagName(self);
    }
};

// ─── Variable Slot ─────────────────────────────────────────────────────────

const BoxKind = enum {
    raw_int,
    raw_bool,
    boxed,
};

const VarSlot = struct {
    name: []const u8, // QBE temp name like "%v0"
    ty: QbeType,
    boxed: BoxKind, // .boxed = M4Value*, .raw_* = unboxed scalar kind
};

// ─── Emitter ───────────────────────────────────────────────────────────────

const Emitter = struct {
    allocator: std.mem.Allocator,
    buf: std.ArrayList(u8),
    opts: EmitOptions,
    arena: *const ast.NodeArena,

    temp_counter: u32,
    block_counter: u32,
    str_counter: u32,

    // Scoped variable mapping (name -> slot). Flat during emission, managed by
    // scope_stack for entering/leaving scopes.
    scope: std.StringHashMap(VarSlot),
    scope_stack: std.ArrayList(std.ArrayList([]const u8)), // keys added per scope level

    // Collected string literals (content -> data label name)
    strings: std.StringHashMap([]const u8),
    str_arena: std.heap.ArenaAllocator,

    // Loop context for continue/esc
    loop_exit_label: ?[]const u8,
    loop_continue_label: ?[]const u8,

    // Tracks the kind of each temporary (boxed M4Value* or unboxed scalar kind)
    temp_boxed: std.StringHashMap(BoxKind),

    // Current function name (for debug comments)
    current_fn: ?[]const u8,

    // ── Helpers ─────────────────────────────────────────────────────────

    fn freshTemp(self: *Emitter) ![]const u8 {
        const n = self.temp_counter;
        self.temp_counter += 1;
        return try std.fmt.allocPrint(self.str_arena.allocator(), "%t{d}", .{n});
    }

    fn freshBlock(self: *Emitter, hint: []const u8) ![]const u8 {
        const n = self.block_counter;
        self.block_counter += 1;
        return try std.fmt.allocPrint(self.str_arena.allocator(), "@{s}.{d}", .{ hint, n });
    }

    fn freshStrLabel(self: *Emitter) ![]const u8 {
        const n = self.str_counter;
        self.str_counter += 1;
        return try std.fmt.allocPrint(self.str_arena.allocator(), "$str{d}", .{n});
    }

    fn freshVarSlot(self: *Emitter) ![]const u8 {
        const n = self.temp_counter;
        self.temp_counter += 1;
        return try std.fmt.allocPrint(self.str_arena.allocator(), "%v{d}", .{n});
    }

    fn write(self: *Emitter, s: []const u8) !void {
        try self.buf.appendSlice(self.allocator, s);
    }

    fn fmt(self: *Emitter, comptime fmt_str: []const u8, args: anytype) !void {
        try self.buf.print(self.allocator, fmt_str, args);
    }

    fn comment(self: *Emitter, s: []const u8) !void {
        if (!self.opts.compact) {
            try self.fmt("\t# {s}\n", .{s});
        }
    }

    fn nl(self: *Emitter) !void {
        try self.write("\n");
    }

    // ── Scope Management ───────────────────────────────────────────────

    /// Record a variable in the current scope and track the key so popScope
    /// can correctly remove only entries added in this level.
    fn scopePut(self: *Emitter, name: []const u8, slot: VarSlot) !void {
        try self.scope.put(name, slot);
        // Track this key in the current (innermost) scope level
        if (self.scope_stack.items.len > 0) {
            try self.scope_stack.items[self.scope_stack.items.len - 1].append(self.allocator, name);
        }
    }

    fn pushScope(self: *Emitter) !void {
        // Create an empty list to hold keys that will be added in this scope level
        try self.scope_stack.append(self.allocator, std.ArrayList([]const u8).initCapacity(self.allocator, 0));
    }

    fn popScope(self: *Emitter) void {
        // Remove only the keys that were added in the scope level being popped
        var added = self.scope_stack.pop();
        defer added.deinit(self.allocator);
        for (added.items) |key| {
            _ = self.scope.remove(key);
        }
    }

    /// Check whether the last statement in a body is a terminator.
    /// In QBE, each block must end with exactly one terminator (ret, jmp, jnz).
    /// If the body already ends with a terminator-producing statement, subsequent
    /// unconditional jumps should be skipped to avoid "X after Y" errors.
    fn bodyEndsWithTerminator(self: *Emitter, body_idx: usize) bool {
        const node = self.arena.get(body_idx);
        const last_idx = if (node == .block and node.block.len > 0)
            node.block[node.block.len - 1]
        else
            body_idx;
        const last = self.arena.get(last_idx);
        return last == .ret_stmt or last == .esc_stmt or last == .continue_stmt;
    }

    fn declareVar(self: *Emitter, name: []const u8, ty: QbeType) ![]const u8 {
        const slot_name = try self.freshVarSlot();
        try self.scopePut(name, .{ .name = slot_name, .ty = ty, .boxed = .boxed });
        return slot_name;
    }

    fn ensureBoxed(self: *Emitter, temp: []const u8) ![]const u8 {
        const kind = self.temp_boxed.get(temp) orelse return temp;
        if (kind == .boxed) return temp;
        const boxed_temp = try self.freshTemp();
        const func = switch (kind) {
            .raw_int => "m4_box_int",
            .raw_bool => "m4_new_bool",
            .boxed => unreachable,
        };
        try self.fmt("\t{s} =l call ${s}(l {s})\n", .{ boxed_temp, func, temp });
        try self.temp_boxed.put(boxed_temp, .boxed);
        return boxed_temp;
    }

    fn lookupVar(self: *Emitter, name: []const u8) ?VarSlot {
        return self.scope.get(name);
    }

    // ── String Collection ──────────────────────────────────────────────

    fn collectStrings(self: *Emitter, stmts: []const usize) !void {
        for (stmts) |idx| {
            try self.collectStringsFromNode(idx);
        }
    }

    fn collectStringsFromNode(self: *Emitter, idx: usize) !void {
        const node = self.arena.get(idx);
        switch (node) {
            .str_lit => |s| {
                const gop = try self.strings.getOrPut(s);
                if (!gop.found_existing) {
                    const label = try self.freshStrLabel();
                    const label_owned = try self.str_arena.allocator().dupe(u8, label);
                    gop.value_ptr.* = label_owned;
                }
            },
            .block => |children| {
                for (children) |child| try self.collectStringsFromNode(child);
            },
            .let_stmt => |ls| {
                if (ls.value) |v| try self.collectStringsFromNode(v);
            },
            .expr_stmt => |e| try self.collectStringsFromNode(e),
            .ret_stmt => |v| if (v) |rv| try self.collectStringsFromNode(rv),
            .if_stmt => |ifs| {
                try self.collectStringsFromNode(ifs.cond);
                try self.collectStringsFromNode(ifs.then_branch);
                for (ifs.elifs) |elif| {
                    try self.collectStringsFromNode(elif.cond);
                    try self.collectStringsFromNode(elif.body);
                }
                if (ifs.else_branch) |eb| try self.collectStringsFromNode(eb);
            },
            .loop_stmt => |body| try self.collectStringsFromNode(body),
            .for_stmt => |fs| {
                try self.collectStringsFromNode(fs.iterable);
                try self.collectStringsFromNode(fs.body);
            },
            .fun_stmt => |fun| {
                try self.collectStringsFromNode(fun.body);
            },
            .assign => |a| {
                try self.collectStringsFromNode(a.target);
                try self.collectStringsFromNode(a.value);
            },
            .binary => |b| {
                try self.collectStringsFromNode(b.left);
                try self.collectStringsFromNode(b.right);
            },
            .unary => |u| try self.collectStringsFromNode(u.operand),
            .call => |c| {
                try self.collectStringsFromNode(c.callee);
                for (c.args) |arg| try self.collectStringsFromNode(arg);
            },
            .index => |ix| {
                try self.collectStringsFromNode(ix.object);
                try self.collectStringsFromNode(ix.idx);
            },
            .field => |f| {
                try self.collectStringsFromNode(f.object);
                const gop = try self.strings.getOrPut(f.field_name);
                if (!gop.found_existing) {
                    const label = try self.freshStrLabel();
                    const label_owned = try self.str_arena.allocator().dupe(u8, label);
                    gop.value_ptr.* = label_owned;
                }
            },
            .struct_lit => |sl| {
                const gop = try self.strings.getOrPut(sl.type_name);
                if (!gop.found_existing) {
                    const label = try self.freshStrLabel();
                    const label_owned = try self.str_arena.allocator().dupe(u8, label);
                    gop.value_ptr.* = label_owned;
                }
                for (sl.fields) |field| {
                    const gop_f = try self.strings.getOrPut(field.name);
                    if (!gop_f.found_existing) {
                        const label = try self.freshStrLabel();
                        const label_owned = try self.str_arena.allocator().dupe(u8, label);
                        gop_f.value_ptr.* = label_owned;
                    }
                    try self.collectStringsFromNode(field.value);
                }
            },
            .vec_lit => |items| {
                for (items) |item| try self.collectStringsFromNode(item);
            },
            .try_expr => |inner| try self.collectStringsFromNode(inner),
            else => {},
        }
    }

    // ── Data Section ──────────────────────────────────────────────────

    fn emitDataSection(self: *Emitter) !void {
        if (self.strings.count() == 0) return;

        try self.write("# ── Data section ─────────────────────────────────────\n\n");
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            const label = entry.value_ptr.*;
            const content = entry.key_ptr.*;
            try self.fmt("data {s} = {{ b \"", .{label});
            // Escape the string for QBE
            for (content) |ch| {
                switch (ch) {
                    '"' => try self.write("\\\""),
                    '\\' => try self.write("\\\\"),
                    '\n' => try self.write("\\n"),
                    '\t' => try self.write("\\t"),
                    '\r' => try self.write("\\r"),
                    0...8, 11, 12, 14...31 => {
                        // escape non-printable as hex
                        try self.fmt("\\x{x:0>2}", .{ch});
                    },
                    else => try self.buf.append(self.allocator, ch),
                }
            }
            try self.write("\", b 0 }\n");
        }
        try self.nl();
    }

    // ── Function Emission ─────────────────────────────────────────────

    fn emitMainWrapper(self: *Emitter, stmts: []const usize) anyerror!void {
        try self.write("export function w $main(w %argc, l %argv) {\n");
        try self.write("@main.entry\n");

        // Allocate param slots (though we won't use them by name in m4)
        _ = try self.declareVar("@argc", .w);
        _ = try self.declareVar("@argv", .l);

        self.current_fn = "main";

        try self.emitBlockStatements(stmts);

        // Implicit return 0
        try self.write("\tret 0\n");
        try self.write("}\n\n");
    }

    fn emitFunStmt(self: *Emitter, idx: usize) anyerror!void {
        const fun = self.arena.get(idx).fun_stmt;
        self.current_fn = fun.name;

        // Determine return type
        const ret_ty: QbeType = if (fun.ret_type != null) m4TypeToQbe(fun.ret_type.?) else .l;

        // Emit function header
        try self.fmt("export function {s} ${s}(", .{ ret_ty.fmt(), fun.name });

        // Emit parameters
        for (fun.params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            const pty: QbeType = if (param.type_annot) |ta| m4TypeToQbe(ta) else .l;
            // Use parameter name as QBE temporary
            try self.fmt("{s} %{s}", .{ pty.fmt(), param.name });
        }
        try self.write(") {\n");

        // Entry block
        try self.fmt("@_{s}.entry\n", .{fun.name});

        // Allocate local slots and store parameters
        for (fun.params) |param| {
            const pty: QbeType = if (param.type_annot) |ta| m4TypeToQbe(ta) else .l;
            // Declare a slot and store param into it (for mutable access)
            const alloca_slot = try self.freshVarSlot();
            try self.fmt("\t{s} =l alloc8 1\n", .{alloca_slot});
            try self.fmt("\tstore{s} %{s}, {s}\n", .{
                QbeStoreSuffix(pty),
                param.name,
                alloca_slot,
            });
            // Update scope with alloca slot
            try self.scopePut(param.name, .{ .name = alloca_slot, .ty = pty, .boxed = .boxed });
        }

        // Emit function body
        try self.emitBlockStatements(&.{(fun.body)});

        // Implicit return — only if the body does NOT already end with a `ret`
        // (esc/continue at function scope are invalid, so only check ret_stmt)
        if (!self.bodyEndsWithTerminator(fun.body)) {
            const ret_val = if (ret_ty == .d) "0.0" else "0";
            try self.fmt("\tret {s}\n", .{ret_val});
        }
        try self.write("}\n\n");
    }

    /// Emit a block of statements. `body_idxs` are indices into the arena.
    /// If a single index points to a block node, expand it.
    fn emitBlockStatements(self: *Emitter, body_idxs: []const usize) anyerror!void {
        // Each element might be a single statement or a block node
        for (body_idxs) |idx| {
            const node = self.arena.get(idx);
            if (node == .block) {
                for (node.block) |child| {
                    try self.emitStmt(child);
                }
            } else {
                try self.emitStmt(idx);
            }
        }
    }

    // ── Statement Emission ────────────────────────────────────────────

    fn emitStmt(self: *Emitter, idx: usize) anyerror!void {
        const node = self.arena.get(idx);
        switch (node) {
            .let_stmt => try self.emitLetStmt(idx),
            .expr_stmt => {
                const temp = try self.emitExpr(node.expr_stmt);
                try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "discard expr {s}", .{temp}));
            },
            .ret_stmt => try self.emitRetStmt(idx),
            .if_stmt => try self.emitIfStmt(idx),
            .loop_stmt => try self.emitLoopStmt(idx),
            .for_stmt => try self.emitForStmt(idx),
            .continue_stmt => try self.emitContinueStmt(),
            .esc_stmt => try self.emitEscStmt(),
            .assign => try self.emitAssignStmt(idx),
            .block => {
                for (node.block) |child| try self.emitStmt(child);
            },
            else => try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "unhandled stmt type {s}", .{@tagName(node)})),
        }
    }

    fn emitLetStmt(self: *Emitter, idx: usize) anyerror!void {
        const ls = self.arena.get(idx).let_stmt;
        const ty: QbeType = if (ls.type_annot) |ta| m4TypeToQbe(ta) else .l;

        const alloca_slot = try self.freshVarSlot();
        try self.fmt("\t{s} =l alloc8 1\n", .{alloca_slot});

        if (ls.value) |val_idx| {
            const val_temp = try self.emitExpr(val_idx);
            const boxed = self.temp_boxed.get(val_temp) orelse .boxed;
            try self.scopePut(ls.name, .{ .name = alloca_slot, .ty = ty, .boxed = boxed });
            try self.fmt("\tstore{s} {s}, {s}\n", .{ QbeStoreSuffix(ty), val_temp, alloca_slot });
        } else {
            try self.scopePut(ls.name, .{ .name = alloca_slot, .ty = ty, .boxed = .boxed });
            const zero = if (ty == .d) "0.0" else "0";
            try self.fmt("\tstore{s} {s}, {s}\n", .{ QbeStoreSuffix(ty), zero, alloca_slot });
        }
    }

    fn emitRetStmt(self: *Emitter, idx: usize) anyerror!void {
        const ret_val = self.arena.get(idx).ret_stmt;
        if (ret_val) |val_idx| {
            const temp = try self.emitExpr(val_idx);
            // Determine return type from value (heuristic)
            try self.fmt("\tret {s}\n", .{temp});
        } else {
            try self.write("\tret\n");
        }
    }

    fn emitIfStmt(self: *Emitter, idx: usize) anyerror!void {
        const ifs = self.arena.get(idx).if_stmt;
        const end_label = try self.freshBlock("if_end");
        var else_label: ?[]const u8 = null;

        // Emit condition
        const cond_temp = try self.emitExpr(ifs.cond);
        const cond_boxed = self.temp_boxed.get(cond_temp) orelse .boxed;
        const then_label = try self.freshBlock("then");
        else_label = try self.freshBlock("else");
        if (cond_boxed == .boxed) {
            const cond_boxed_val = try self.ensureBoxed(cond_temp);
            const is_truthy = try self.freshTemp();
            try self.fmt("\t{s} =l call $m4_is_truthy(l {s})\n", .{ is_truthy, cond_boxed_val });
            try self.fmt("\tjnz {s}, {s}, {s}\n", .{ is_truthy, then_label, else_label.? });
        } else {
            // Unboxed: truthy if non-zero
            try self.fmt("\tjnz {s}, {s}, {s}\n", .{ cond_temp, then_label, else_label.? });
        }

        // Then branch
        try self.fmt("{s}\n", .{then_label});
        try self.emitBlockStatements(&.{ifs.then_branch});
        if (!self.bodyEndsWithTerminator(ifs.then_branch)) {
            try self.fmt("\tjmp {s}\n", .{end_label});
        }

        // Elif branches: emit the else label first so the elif condition
        // computation lands in the correct block (not after then's jmp).
        for (ifs.elifs) |elif| {
            const elif_then = try self.freshBlock("elif_then");
            const elif_else = try self.freshBlock("elif_else");

            try self.fmt("{s}\n", .{else_label.?});
            const elif_cond = try self.emitExpr(elif.cond);
            const elif_truthy = try self.freshTemp();
            try self.fmt("\t{s} =l call $m4_is_truthy(l {s})\n", .{ elif_truthy, elif_cond });
            try self.fmt("\tjnz {s}, {s}, {s}\n", .{ elif_truthy, elif_then, elif_else });
            try self.fmt("{s}\n", .{elif_then});
            try self.emitBlockStatements(&.{elif.body});
            if (!self.bodyEndsWithTerminator(elif.body)) {
                try self.fmt("\tjmp {s}\n", .{end_label});
            }

            else_label = elif_else;
        }

        // Else branch
        try self.fmt("{s}\n", .{else_label.?});
        if (ifs.else_branch) |eb| {
            try self.emitBlockStatements(&.{eb});
            if (!self.bodyEndsWithTerminator(eb)) {
                try self.fmt("\tjmp {s}\n", .{end_label});
            }
        } else {
            try self.fmt("\tjmp {s}\n", .{end_label});
        }

        // End label
        try self.fmt("{s}\n", .{end_label});
    }

    fn emitLoopStmt(self: *Emitter, idx: usize) anyerror!void {
        const body_idx = self.arena.get(idx).loop_stmt;
        const loop_header = try self.freshBlock("loop_header");
        const loop_body = try self.freshBlock("loop_body");
        const exit_label = try self.freshBlock("loop_exit");

        // Save and set loop context
        const saved_exit = self.loop_exit_label;
        const saved_continue = self.loop_continue_label;
        self.loop_exit_label = exit_label;
        self.loop_continue_label = loop_header;

        // Loop header (jump to body unconditionally; continue jumps here)
        try self.fmt("{s}\n", .{loop_header});
        try self.fmt("\tjmp {s}\n", .{loop_body});

        // Body — only jump back to header if body doesn't end with a terminator
        try self.fmt("{s}\n", .{loop_body});
        try self.emitBlockStatements(&.{body_idx});
        if (!self.bodyEndsWithTerminator(body_idx)) {
            try self.fmt("\tjmp {s}\n", .{loop_header});
        }

        // Exit
        try self.fmt("{s}\n", .{exit_label});

        // Restore loop context
        self.loop_exit_label = saved_exit;
        self.loop_continue_label = saved_continue;
    }

    fn emitForStmt(self: *Emitter, idx: usize) anyerror!void {
        const fs = self.arena.get(idx).for_stmt;

        // Compile iterable
        const iter_temp = try self.emitExpr(fs.iterable);
        const iter_var = try self.freshVarSlot();
        try self.fmt("\t{s} =l alloc8 1\n", .{iter_var});
        try self.fmt("\tstorel {s}, {s}\n", .{ iter_temp, iter_var });

        // Index variable
        const idx_var = try self.freshVarSlot();
        try self.fmt("\t{s} =l alloc8 1\n", .{idx_var});
        try self.fmt("\tstorel 0, {s}\n", .{idx_var});

        const loop_header = try self.freshBlock("for_header");
        const loop_body = try self.freshBlock("for_body");
        const exit_label = try self.freshBlock("for_exit");
        const inc_label = try self.freshBlock("for_inc");

        // Save and set loop context
        const saved_exit = self.loop_exit_label;
        const saved_continue = self.loop_continue_label;
        self.loop_exit_label = exit_label;
        self.loop_continue_label = inc_label;

        // Loop header: check condition
        try self.fmt("{s}\n", .{loop_header});
        const iter_loaded = try self.freshTemp();
        try self.fmt("\t{s} =l loadl {s}\n", .{ iter_loaded, iter_var });
        const idx_loaded = try self.freshTemp();
        try self.fmt("\t{s} =l loadl {s}\n", .{ idx_loaded, idx_var });

        // Box iterable and index before calling runtime functions
        const boxed_iter = try self.ensureBoxed(iter_loaded);
        const boxed_idx = try self.ensureBoxed(idx_loaded);

        const len_temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_len(l {s})\n", .{ len_temp, boxed_iter });
        const cmp_temp = try self.freshTemp();
        try self.fmt("\t{s} =w csltl {s}, {s}\n", .{ cmp_temp, idx_loaded, len_temp });
        try self.fmt("\tjnz {s}, {s}, {s}\n", .{ cmp_temp, loop_body, exit_label });

        // Body: get element and declare loop variable
        try self.fmt("{s}\n", .{loop_body});
        const elem_temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_get(l {s}, l {s})\n", .{ elem_temp, boxed_iter, boxed_idx });
        const loop_var_slot = try self.declareVar(fs.var_name, .l);
        try self.fmt("\t{s} =l alloc8 1\n", .{loop_var_slot});
        try self.fmt("\tstorel {s}, {s}\n", .{ elem_temp, loop_var_slot });

        try self.emitBlockStatements(&.{fs.body});

        // Increment
        try self.fmt("{s}\n", .{inc_label});
        const idx2 = try self.freshTemp();
        try self.fmt("\t{s} =l loadl {s}\n", .{ idx2, idx_var });
        const one_plus = try self.freshTemp();
        try self.fmt("\t{s} =l add {s}, 1\n", .{ one_plus, idx2 });
        try self.fmt("\tstorel {s}, {s}\n", .{ one_plus, idx_var });
        try self.fmt("\tjmp {s}\n", .{loop_header});

        // Exit
        try self.fmt("{s}\n", .{exit_label});

        // Restore loop context
        self.loop_exit_label = saved_exit;
        self.loop_continue_label = saved_continue;
    }

    fn emitContinueStmt(self: *Emitter) anyerror!void {
        if (self.loop_continue_label) |label| {
            try self.fmt("\tjmp {s}\n", .{label});
        } else {
            try self.comment("continue outside loop (ignored)");
        }
    }

    fn emitEscStmt(self: *Emitter) anyerror!void {
        if (self.loop_exit_label) |label| {
            try self.fmt("\tjmp {s}\n", .{label});
        } else {
            try self.comment("esc outside loop (ignored)");
        }
    }

    fn emitAssignStmt(self: *Emitter, idx: usize) anyerror!void {
        const assign = self.arena.get(idx).assign;
        const value_temp = try self.emitExpr(assign.value);

        // Resolve the target
        const target = self.arena.get(assign.target);
        if (target == .ident) {
            const name = target.ident;
            if (self.lookupVar(name)) |slot| {
                try self.fmt("\tstore{s} {s}, {s}\n", .{ QbeStoreSuffix(slot.ty), value_temp, slot.name });
                // Update slot's boxed status to match the stored value
                if (self.temp_boxed.get(value_temp)) |b| {
                    // Can't update the slot in-place since it's a value copy, re-insert
                    try self.scope.put(name, .{ .name = slot.name, .ty = slot.ty, .boxed = b });
                }
            } else {
                try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "assign to unknown var '{s}'", .{name}));
            }
        } else {
            try self.comment("assign to non-identifier target");
        }
    }

    // ── Expression Emission ───────────────────────────────────────────

    /// Evaluate an expression and return the name of a temp holding the result.
    fn emitExpr(self: *Emitter, idx: usize) anyerror![]const u8 {
        const node = self.arena.get(idx);
        return switch (node) {
            .int_lit => |v| try self.emitIntLit(v),
            .float_lit => |v| try self.emitFloatLit(v),
            .bool_lit => |v| try self.emitBoolLit(v),
            .nil_lit => try self.emitNilLit(),
            .str_lit => |s| try self.emitStrLit(s),
            .char_lit => |c| try self.emitCharLit(c),
            .ident => |name| try self.emitIdent(name),
            .binary => try self.emitBinary(idx),
            .unary => try self.emitUnary(idx),
            .call => try self.emitCall(idx),
            .assign => try self.emitAssign(idx),
            .index => try self.emitIndex(idx),
            .field => try self.emitField(idx),
            .struct_lit => try self.emitStructLit(idx),
            .vec_lit => try self.emitVecLit(idx),
            .try_expr => try self.emitTry(idx),
            else => {
                const temp = try self.freshTemp();
                try self.fmt("\t{s} =l copy 0\n", .{temp});
                try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "unhandled expr type {s}", .{@tagName(node)}));
                return temp;
            },
        };
    }

    fn emitIntLit(self: *Emitter, v: i64) ![]const u8 {
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l copy {d}\n", .{ temp, v });
        try self.temp_boxed.put(temp, .raw_int);
        return temp;
    }

    fn emitFloatLit(self: *Emitter, v: f64) ![]const u8 {
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_new_float(d d_{d})\n", .{ temp, v });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitBoolLit(self: *Emitter, v: bool) ![]const u8 {
        const temp = try self.freshTemp();
        const val: i64 = if (v) 1 else 0;
        try self.fmt("\t{s} =l call $m4_new_bool(l {d})\n", .{ temp, val });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitNilLit(self: *Emitter) ![]const u8 {
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l copy 0\n", .{temp});
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitCharLit(self: *Emitter, c: u21) ![]const u8 {
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_new_char(l {d})\n", .{ temp, @as(i64, @intCast(c)) });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitStrLit(self: *Emitter, s: []const u8) ![]const u8 {
        const gop = try self.strings.getOrPut(s);
        const label = if (gop.found_existing) gop.value_ptr.* else lbl: {
            const lbl = try self.freshStrLabel();
            gop.value_ptr.* = lbl;
            break :lbl lbl;
        };
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_new_string(l {s}, l {d})\n", .{ temp, label, @as(i64, @intCast(s.len)) });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitIdent(self: *Emitter, name: []const u8) ![]const u8 {
        if (self.lookupVar(name)) |slot| {
            const temp = try self.freshTemp();
            try self.fmt("\t{s} =l loadl {s}\n", .{ temp, slot.name });
            try self.temp_boxed.put(temp, slot.boxed);
            return temp;
        }
        // Global/unknown — emit as 0 (nil pointer)
        try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "unknown ident '{s}'", .{name}));
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l copy 0\n", .{temp});
        try self.temp_boxed.put(temp, .raw_int);
        return temp;
    }

    fn emitBinary(self: *Emitter, idx: usize) ![]const u8 {
        const b = self.arena.get(idx).binary;
        const left = try self.emitExpr(b.left);
        const right = try self.emitExpr(b.right);
        const temp = try self.freshTemp();

        // Check if both operands are unboxed (raw ints) → use native QBE ops
        const left_boxed = self.temp_boxed.get(left) orelse .boxed;
        const right_boxed = self.temp_boxed.get(right) orelse .boxed;
        const both_unboxed = left_boxed != .boxed and right_boxed != .boxed;

        switch (b.op) {
            .add => {
                if (both_unboxed) {
                    try self.fmt("\t{s} =l add {s}, {s}\n", .{ temp, left, right });
                    try self.temp_boxed.put(temp, .raw_int);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_add(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .sub => {
                if (both_unboxed) {
                    try self.fmt("\t{s} =l sub {s}, {s}\n", .{ temp, left, right });
                    try self.temp_boxed.put(temp, .raw_int);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_sub(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .mul => {
                if (both_unboxed) {
                    try self.fmt("\t{s} =l mul {s}, {s}\n", .{ temp, left, right });
                    try self.temp_boxed.put(temp, .raw_int);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_mul(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .div => {
                if (both_unboxed) {
                    try self.fmt("\t{s} =l call $m4_div_u(l {s}, l {s})\n", .{ temp, left, right });
                    try self.temp_boxed.put(temp, .boxed);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_div(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .mod => {
                if (both_unboxed) {
                    try self.fmt("\t{s} =l call $m4_mod_u(l {s}, l {s})\n", .{ temp, left, right });
                    try self.temp_boxed.put(temp, .boxed);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_mod(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .eq => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w ceql {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_eq(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .neq => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w cnel {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_neq(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .gt => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w csgtl {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_gt(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .lt => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w csltl {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_lt(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .gte => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w csgel {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_gte(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .lte => {
                if (both_unboxed) {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w cslel {s}, {s}\n", .{ cmp, left, right });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                } else {
                    const boxed_l = try self.ensureBoxed(left);
                    const boxed_r = try self.ensureBoxed(right);
                    try self.fmt("\t{s} =l call $m4_lte(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                    try self.temp_boxed.put(temp, .boxed);
                }
            },
            .and_ => {
                const boxed_l = try self.ensureBoxed(left);
                const boxed_r = try self.ensureBoxed(right);
                try self.fmt("\t{s} =l call $m4_and(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                try self.temp_boxed.put(temp, .boxed);
            },
            .or_ => {
                const boxed_l = try self.ensureBoxed(left);
                const boxed_r = try self.ensureBoxed(right);
                try self.fmt("\t{s} =l call $m4_or(l {s}, l {s})\n", .{ temp, boxed_l, boxed_r });
                try self.temp_boxed.put(temp, .boxed);
            },
        }
        return temp;
    }

    fn emitUnary(self: *Emitter, idx: usize) ![]const u8 {
        const u = self.arena.get(idx).unary;
        const operand = try self.emitExpr(u.operand);
        const temp = try self.freshTemp();
        const is_boxed = self.temp_boxed.get(operand) orelse .boxed;

        switch (u.op) {
            .neg => {
                if (is_boxed == .boxed) {
                    const boxed_op = try self.ensureBoxed(operand);
                    try self.fmt("\t{s} =l call $m4_neg(l {s})\n", .{ temp, boxed_op });
                    try self.temp_boxed.put(temp, .boxed);
                } else {
                    try self.fmt("\t{s} =l sub 0, {s}\n", .{ temp, operand });
                    try self.temp_boxed.put(temp, .raw_int);
                }
            },
            .not => {
                if (is_boxed == .boxed) {
                    const boxed_op = try self.ensureBoxed(operand);
                    try self.fmt("\t{s} =l call $m4_not(l {s})\n", .{ temp, boxed_op });
                    try self.temp_boxed.put(temp, .boxed);
                } else {
                    const cmp = try self.freshTemp();
                    try self.fmt("\t{s} =w ceql {s}, 0\n", .{ cmp, operand });
                    try self.fmt("\t{s} =l extuw {s}\n", .{ temp, cmp });
                    try self.temp_boxed.put(temp, .raw_bool);
                }
            },
        }
        return temp;
    }

    fn emitCall(self: *Emitter, idx: usize) ![]const u8 {
        const c = self.arena.get(idx).call;
        // Resolve callee name
        const callee_name = resolveCalleeName(self.arena, self.str_arena.allocator(), c.callee) catch {
            try self.comment("cannot resolve callee name");
            const fallback = try self.freshTemp();
            try self.fmt("\t{s} =l copy 0\n", .{fallback});
            return fallback;
        };

        // Emit arguments
        var arg_temps = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer arg_temps.deinit(self.allocator);

        for (c.args) |arg_idx| {
            const arg_temp = try self.emitExpr(arg_idx);
            const boxed_arg = try self.ensureBoxed(arg_temp);
            try arg_temps.append(self.allocator, boxed_arg);
        }

        // Map stdlib module names to runtime m4_* prefixed names
        // e.g. "std.println" → "m4_std_println"
        const mapped_name = if (std.mem.startsWith(u8, callee_name, "std.") or
            std.mem.startsWith(u8, callee_name, "range."))
        blk: {
            const arena_a = self.str_arena.allocator();
            const buf = try arena_a.alloc(u8, 3 + callee_name.len);
            buf[0] = 'm';
            buf[1] = '4';
            buf[2] = '_';
            for (callee_name, 0..) |ch, i| {
                buf[3 + i] = if (ch == '.') '_' else ch;
            }
            break :blk buf;
        } else callee_name;

        // Emit call
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call ${s}(", .{ temp, mapped_name });
        for (arg_temps.items, 0..) |arg, i| {
            if (i > 0) try self.write(", ");
            try self.fmt("l {s}", .{arg});
        }
        try self.write(")\n");
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitAssign(self: *Emitter, idx: usize) ![]const u8 {
        const a = self.arena.get(idx).assign;
        const value_temp = try self.emitExpr(a.value);

        const target = self.arena.get(a.target);
        if (target == .ident) {
            const name = target.ident;
            if (self.lookupVar(name)) |slot| {
                try self.fmt("\tstore{s} {s}, {s}\n", .{ QbeStoreSuffix(slot.ty), value_temp, slot.name });
            }
        }

        return value_temp;
    }

    fn emitIndex(self: *Emitter, idx: usize) ![]const u8 {
        const ix = self.arena.get(idx).index;
        const obj = try self.emitExpr(ix.object);
        const idx_val = try self.emitExpr(ix.idx);
        const boxed_obj = try self.ensureBoxed(obj);
        const boxed_idx = try self.ensureBoxed(idx_val);
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_index(l {s}, l {s})\n", .{ temp, boxed_obj, boxed_idx });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitField(self: *Emitter, idx: usize) ![]const u8 {
        const f = self.arena.get(idx).field;
        const obj = try self.emitExpr(f.object);
        const boxed_obj = try self.ensureBoxed(obj);
        const temp = try self.freshTemp();
        const field_label = self.strings.get(f.field_name) orelse {
            try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "missing string label for field '{s}'", .{f.field_name}));
            return temp;
        };
        try self.fmt("\t{s} =l call $m4_field(l {s}, l {s})\n", .{ temp, boxed_obj, field_label });
        try self.temp_boxed.put(temp, .boxed);
        return temp;
    }

    fn emitStructLit(self: *Emitter, idx: usize) ![]const u8 {
        const sl = self.arena.get(idx).struct_lit;
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_new_struct(l 0)\n", .{temp});
        try self.temp_boxed.put(temp, .boxed);
        for (sl.fields) |field| {
            const val = try self.emitExpr(field.value);
            const boxed_val = try self.ensureBoxed(val);
            const field_label = self.strings.get(field.name) orelse {
                try self.comment(try std.fmt.allocPrint(self.str_arena.allocator(), "missing string label for field '{s}'", .{field.name}));
                continue;
            };
            try self.fmt("\tcall $m4_struct_set(l {s}, l {s}, l {s})\n", .{ temp, field_label, boxed_val });
        }
        return temp;
    }

    fn emitVecLit(self: *Emitter, idx: usize) ![]const u8 {
        const items = self.arena.get(idx).vec_lit;
        const temp = try self.freshTemp();
        try self.fmt("\t{s} =l call $m4_new_vec(l {d})\n", .{ temp, @as(i64, @intCast(items.len)) });
        try self.temp_boxed.put(temp, .boxed);
        for (items, 0..) |item, i| {
            const val = try self.emitExpr(item);
            const boxed_val = try self.ensureBoxed(val);
            try self.fmt("\tcall $m4_vec_set(l {s}, l {d}, l {s})\n", .{ temp, @as(i64, @intCast(i)), boxed_val });
        }
        return temp;
    }

    fn emitTry(self: *Emitter, idx: usize) ![]const u8 {
        const inner = self.arena.get(idx).try_expr;
        // For now, just emit the inner expression (no error propagation in QBE yet)
        return try self.emitExpr(inner);
    }

    // ── Type Helpers ──────────────────────────────────────────────────

    // (runtime dispatch handles type specialization, no isFloatNode needed)
};

// ─── Module-Level Helpers ───────────────────────────────────────────────────

fn QbeStoreSuffix(ty: QbeType) []const u8 {
    return switch (ty) {
        .l => "l",
        .w => "w",
        .d => "d",
    };
}

fn m4TypeToQbe(type_idx: usize) QbeType {
    _ = type_idx;
    // For now, all m4 values are represented as `l` (64-bit) in QBE.
    // This is a simplified mapping; the type index points into the type
    // checker's type pool which we don't have direct access to here.
    // Future work: resolve type index → Type → QbeType.
    return .l;
}

/// Resolve the name of a callee from an expression.
/// Allocates into `arena_alloc` for dotted names (e.g. "obj.field").
fn resolveCalleeName(arena: *const ast.NodeArena, arena_alloc: std.mem.Allocator, callee_idx: usize) ![]const u8 {
    const node = arena.get(callee_idx);
    return switch (node) {
        .ident => |name| name,
        .field => |f| {
            const obj_name = try resolveCalleeName(arena, arena_alloc, f.object);
            return try std.fmt.allocPrint(arena_alloc, "{s}.{s}", .{ obj_name, f.field_name });
        },
        else => error.UnsupportedCallee,
    };
}
