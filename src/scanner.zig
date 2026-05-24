const std = @import("std");
const Token = @import("token.zig");

const Scanner = @This();

allocator: std.mem.Allocator,
source: []const u8,
start: usize,
current: usize,
line: u32,
indent_stack: std.ArrayList(u32),
pending_tokens: std.ArrayList(Token.Token),
in_line: bool,

pub fn init(allocator: std.mem.Allocator, source: []const u8) Scanner {
    var stack = std.ArrayList(u32).empty;
    stack.append(allocator, 0) catch @panic("OOM");
    return .{
        .allocator = allocator,
        .source = source,
        .start = 0,
        .current = 0,
        .line = 1,
        .indent_stack = stack,
        .pending_tokens = std.ArrayList(Token.Token).empty,
        .in_line = false,
    };
}

pub fn deinit(self: *Scanner) void {
    self.indent_stack.deinit(self.allocator);
    self.pending_tokens.deinit(self.allocator);
}

pub fn nextToken(self: *Scanner) Token.Token {
    if (self.pending_tokens.items.len > 0) {
        const tok = self.pending_tokens.orderedRemove(0);
        return tok;
    }

    if (isAtEnd(self)) {
        if (self.indent_stack.items.len > 1) {
            _ = self.indent_stack.pop();
            return makeToken(self, .dedent, "");
        }
        return makeToken(self, .eof, "");
    }

    if (!self.in_line) {
        return handleIndent(self);
    }

    skipSpaces(self);
    self.start = self.current;

    if (isAtEnd(self)) {
        self.in_line = false;
        return makeToken(self, .newline, "");
    }

    const c = advance(self);
    switch (c) {
        '\n' => {
            self.in_line = false;
            return makeToken(self, .newline, "");
        },
        '(' => return makeToken(self, .lparen, ""),
        ')' => return makeToken(self, .rparen, ""),
        '[' => return makeToken(self, .lbracket, ""),
        ']' => return makeToken(self, .rbracket, ""),
        ',' => return makeToken(self, .comma, ""),
        ':' => return makeToken(self, .colon, ""),
        '.' => return makeToken(self, .dot, ""),
        '?' => return makeToken(self, .question, ""),
        '+' => return makeToken(self, .plus, ""),
        '-' => return makeToken(self, .minus, ""),
        '*' => return makeToken(self, .star, ""),
        '/' => return makeToken(self, .slash, ""),
        '%' => return makeToken(self, .percent, ""),
        '!' => {
            if (match(self, '=')) return makeToken(self, .bang_eq, "");
            return makeToken(self, .bang, "");
        },
        '=' => {
            if (match(self, '=')) return makeToken(self, .eq_eq, "");
            return makeToken(self, .eq, "");
        },
        '>' => {
            if (match(self, '=')) return makeToken(self, .gt_eq, "");
            return makeToken(self, .gt, "");
        },
        '<' => {
            if (match(self, '=')) return makeToken(self, .lt_eq, "");
            return makeToken(self, .lt, "");
        },
        '&' => {
            if (match(self, '&')) return makeToken(self, .and_and, "");
            return makeToken(self, .err, "Expected '&&'");
        },
        '|' => {
            if (match(self, '|')) return makeToken(self, .pipe_pipe, "");
            return makeToken(self, .err, "Expected '||'");
        },
        '#' => {
            while (peek(self) != '\n' and !isAtEnd(self)) {
                _ = advance(self);
            }
            return makeToken(self, .hash, "");
        },
        '"' => return string(self),
        '\'' => return charLit(self),
        '0'...'9' => return number(self),
        else => {
            if (isAlpha(c)) return identifier(self);
            return makeToken(self, .err, "Unexpected character");
        },
    }
}

fn handleIndent(self: *Scanner) Token.Token {
    const col = countLeadingSpaces(self);

    if (col == 0xFFFF_FFFF) {
        skipLine(self);
        return nextToken(self);
    }

    // indent_stack always has at least one entry (base 0)
    const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];

    if (col > current_indent) {
        self.indent_stack.append(self.allocator, col) catch @panic("OOM");
        self.in_line = true;
        self.start = self.current;
        return makeToken(self, .indent, "");
    } else if (col < current_indent) {
        while (self.indent_stack.items.len > 1 and
            self.indent_stack.items[self.indent_stack.items.len - 1] > col)
        {
            _ = self.indent_stack.pop();
            self.pending_tokens.append(self.allocator, makeToken(self, .dedent, "")) catch @panic("OOM");
        }
        if (self.indent_stack.items[self.indent_stack.items.len - 1] != col) {
            return makeToken(self, .err, "Inconsistent indentation");
        }
        self.in_line = true;
        self.start = self.current;
        return self.pending_tokens.orderedRemove(0);
    } else {
        self.in_line = true;
        self.start = self.current;
        skipSpaces(self);
        self.start = self.current;
        return nextToken(self);
    }
}

fn countLeadingSpaces(self: *Scanner) u32 {
    var count: u32 = 0;
    while (!isAtEnd(self) and peek(self) != '\n') {
        const c = peek(self);
        if (c == ' ') {
            count += 1;
        } else if (c == '\t') {
            count += 4;
        } else if (c == '#') {
            return 0xFFFF_FFFF;
        } else {
            return count;
        }
        _ = advance(self);
    }
    if (peek(self) == '\n') {
        return 0xFFFF_FFFF;
    }
    return count;
}

fn skipLine(self: *Scanner) void {
    while (!isAtEnd(self) and peek(self) != '\n') {
        _ = advance(self);
    }
    if (!isAtEnd(self) and peek(self) == '\n') {
        _ = advance(self);
        self.line += 1;
    }
}

fn skipSpaces(self: *Scanner) void {
    while (!isAtEnd(self)) {
        switch (peek(self)) {
            ' ', '\r', '\t' => _ = advance(self),
            else => return,
        }
    }
}

fn string(self: *Scanner) Token.Token {
    while (peek(self) != '"' and !isAtEnd(self)) {
        if (peek(self) == '\n') self.line += 1;
        _ = advance(self);
    }
    if (isAtEnd(self)) return makeToken(self, .err, "Unterminated string");
    _ = advance(self);
    return makeToken(self, .str_literal, "");
}

fn charLit(self: *Scanner) Token.Token {
    if (isAtEnd(self)) return makeToken(self, .err, "Unterminated char literal");
    _ = advance(self);
    if (match(self, '\'')) {
        return makeToken(self, .char_literal, "");
    }
    if (peek(self) == '\'') {
        _ = advance(self);
        _ = advance(self);
        return makeToken(self, .char_literal, "");
    }
    return makeToken(self, .err, "Unterminated char literal");
}

fn number(self: *Scanner) Token.Token {
    while (isDigit(peek(self))) _ = advance(self);
    if (peek(self) == '.' and isDigit(peekNext(self))) {
        _ = advance(self);
        while (isDigit(peek(self))) _ = advance(self);
        return makeToken(self, .float_literal, "");
    }
    return makeToken(self, .int_literal, "");
}

fn identifier(self: *Scanner) Token.Token {
    while (isAlpha(peek(self)) or isDigit(peek(self))) _ = advance(self);
    const name = self.source[self.start..self.current];
    if (Token.keywordTag(name)) |kw| {
        return makeToken(self, kw, "");
    }
    return makeToken(self, .ident, "");
}

fn makeToken(self: *Scanner, tag: Token.Tag, err_msg: []const u8) Token.Token {
    return .{
        .tag = tag,
        .start = if (tag == .err) err_msg else self.source[self.start..self.current],
        .line = self.line,
    };
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

fn peek(self: *Scanner) u8 {
    if (isAtEnd(self)) return 0;
    return self.source[self.current];
}

fn peekNext(self: *Scanner) u8 {
    if (self.current + 1 >= self.source.len) return 0;
    return self.source[self.current + 1];
}

fn advance(self: *Scanner) u8 {
    const c = self.source[self.current];
    self.current += 1;
    return c;
}

fn match(self: *Scanner, expected: u8) bool {
    if (isAtEnd(self)) return false;
    if (self.source[self.current] != expected) return false;
    self.current += 1;
    return true;
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "scanner: single token" {
    var s = Scanner.init(std.testing.allocator, "let");
    defer s.deinit();
    const tok = s.nextToken();
    try std.testing.expectEqual(Token.Tag.kw_let, tok.tag);
    try std.testing.expectEqual(Token.Tag.eof, s.nextToken().tag);
}

test "scanner: arithmetic expression" {
    var s = Scanner.init(std.testing.allocator, "2 + 3 * 4");
    defer s.deinit();
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.plus, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.star, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.newline, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.eof, s.nextToken().tag);
}

test "scanner: indentation block" {
    const src =
        \\if x
        \\    print(1)
        \\    print(2)
        \\print(3)
    ;
    var s = Scanner.init(std.testing.allocator, src);
    defer s.deinit();

    try std.testing.expectEqual(Token.Tag.kw_if, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.ident, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.newline, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.indent, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.ident, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.lparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.rparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.newline, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.ident, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.lparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.rparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.newline, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.dedent, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.ident, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.lparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.int_literal, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.rparen, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.newline, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.dedent, s.nextToken().tag);
    try std.testing.expectEqual(Token.Tag.eof, s.nextToken().tag);
}

test "scanner: all keywords" {
    const keywords = [_]Token.Tag{
        .kw_let, .kw_mut, .kw_fun, .kw_pub,
        .kw_if, .kw_elif, .kw_else, .kw_loop, .kw_for,
        .kw_continue, .kw_esc, .kw_ret, .kw_nil, .kw_use, .kw_type,
    };
    for (keywords) |kw| {
        const name = @tagName(kw)["kw_".len..];
        var s = Scanner.init(std.testing.allocator, name);
        defer s.deinit();
        const tok = s.nextToken();
        try std.testing.expectEqual(kw, tok.tag);
    }
}

test "scanner: string literal" {
    var s = Scanner.init(std.testing.allocator, "\"hello\"");
    defer s.deinit();
    const tok = s.nextToken();
    try std.testing.expectEqual(Token.Tag.str_literal, tok.tag);
}

test "scanner: comment line produces no tokens" {
    var s = Scanner.init(std.testing.allocator, "# this is a comment\n42");
    defer s.deinit();
    const tok = s.nextToken();
    try std.testing.expectEqual(Token.Tag.int_literal, tok.tag);
}

test "scanner: operators" {
    var s = Scanner.init(std.testing.allocator, "+ - * / % == != > < >= <= && || =");
    defer s.deinit();
    const expected = [_]Token.Tag{
        .plus, .minus, .star, .slash, .percent,
        .eq_eq, .bang_eq, .gt, .lt, .gt_eq, .lt_eq,
        .and_and, .pipe_pipe, .eq,
    };
    for (expected) |tag| {
        try std.testing.expectEqual(tag, s.nextToken().tag);
    }
}

test "scanner: float literal" {
    var s = Scanner.init(std.testing.allocator, "3.14");
    defer s.deinit();
    const tok = s.nextToken();
    try std.testing.expectEqual(Token.Tag.float_literal, tok.tag);
}

