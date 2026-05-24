const std = @import("std");

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    gt,
    lt,
    gte,
    lte,
    and_,
    or_,
};

pub const UnaryOp = enum {
    neg,
    not,
};

pub const Param = struct {
    name: []const u8,
    type_annot: ?usize,
};

pub const Field = struct {
    name: []const u8,
    type_annot: usize,
};

pub const Elif = struct {
    cond: usize,
    body: usize,
};

pub const NamedArg = struct {
    name: []const u8,
    value: usize,
};

pub const Node = union(enum) {
    // Statements
    let_stmt: struct {
        mutable: bool,
        name: []const u8,
        type_annot: ?usize,
        value: ?usize,
    },
    fun_stmt: struct {
        public: bool,
        name: []const u8,
        params: []const Param,
        ret_type: ?usize,
        body: usize,
    },
    type_decl: struct {
        name: []const u8,
        fields: []const Field,
    },
    use_stmt: struct {
        path: []const u8,
    },
    expr_stmt: usize,
    ret_stmt: ?usize,
    block: []const usize,

    // Control flow
    if_stmt: struct {
        cond: usize,
        then_branch: usize,
        elifs: []const Elif,
        else_branch: ?usize,
    },
    loop_stmt: usize,
    for_stmt: struct {
        var_name: []const u8,
        iterable: usize,
        body: usize,
    },
    continue_stmt: void,
    esc_stmt: void,

    // Expressions
    binary: struct { op: BinaryOp, left: usize, right: usize },
    unary: struct { op: UnaryOp, operand: usize },
    call: struct { callee: usize, args: []const usize },
    ident: []const u8,
    int_lit: i64,
    float_lit: f64,
    bool_lit: bool,
    str_lit: []const u8,
    char_lit: u21,
    nil_lit: void,
    assign: struct { target: usize, value: usize },
    field: struct { object: usize, field_name: []const u8 },
    index: struct { object: usize, idx: usize },
    try_expr: usize,

    // Type expressions
    type_ident: []const u8,
    type_vec: usize,
    type_map: struct { key: usize, val: usize },
    type_opt: usize,
    type_res: struct { ok: usize, err: usize },

    // Literal construction
    struct_lit: struct { type_name: []const u8, fields: []const NamedArg },
    vec_lit: []const usize,
};

pub const NodeArena = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),

    pub fn init(allocator: std.mem.Allocator) NodeArena {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(Node).empty,
        };
    }

    pub fn deinit(self: *NodeArena) void {
        self.nodes.deinit(self.allocator);
    }

    pub fn add(self: *NodeArena, node: Node) !usize {
        const idx = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        return idx;
    }

    pub fn get(self: *const NodeArena, idx: usize) Node {
        return self.nodes.items[idx];
    }
};
