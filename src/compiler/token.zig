const std = @import("std");

pub const Tag = enum(u8) {
    // Keywords (15)
    kw_let,
    kw_mut,
    kw_fun,
    kw_pub,
    kw_if,
    kw_elif,
    kw_else,
    kw_loop,
    kw_for,
    kw_continue,
    kw_esc,
    kw_ret,
    kw_nil,
    kw_use,
    kw_type,

    // Indentation / line
    indent,
    dedent,
    newline,

    // Literal keywords
    kw_true,
    kw_false,
    int_literal,
    float_literal,
    str_literal,
    char_literal,
    ident,

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    bang,
    eq_eq,
    bang_eq,
    gt,
    lt,
    gt_eq,
    lt_eq,
    and_and,
    pipe_pipe,
    eq,

    // Delimiters
    colon,
    comma,
    dot,
    lparen,
    rparen,
    lbracket,
    rbracket,
    question,
    hash,

    eof,
    err,
};

/// A lexical token with its tag, source lexeme, and line number.
pub const Token = struct {
    tag: Tag,
    start: []const u8,
    line: u32,

    /// Return the source text of this token.
    pub fn lexeme(self: Token) []const u8 {
        return self.start;
    }

    /// Format a token for display (implements std.fmt.format). Shows the tag name.
    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.tag)});
    }
};

/// Returns true if the token tag is a keyword.
pub fn isKeyword(tag: Tag) bool {
    return switch (tag) {
        .kw_let,
        .kw_mut,
        .kw_fun,
        .kw_pub,
        .kw_if,
        .kw_elif,
        .kw_else,
        .kw_loop,
        .kw_for,
        .kw_continue,
        .kw_esc,
        .kw_ret,
        .kw_nil,
        .kw_use,
        .kw_type,
        => true,
        else => false,
    };
}

/// Look up a keyword tag by name. Returns null for non-keyword identifiers.
pub fn keywordTag(name: []const u8) ?Tag {
    const k = std.StaticStringMap(Tag).initComptime(.{
        .{ "let", .kw_let },
        .{ "mut", .kw_mut },
        .{ "fun", .kw_fun },
        .{ "pub", .kw_pub },
        .{ "if", .kw_if },
        .{ "elif", .kw_elif },
        .{ "else", .kw_else },
        .{ "loop", .kw_loop },
        .{ "for", .kw_for },
        .{ "continue", .kw_continue },
        .{ "esc", .kw_esc },
        .{ "ret", .kw_ret },
        .{ "nil", .kw_nil },
        .{ "use", .kw_use },
        .{ "type", .kw_type },
        .{ "true", .kw_true },
        .{ "false", .kw_false },
    });
    return k.get(name);
}
