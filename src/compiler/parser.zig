const std = @import("std");
const Token = @import("token.zig");
const ast = @import("ast.zig");
const Scanner = @import("scanner.zig");
const err = @import("error.zig");

const Precedence = enum(u8) {
    none,
    assignment,
    or_,
    and_,
    equality,
    comparison,
    term,
    factor,
    unary,
    call,
    primary,
};

const PrefixFn = *const fn (*Parser) anyerror!usize;
const InfixFn = *const fn (*Parser, usize) anyerror!usize;

const ParseRule = struct {
    prefix: ?PrefixFn,
    infix: ?InfixFn,
    precedence: Precedence,
};

pub const Error = error{ ParseError, OutOfMemory };

pub const Parser = @This();

allocator: std.mem.Allocator,
scanner: Scanner,
arena: ast.NodeArena,
current: Token.Token,
previous: Token.Token,
had_error: bool,
diag: ?*err.DiagnosticList = null,

/// Initialize a new parser for the given source string. Automatically advances to the first token.
pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
    var p = Parser{
        .allocator = allocator,
        .scanner = Scanner.init(allocator, source),
        .arena = ast.NodeArena.init(allocator),
        .current = .{ .tag = .eof, .start = "", .line = 0 },
        .previous = .{ .tag = .eof, .start = "", .line = 0 },
        .had_error = false,
    };
    p.advance();
    return p;
}

/// Deinitialize the parser, freeing the scanner and AST arena.
pub fn deinit(self: *Parser) void {
    self.scanner.deinit();
    self.arena.deinit();
}

/// Parse the entire source into a list of AST statement indices. Returns ParseError on syntax errors.
pub fn parse(self: *Parser) ![]const usize {
    var stmts = std.ArrayList(usize).empty;
    errdefer stmts.deinit(self.allocator);
    self.skipNewlines();
    while (!self.check(.eof)) {
        if (try self.declaration()) |stmt| {
            try stmts.append(self.allocator, stmt);
        } else {
            const s = try self.statement();
            try stmts.append(self.allocator, s);
        }
        self.skipNewlines();
    }
    if (self.had_error) return error.ParseError;
    return stmts.toOwnedSlice(self.allocator);
}

fn skipNewlines(self: *Parser) void {
    while (self.current.tag == .newline) {
        self.advanceRaw();
    }
}

// ── Declarations ───────────────────────────────────────────────────────────

fn declaration(self: *Parser) Error!?usize {
    if (self.current.tag == .kw_let) return try self.letDecl(false);
    if (self.current.tag == .kw_mut) return try self.letDecl(true);
    if (self.current.tag == .kw_fun) return try self.funDecl(false);
    if (self.current.tag == .kw_pub) return try self.pubDecl();
    if (self.current.tag == .kw_type) return try self.typeDecl();
    if (self.current.tag == .kw_use) return try self.useDecl();
    return null;
}

/// let x i32 = 10  or  mut x i32 = 0
fn letDecl(self: *Parser, mutable: bool) !usize {
    self.advanceRaw(); // consume let/mut
    const name = try self.consumeIdent("p001", "Expected variable name");

    var type_annot: ?usize = null;
    if (!self.check(.eq) and !self.check(.newline) and !self.check(.eof)) {
        type_annot = try self.parsePrecedence(.primary);
    }

    var value: ?usize = null;
    if (self.check(.eq)) {
        self.advanceRaw(); // consume =
        value = try self.expression();
    }

    return self.arena.add(.{ .let_stmt = .{
        .mutable = mutable,
        .name = name,
        .type_annot = type_annot,
        .value = value,
    } });
}

/// fun name(params) retType  or  pub fun name(params) retType
fn funDecl(self: *Parser, public: bool) !usize {
    self.advanceRaw(); // consume fun
    const name = try self.consumeIdent("p001", "Expected function name");

    try self.consume(.lparen, "p001", "Expected '('");
    var params = std.ArrayList(ast.Param).empty;
    if (!self.check(.rparen)) {
        while (true) {
            const pname = try self.consumeIdent("p001", "Expected parameter name");
            var ptype: ?usize = null;
            if (!self.check(.comma) and !self.check(.rparen)) {
                ptype = try self.parsePrecedence(.primary);
            }
            try params.append(self.allocator, .{ .name = pname, .type_annot = ptype });
            if (!self.check(.comma)) break;
            self.advanceRaw(); // consume comma
        }
    }
    try self.consume(.rparen, "p001", "Expected ')'");

    var ret_type: ?usize = null;
    if (!self.check(.newline) and !self.check(.indent)) {
        ret_type = try self.parsePrecedence(.primary);
    }

    const body = try self.block();
    return self.arena.add(.{ .fun_stmt = .{
        .public = public,
        .name = name,
        .params = try params.toOwnedSlice(self.allocator),
        .ret_type = ret_type,
        .body = body,
    } });
}

/// pub fun ...  — public function is only pub-able thing in v0.1
fn pubDecl(self: *Parser) !usize {
    self.advanceRaw(); // consume pub
    if (self.current.tag == .kw_fun) {
        return self.funDecl(true);
    }
    return self.reportError(self.current.line, "'pub' can only be used with 'fun'", .{});
}

/// type Name / field1 type1 / field2 type2
fn typeDecl(self: *Parser) !usize {
    self.advanceRaw(); // consume type
    const name = try self.consumeIdent("p001", "Expected type name");

    // NEWLINE may have been consumed by consumeIdent's advanceRaw
    if (self.check(.newline)) self.advanceRaw();
    try self.consume(.indent, "p001", "Expected indented block for type fields");

    var fields = std.ArrayList(ast.Field).empty;
    while (!self.check(.dedent) and !self.check(.eof)) {
        const fname = try self.consumeIdent("p001", "Expected field name");
        const ftype = try self.parsePrecedence(.primary);
        try fields.append(self.allocator, .{ .name = fname, .type_annot = ftype });
        self.skipNewlines();
    }
    try self.consume(.dedent, "p001", "Expected dedent after type body");

    return self.arena.add(.{ .type_decl = .{
        .name = name,
        .fields = try fields.toOwnedSlice(self.allocator),
    } });
}

/// use module_name
fn useDecl(self: *Parser) !usize {
    self.advanceRaw(); // consume use
    const path = try self.consumeIdent("p001", "Expected module name");
    return self.arena.add(.{ .use_stmt = .{ .path = path } });
}

// ── Statements ──────────────────────────────────────────────────────────────

fn statement(self: *Parser) !usize {
    return switch (self.current.tag) {
        .kw_if => self.ifStmt(false),
        .kw_elif => return self.reportError(self.current.line, "'elif' without 'if'", .{}),
        .kw_else => return self.reportError(self.current.line, "'else' without 'if'", .{}),
        .kw_loop => self.loopStmt(),
        .kw_for => self.forStmt(),
        .kw_continue => self.continueStmt(),
        .kw_esc => self.escStmt(),
        .kw_ret => self.retStmt(),
        else => self.expressionStatement(),
    };
}

/// if cond / body / elif cond / body / else / body
fn ifStmt(self: *Parser, is_elif: bool) !usize {
    if (!is_elif) self.advanceRaw(); // consume if, but not elif (already consumed by recursion)

    const cond = try self.expression();
    const then_body = try self.block();

    var elifs = std.ArrayList(ast.Elif).empty;
    var else_branch: ?usize = null;

    self.skipNewlines();
    while (self.current.tag == .kw_elif) {
        self.advanceRaw(); // consume elif
        const econd = try self.expression();
        const ebody = try self.block();
        try elifs.append(self.allocator, .{ .cond = econd, .body = ebody });
        self.skipNewlines();
    }

    if (self.current.tag == .kw_else) {
        self.advanceRaw(); // consume else
        else_branch = try self.block();
        self.skipNewlines();
    }

    return self.arena.add(.{ .if_stmt = .{
        .cond = cond,
        .then_branch = then_body,
        .elifs = try elifs.toOwnedSlice(self.allocator),
        .else_branch = else_branch,
    } });
}

/// loop / body
fn loopStmt(self: *Parser) !usize {
    self.advanceRaw(); // consume loop
    const body = try self.block();
    return self.arena.add(.{ .loop_stmt = body });
}

/// for var in iterable / body
fn forStmt(self: *Parser) !usize {
    self.advanceRaw(); // consume for
    const var_name = try self.consumeIdent("p001", "Expected loop variable");

    // consume 'in' (parsed as an identifier token)
    const in_tok = try self.consumeIdent("p001", "Expected 'in'");
    if (!std.mem.eql(u8, in_tok, "in")) {
        return self.reportError(self.previous.line, "expected 'in', got '{s}'", .{in_tok});
    }

    const iterable = try self.expression();
    const body = try self.block();

    return self.arena.add(.{ .for_stmt = .{
        .var_name = var_name,
        .iterable = iterable,
        .body = body,
    } });
}

fn continueStmt(self: *Parser) !usize {
    self.advanceRaw(); // consume continue
    return self.arena.add(.continue_stmt);
}

fn escStmt(self: *Parser) !usize {
    self.advanceRaw(); // consume esc
    return self.arena.add(.esc_stmt);
}

/// ret value
fn retStmt(self: *Parser) !usize {
    self.advanceRaw(); // consume ret

    var value: ?usize = null;
    if (!self.check(.newline) and !self.check(.eof) and !self.check(.dedent)) {
        value = try self.expression();
    }
    return self.arena.add(.{ .ret_stmt = value });
}

fn expressionStatement(self: *Parser) !usize {
    const expr = try self.expression();
    // Check for assignment: x = expr
    if (self.check(.eq)) {
        self.advanceRaw(); // consume =
        const val = try self.expression();
        const assign = try self.arena.add(.{ .assign = .{ .target = expr, .value = val } });
        return self.arena.add(.{ .expr_stmt = assign });
    }
    return self.arena.add(.{ .expr_stmt = expr });
}

// ── Block parsing ──────────────────────────────────────────────────────────

fn block(self: *Parser) Error!usize {
    // Expression parsing may have already consumed the newline
    if (self.check(.newline)) {
        self.advanceRaw();
    }
    if (self.check(.indent)) {
        self.advanceRaw();

        var stmts = std.ArrayList(usize).empty;
        self.skipNewlines();
        while (!self.check(.dedent) and !self.check(.eof)) {
            if (try self.declaration()) |stmt| {
                try stmts.append(self.allocator, stmt);
            } else {
                try stmts.append(self.allocator, try self.statement());
            }
            self.skipNewlines();
        }
        try self.consume(.dedent, "p001", "Expected dedent");
        return self.arena.add(.{ .block = try stmts.toOwnedSlice(self.allocator) });
    }
    return self.reportError(self.previous.line, "expected indented block", .{});
}

// ── Expression parsing ─────────────────────────────────────────────────────

fn expression(self: *Parser) !usize {
    return self.parsePrecedence(.assignment);
}

fn parsePrecedence(self: *Parser, prec: Precedence) !usize {
    self.advanceRaw();
    const rule = getRule(self.previous.tag);
    const prefix_fn = rule.prefix orelse {
        return self.reportError(self.previous.line, "expected expression, got '{s}'", .{@tagName(self.previous.tag)});
    };

    var left = prefix_fn(self) catch return error.ParseError;

    while (@intFromEnum(prec) <= @intFromEnum(getRule(self.current.tag).precedence)) {
        self.advanceRaw();
        const infix_rule = getRule(self.previous.tag);
        if (infix_rule.infix) |infix_fn| {
            left = infix_fn(self, left) catch return error.ParseError;
        } else {
            break;
        }
    }

    return left;
}

fn advanceRaw(self: *Parser) void {
    self.previous = self.current;
    while (true) {
        self.current = self.scanner.nextToken();
        if (self.current.tag != .hash and self.current.tag != .err and self.current.tag != .newline) break;
        if (self.current.tag == .err) {
            self.had_error = true;
            const msg = self.current.start;
            if (self.diag) |diag| {
                diag.add(self.allocator, .{
                    .severity = .@"error",
                    .code = "p001",
                    .message = msg,
                    .location = .{ .file = "<source>", .line = self.current.line, .column = 0 },
                }) catch {};
            } else {
                err.printDiagnostic("p001", "Lex Error", msg, self.current.line);
            }
        }
    }
}

fn advance(self: *Parser) void {
    self.previous = self.current;
    while (true) {
        self.current = self.scanner.nextToken();
        if (self.current.tag != .hash and self.current.tag != .err and self.current.tag != .newline) break;
        if (self.current.tag == .err) {
            self.had_error = true;
            const msg = self.current.start;
            if (self.diag) |diag| {
                diag.add(self.allocator, .{
                    .severity = .@"error",
                    .code = "p001",
                    .message = msg,
                    .location = .{ .file = "<source>", .line = self.current.line, .column = 0 },
                }) catch {};
            } else {
                err.printDiagnostic("p001", "Lex Error", msg, self.current.line);
            }
        }
    }
}

fn check(self: *Parser, tag: Token.Tag) bool {
    return self.current.tag == tag;
}

fn consume(self: *Parser, tag: Token.Tag, code: []const u8, msg: []const u8) !void {
    if (self.current.tag == tag) return self.advanceRaw();
    // Detect unexpected EOF — use p002 regardless of expected code
    const actual_code = if (self.current.tag == .eof) "p002" else code;
    return self.errorAtCurrent(actual_code, msg);
}

fn errorAtCurrent(self: *Parser, code: []const u8, msg: []const u8) error{ParseError} {
    return self.errorAt(self.current, code, msg);
}

fn errorAt(self: *Parser, token: Token.Token, code: []const u8, msg: []const u8) error{ParseError} {
    self.had_error = true;
    if (self.diag) |diag| {
        diag.add(self.allocator, .{
            .severity = .@"error",
            .code = code,
            .message = msg,
            .location = .{ .file = "<source>", .line = token.line, .column = 0 },
        }) catch {};
    } else {
        err.printDiagnostic(code, "Parse Error", msg, token.line);
    }
    return error.ParseError;
}

fn reportError(self: *Parser, line: u32, comptime fmt: []const u8, args: anytype) error{ParseError} {
    const msg = std.fmt.allocPrint(self.allocator, fmt, args) catch "parse error";
    return self.errorAt(.{ .tag = .err, .start = "", .line = line }, "p001", msg);
}

fn consumeIdent(self: *Parser, code: []const u8, msg: []const u8) ![]const u8 {
    if (self.current.tag == .ident) {
        const name = self.current.start;
        self.advanceRaw();
        return name;
    }
    // Detect unexpected EOF — use p002 regardless of expected code
    const actual_code = if (self.current.tag == .eof) "p002" else code;
    return self.errorAtCurrent(actual_code, msg);
}

fn getRule(tag: Token.Tag) ParseRule {
    return switch (tag) {
        .lparen => .{ .prefix = &grouping, .infix = &callExpr, .precedence = .call },
        .lbracket => .{ .prefix = &vecLiteral, .infix = &indexExpr, .precedence = .call },
        .minus => .{ .prefix = &unary, .infix = &binary, .precedence = .term },
        .plus => .{ .prefix = null, .infix = &binary, .precedence = .term },
        .slash => .{ .prefix = null, .infix = &binary, .precedence = .factor },
        .star => .{ .prefix = null, .infix = &binary, .precedence = .factor },
        .percent => .{ .prefix = null, .infix = &binary, .precedence = .factor },
        .bang => .{ .prefix = &unary, .infix = null, .precedence = .none },
        .eq_eq => .{ .prefix = null, .infix = &binary, .precedence = .equality },
        .bang_eq => .{ .prefix = null, .infix = &binary, .precedence = .equality },
        .gt => .{ .prefix = null, .infix = &binary, .precedence = .comparison },
        .lt => .{ .prefix = null, .infix = &binary, .precedence = .comparison },
        .gt_eq => .{ .prefix = null, .infix = &binary, .precedence = .comparison },
        .lt_eq => .{ .prefix = null, .infix = &binary, .precedence = .comparison },
        .and_and => .{ .prefix = null, .infix = &binary, .precedence = .and_ },
        .pipe_pipe => .{ .prefix = null, .infix = &binary, .precedence = .or_ },
        .dot => .{ .prefix = null, .infix = &dotExpr, .precedence = .call },
        .question => .{ .prefix = null, .infix = &tryExpr, .precedence = .call },

        .int_literal => .{ .prefix = &number, .infix = null, .precedence = .none },
        .float_literal => .{ .prefix = &number, .infix = null, .precedence = .none },
        .str_literal => .{ .prefix = &string, .infix = null, .precedence = .none },
        .char_literal => .{ .prefix = &literal, .infix = null, .precedence = .none },
        .kw_nil => .{ .prefix = &literal, .infix = null, .precedence = .none },
        .kw_true => .{ .prefix = &literal, .infix = null, .precedence = .none },
        .kw_false => .{ .prefix = &literal, .infix = null, .precedence = .none },
        .ident => .{ .prefix = &variable, .infix = null, .precedence = .none },

        else => .{ .prefix = null, .infix = null, .precedence = .none },
    };
}

// ── Prefix parselets ────────────────────────────────────────────────────────

fn number(self: *Parser) !usize {
    const lexeme = self.previous.start;
    if (self.previous.tag == .int_literal) {
        const val = std.fmt.parseInt(i64, lexeme, 10) catch {
            return self.errorAt(self.previous, "p004", "Invalid integer literal");
        };
        return self.arena.add(.{ .int_lit = val });
    } else {
        const val = std.fmt.parseFloat(f64, lexeme) catch {
            return self.errorAt(self.previous, "p004", "Invalid float literal");
        };
        return self.arena.add(.{ .float_lit = val });
    }
}

fn string(self: *Parser) !usize {
    const lexeme = self.previous.start;
    return self.arena.add(.{ .str_lit = lexeme[1 .. lexeme.len - 1] });
}

fn literal(self: *Parser) !usize {
    return switch (self.previous.tag) {
        .kw_nil => self.arena.add(.nil_lit),
        .kw_true => self.arena.add(.{ .bool_lit = true }),
        .kw_false => self.arena.add(.{ .bool_lit = false }),
        else => error.ParseError,
    };
}

fn variable(self: *Parser) !usize {
    return self.arena.add(.{ .ident = self.previous.start });
}

fn grouping(self: *Parser) !usize {
    const expr = try self.expression();
    try self.consume(.rparen, "p001", "Expected ')'");
    return expr;
}

fn vecLiteral(self: *Parser) !usize {
    var items = std.ArrayList(usize).empty;
    if (!self.check(.rbracket)) {
        while (true) {
            try items.append(self.allocator, try self.expression());
            if (!self.check(.comma)) break;
            self.advanceRaw(); // consume comma
        }
    }
    try self.consume(.rbracket, "p001", "Expected ']'");
    return self.arena.add(.{ .vec_lit = try items.toOwnedSlice(self.allocator) });
}

fn unary(self: *Parser) !usize {
    const op_tag = self.previous.tag;
    const op: ast.UnaryOp = switch (op_tag) {
        .minus => .neg,
        .bang => .not,
        else => return error.ParseError,
    };
    const operand = try self.parsePrecedence(.unary);
    return self.arena.add(.{ .unary = .{ .op = op, .operand = operand } });
}

// ── Infix parselets ──────────────────────────────────────────────────────

fn binary(self: *Parser, left: usize) !usize {
    const op_tag = self.previous.tag;
    const op: ast.BinaryOp = switch (op_tag) {
        .plus => .add,
        .minus => .sub,
        .star => .mul,
        .slash => .div,
        .percent => .mod,
        .eq_eq => .eq,
        .bang_eq => .neq,
        .gt => .gt,
        .lt => .lt,
        .gt_eq => .gte,
        .lt_eq => .lte,
        .and_and => .and_,
        .pipe_pipe => .or_,
        else => return error.ParseError,
    };
    const rule = getRule(op_tag);
    const right = try self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));
    return self.arena.add(.{ .binary = .{ .op = op, .left = left, .right = right } });
}

fn callExpr(self: *Parser, callee: usize) !usize {
    // Check if this is a struct literal: Ident(name: value, ...)
    // Detect by peeking ahead for colon after first identifier
    if (self.isStructLiteral(callee)) {
        return self.structLiteral(callee);
    }

    var args = std.ArrayList(usize).empty;
    if (!self.check(.rparen)) {
        while (true) {
            try args.append(self.allocator, try self.expression());
            if (!self.check(.comma)) break;
            self.advanceRaw();
        }
    }
    try self.consume(.rparen, "p001", "Expected ')'");
    return self.arena.add(.{ .call = .{ .callee = callee, .args = try args.toOwnedSlice(self.allocator) } });
}

fn isStructLiteral(self: *Parser, callee: usize) bool {
    // Heuristic: if callee name starts with uppercase, treat as struct literal
    const callee_node = self.arena.get(callee);
    if (callee_node == .ident) {
        const name = callee_node.ident;
        if (name.len > 0 and name[0] >= 'A' and name[0] <= 'Z') {
            return true;
        }
    }
    return false;
}

fn skipNewlinesAndIndent(self: *Parser) void {
    while (self.check(.newline) or self.check(.indent) or self.check(.dedent)) {
        self.advanceRaw();
    }
}

fn structLiteral(self: *Parser, type_node: usize) !usize {
    const type_name = self.arena.get(type_node).ident;
    var fields = std.ArrayList(ast.NamedArg).empty;

    if (!self.check(.rparen)) {
        while (true) {
            // Skip newlines, indents, and dedents between fields
            self.skipNewlinesAndIndent();
            if (self.check(.rparen)) break;
            const fname = try self.consumeIdent("p001", "Expected field name");
            try self.consume(.colon, "p001", "Expected ':'");
            const val = try self.expression();
            try fields.append(self.allocator, .{ .name = fname, .value = val });
            // After the field, check for end or more fields
            self.skipNewlinesAndIndent();
            if (self.check(.rparen)) break;
            if (self.check(.comma)) {
                self.advanceRaw();
                self.skipNewlinesAndIndent();
            }
            if (self.check(.rparen)) break;
            if (!self.check(.ident)) break;
        }
    }
    self.skipNewlinesAndIndent();
    try self.consume(.rparen, "p001", "Expected ')'");
    return self.arena.add(.{ .struct_lit = .{ .type_name = type_name, .fields = try fields.toOwnedSlice(self.allocator) } });
}

fn dotExpr(self: *Parser, left: usize) !usize {
    // self.current is already the token after the dot (set by the Pratt loop's advanceRaw)
    const field = try self.consumeIdent("p001", "Expected field name");
    return self.arena.add(.{ .field = .{ .object = left, .field_name = field } });
}

fn indexExpr(self: *Parser, left: usize) !usize {
    const idx = try self.expression();
    try self.consume(.rbracket, "p001", "Expected ']'");
    return self.arena.add(.{ .index = .{ .object = left, .idx = idx } });
}

fn tryExpr(self: *Parser, left: usize) !usize {
    // self.current is already past the ? token
    return self.arena.add(.{ .try_expr = left });
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "parser: integer literal" {
    var p = Parser.init(std.testing.allocator, "42");
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    switch (stmt) {
        .expr_stmt => |e| {
            const node = p.arena.get(e);
            try std.testing.expectEqual(@as(i64, 42), node.int_lit);
        },
        else => unreachable,
    }
}

test "parser: simple arithmetic" {
    var p = Parser.init(std.testing.allocator, "2 + 3 * 4");
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    switch (stmt) {
        .expr_stmt => |e| {
            const node = p.arena.get(e);
            switch (node) {
                .binary => |b| {
                    try std.testing.expectEqual(ast.BinaryOp.add, b.op);
                    try std.testing.expectEqual(@as(i64, 2), p.arena.get(b.left).int_lit);
                    const right = p.arena.get(b.right);
                    try std.testing.expectEqual(ast.BinaryOp.mul, right.binary.op);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "parser: function call" {
    var p = Parser.init(std.testing.allocator, "print(42)");
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    switch (stmt) {
        .expr_stmt => |e| {
            const node = p.arena.get(e);
            switch (node) {
                .call => |c| {
                    try std.testing.expectEqualStrings("print", p.arena.get(c.callee).ident);
                    try std.testing.expectEqual(@as(usize, 1), c.args.len);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "parser: let declaration" {
    var p = Parser.init(std.testing.allocator, "let x i32 = 10");
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    switch (stmt) {
        .let_stmt => |l| {
            try std.testing.expect(!l.mutable);
            try std.testing.expectEqualStrings("x", l.name);
            try std.testing.expect(l.value != null);
        },
        else => unreachable,
    }
}

test "parser: if statement" {
    const src =
        \\if x > 10
        \\    print(1)
        \\else
        \\    print(2)
    ;
    var p = Parser.init(std.testing.allocator, src);
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    try std.testing.expect(stmt == .if_stmt);
}

test "parser: loop statement" {
    const src =
        \\loop
        \\    tick()
    ;
    var p = Parser.init(std.testing.allocator, src);
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    try std.testing.expect(stmt == .loop_stmt);
}

test "parser: ret statement" {
    var p = Parser.init(std.testing.allocator, "ret 42");
    defer p.deinit();
    const stmts = try p.parse();
    const stmt = p.arena.get(stmts[0]);
    switch (stmt) {
        .ret_stmt => |v| try std.testing.expect(v != null),
        else => unreachable,
    }
}

test "parser: EOF in consumeIdent remaps to p002" {
    var diag = err.DiagnosticList.init();
    defer diag.deinit(std.testing.allocator);
    var p = Parser.init(std.testing.allocator, "fun");
    p.diag = &diag;
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parse());
    try std.testing.expect(diag.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), diag.items().len);
    try std.testing.expectEqualStrings("p002", diag.items()[0].code);
}

test "parser: EOF in consume remaps to p002" {
    var diag = err.DiagnosticList.init();
    defer diag.deinit(std.testing.allocator);
    var p = Parser.init(std.testing.allocator, "fun foo");
    p.diag = &diag;
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parse());
    try std.testing.expect(diag.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), diag.items().len);
    try std.testing.expectEqualStrings("p002", diag.items()[0].code);
}

test "parser: invalid integer literal produces p004" {
    var diag = err.DiagnosticList.init();
    defer diag.deinit(std.testing.allocator);
    var p = Parser.init(std.testing.allocator, "9999999999999999999");
    p.diag = &diag;
    defer p.deinit();
    try std.testing.expectError(error.ParseError, p.parse());
    try std.testing.expect(diag.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), diag.items().len);
    try std.testing.expectEqualStrings("p004", diag.items()[0].code);
}
