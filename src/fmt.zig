const std = @import("std");
const ast = @import("ast.zig");

/// Pretty-print an AST node to stderr with the given indentation level.
pub fn formatNode(arena: *ast.NodeArena, node_idx: usize, indent: u32) void {
    const node = arena.get(node_idx);
    writeIndent(indent);
    switch (node) {
        .let_stmt => |ls| {
            std.debug.print("{s} {s}", .{ if (ls.mutable) "mut" else "let", ls.name });
            if (ls.type_annot) |ta| {
                std.debug.print(" ", .{});
                formatTypeExpr(arena, ta);
            }
            if (ls.value) |vi| {
                std.debug.print(" = ", .{});
                formatExpr(arena, vi);
            }
        },
        .expr_stmt => |ei| formatExpr(arena, ei),
        .if_stmt => |ifs| {
            std.debug.print("if ", .{});
            formatExpr(arena, ifs.cond);
            std.debug.print("\n", .{});
            formatBlock(arena, ifs.then_branch, indent + 4);
            for (ifs.elifs) |elif| {
                writeIndent(indent);
                std.debug.print("elif ", .{});
                formatExpr(arena, elif.cond);
                std.debug.print("\n", .{});
                formatBlock(arena, elif.body, indent + 4);
            }
            if (ifs.else_branch) |eb| {
                writeIndent(indent);
                std.debug.print("else\n", .{});
                formatBlock(arena, eb, indent + 4);
            }
        },
        .loop_stmt => |body| {
            std.debug.print("loop\n", .{});
            formatBlock(arena, body, indent + 4);
        },
        .for_stmt => |fs| {
            std.debug.print("for {s} in ", .{fs.var_name});
            formatExpr(arena, fs.iterable);
            std.debug.print("\n", .{});
            formatBlock(arena, fs.body, indent + 4);
        },
        .continue_stmt => std.debug.print("continue", .{}),
        .esc_stmt => std.debug.print("esc", .{}),
        .ret_stmt => |rs| {
            std.debug.print("ret", .{});
            if (rs) |vi| {
                std.debug.print(" ", .{});
                formatExpr(arena, vi);
            }
        },
        .fun_stmt => |fs| {
            if (fs.public) std.debug.print("pub ", .{});
            std.debug.print("fun {s}(", .{fs.name});
            for (fs.params, 0..) |p, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{p.name});
                if (p.type_annot) |ta| {
                    std.debug.print(" ", .{});
                    formatTypeExpr(arena, ta);
                }
            }
            std.debug.print(")", .{});
            if (fs.ret_type) |rt| {
                std.debug.print(" ", .{});
                formatTypeExpr(arena, rt);
            }
            std.debug.print("\n", .{});
            formatBlock(arena, fs.body, indent + 4);
        },
        .type_decl => |td| {
            std.debug.print("type {s}\n", .{td.name});
            for (td.fields) |f| {
                writeIndent(indent + 4);
                std.debug.print("{s} ", .{f.name});
                formatTypeExpr(arena, f.type_annot);
                std.debug.print("\n", .{});
            }
        },
        .use_stmt => |us| std.debug.print("use {s}", .{us.path}),
        .block => |stmts| {
            for (stmts) |s| {
                formatNode(arena, s, indent);
                std.debug.print("\n", .{});
            }
        },
        else => std.debug.print("<node>", .{}),
    }
}

fn formatExpr(arena: *ast.NodeArena, node_idx: usize) void {
    const node = arena.get(node_idx);
    switch (node) {
        .int_lit => |v| std.debug.print("{d}", .{v}),
        .float_lit => |v| std.debug.print("{d}", .{v}),
        .bool_lit => |v| std.debug.print("{}", .{v}),
        .str_lit => |v| std.debug.print("\"{s}\"", .{v}),
        .nil_lit => std.debug.print("nil", .{}),
        .ident => |n| std.debug.print("{s}", .{n}),
        .field => |f| {
            formatExpr(arena, f.object);
            std.debug.print(".{s}", .{f.field_name});
        },
        .binary => |b| {
            formatExpr(arena, b.left);
            std.debug.print(" {s} ", .{opStr(b.op)});
            formatExpr(arena, b.right);
        },
        .unary => |u| {
            std.debug.print("{s}", .{if (u.op == .neg) "-" else "!"});
            formatExpr(arena, u.operand);
        },
        .call => |c| {
            formatExpr(arena, c.callee);
            std.debug.print("(", .{});
            for (c.args, 0..) |a, i| {
                if (i > 0) std.debug.print(", ", .{});
                formatExpr(arena, a);
            }
            std.debug.print(")", .{});
        },
        .vec_lit => |items| {
            std.debug.print("[", .{});
            for (items, 0..) |it, i| {
                if (i > 0) std.debug.print(", ", .{});
                formatExpr(arena, it);
            }
            std.debug.print("]", .{});
        },
        .try_expr => |inner| {
            formatExpr(arena, inner);
            std.debug.print("?", .{});
        },
        .struct_lit => |sl| {
            std.debug.print("{s}(", .{sl.type_name});
            for (sl.fields, 0..) |f, i| {
                if (i > 0) std.debug.print(" ", .{});
                std.debug.print("{s}: ", .{f.name});
                formatExpr(arena, f.value);
            }
            std.debug.print(")", .{});
        },
        else => std.debug.print("<expr>", .{}),
    }
}

fn formatTypeExpr(arena: *ast.NodeArena, node_idx: usize) void {
    const node = arena.get(node_idx);
    switch (node) {
        .ident => std.debug.print("{s}", .{node.ident}),
        .type_ident => |n| std.debug.print("{s}", .{n}),
        else => std.debug.print("<type>", .{}),
    }
}

fn formatBlock(arena: *ast.NodeArena, node_idx: usize, indent: u32) void {
    const node = arena.get(node_idx);
    if (node == .block) {
        for (node.block) |s| {
            formatNode(arena, s, indent);
            std.debug.print("\n", .{});
        }
    }
}

fn writeIndent(indent: u32) void {
    var i: u32 = 0;
    while (i < indent) : (i += 1) std.debug.print(" ", .{});
}

fn opStr(op: ast.BinaryOp) []const u8 {
    return switch (op) {
        .add => "+", .sub => "-", .mul => "*", .div => "/", .mod => "%",
        .eq => "==", .neq => "!=", .gt => ">", .lt => "<", .gte => ">=", .lte => "<=",
        .and_ => "&&", .or_ => "||",
    };
}
