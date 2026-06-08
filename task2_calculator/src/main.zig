const std = @import("std");
const SimpleAllocator = @import("simple_allocator.zig").SimpleAllocator;

pub const Context = std.StringHashMap(f32);

pub const INode = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        eval: *const fn (*const anyopaque, *const Context) f32,
    };

    pub fn eval(self: INode, context: *const Context) f32 {
        return self.vtable.eval(self.ptr, context);
    }
};

pub const Token = union(enum) {
    value: f32,
    plus,
    sub,
    mul,
    sqrt,
    var_name: []const u8,
};

pub const Error = std.mem.Allocator.Error || error{InvalidExpression};

const BinaryOp = enum { plus, sub, mul };

const NumberNode = struct {
    value: f32,

    fn node(self: *const NumberNode) INode {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn eval(self_opaque: *const anyopaque, context: *const Context) f32 {
        _ = context;
        const self: *const NumberNode = @ptrCast(@alignCast(self_opaque));
        return self.value;
    }

    const vtable = INode.VTable{ .eval = eval };
};

const VarNode = struct {
    name: []const u8,

    fn node(self: *const VarNode) INode {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn eval(self_opaque: *const anyopaque, context: *const Context) f32 {
        const self: *const VarNode = @ptrCast(@alignCast(self_opaque));
        return context.get(self.name) orelse 0;
    }

    const vtable = INode.VTable{ .eval = eval };
};

const BinaryNode = struct {
    op: BinaryOp,
    left: INode,
    right: INode,

    fn node(self: *const BinaryNode) INode {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn eval(self_opaque: *const anyopaque, context: *const Context) f32 {
        const self: *const BinaryNode = @ptrCast(@alignCast(self_opaque));
        const left = self.left.eval(context);
        const right = self.right.eval(context);

        return switch (self.op) {
            .plus => left + right,
            .sub => left - right,
            .mul => left * right,
        };
    }

    const vtable = INode.VTable{ .eval = eval };
};

const SqrtNode = struct {
    child: INode,

    fn node(self: *const SqrtNode) INode {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn eval(self_opaque: *const anyopaque, context: *const Context) f32 {
        const self: *const SqrtNode = @ptrCast(@alignCast(self_opaque));
        return @sqrt(self.child.eval(context));
    }

    const vtable = INode.VTable{ .eval = eval };
};

pub const Tree = struct {
    arena: std.heap.ArenaAllocator,
    root: INode,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Error!Tree {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var idx: usize = 0;
        const root = try createNode(arena.allocator(), tokens, &idx);
        if (idx != tokens.len) return error.InvalidExpression;

        return .{ .arena = arena, .root = root };
    }

    pub fn deinit(self: *Tree) void {
        self.arena.deinit();
    }

    pub fn eval(self: *const Tree, context: *const Context) f32 {
        return self.root.eval(context);
    }

    fn createNode(allocator: std.mem.Allocator, tokens: []const Token, idx: *usize) Error!INode {
        if (idx.* >= tokens.len) return error.InvalidExpression;

        const token = tokens[idx.*];
        idx.* += 1;

        return switch (token) {
            .value => |value| blk: {
                const node = try allocator.create(NumberNode);
                node.* = .{ .value = value };
                break :blk node.node();
            },
            .var_name => |name| blk: {
                const node = try allocator.create(VarNode);
                node.* = .{ .name = name };
                break :blk node.node();
            },
            .plus => blk: {
                const left = try createNode(allocator, tokens, idx);
                const right = try createNode(allocator, tokens, idx);
                const node = try allocator.create(BinaryNode);
                node.* = .{
                    .op = .plus,
                    .left = left,
                    .right = right,
                };
                break :blk node.node();
            },
            .sub => blk: {
                const left = try createNode(allocator, tokens, idx);
                const right = try createNode(allocator, tokens, idx);
                const node = try allocator.create(BinaryNode);
                node.* = .{
                    .op = .sub,
                    .left = left,
                    .right = right,
                };
                break :blk node.node();
            },
            .mul => blk: {
                const left = try createNode(allocator, tokens, idx);
                const right = try createNode(allocator, tokens, idx);
                const node = try allocator.create(BinaryNode);
                node.* = .{
                    .op = .mul,
                    .left = left,
                    .right = right,
                };
                break :blk node.node();
            },
            .sqrt => blk: {
                const child = try createNode(allocator, tokens, idx);
                const node = try allocator.create(SqrtNode);
                node.* = .{ .child = child };
                break :blk node.node();
            },
        };
    }
};

pub fn createTree(allocator: std.mem.Allocator, tokens: []const Token) Error!Tree {
    return Tree.init(allocator, tokens);
}

pub fn parseExpression(allocator: std.mem.Allocator, expression: []const u8) Error!Tree {
    var tokens: std.ArrayList(Token) = .empty;
    defer tokens.deinit(allocator);

    var it = std.mem.splitScalar(u8, expression, ' ');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        try tokens.append(allocator, try parseToken(part));
    }

    return createTree(allocator, tokens.items);
}

fn parseToken(part: []const u8) Error!Token {
    if (std.mem.eql(u8, part, "+"))
        return .plus;
    if (std.mem.eql(u8, part, "-"))
        return .sub;
    if (std.mem.eql(u8, part, "*"))
        return .mul;
    if (std.mem.eql(u8, part, "sqrt"))
        return .sqrt;

    const value = std.fmt.parseFloat(f32, part) catch return .{ .var_name = part };
    return .{ .value = value };
}

pub fn main() !void {}

test "SimpleNoVarsTest" {
    var simple_allocator = SimpleAllocator.init();
    defer simple_allocator.deinit();
    const allocator = simple_allocator.allocator();

    const tokens = [_]Token{
        .sqrt,
        .sub,
        .mul,
        .{ .value = 3.0 },
        .{ .value = 2.0 },
        .{ .value = 2.0 },
    };

    var tree = try createTree(allocator, &tokens);
    defer tree.deinit();

    var context = Context.init(allocator);
    defer context.deinit();

    try std.testing.expectEqual(@as(f32, 2.0), tree.eval(&context));
}

test "SimpleTestWithVars" {
    var simple_allocator = SimpleAllocator.init();
    defer simple_allocator.deinit();
    const allocator = simple_allocator.allocator();

    const tokens = [_]Token{
        .sub,
        .plus,
        .{ .var_name = "x" },
        .{ .var_name = "y" },
        .{ .var_name = "z" },
    };

    var tree = try createTree(allocator, &tokens);
    defer tree.deinit();

    var context = Context.init(allocator);
    defer context.deinit();

    try context.put("x", 1.0);
    try context.put("y", 2.0);
    try context.put("z", 100.5);

    try std.testing.expectEqual(@as(f32, -97.5), tree.eval(&context));
}

test "Large [+ - + - + - ... x x x x x x] Test" {
    var simple_allocator = SimpleAllocator.init();
    defer simple_allocator.deinit();
    const allocator = simple_allocator.allocator();

    const iterations: usize = 1000;
    var tokens: [2 * iterations - 1]Token = undefined;

    for (0..iterations - 1) |idx| {
        if ((idx & 1) == 0) {
            tokens[idx] = .plus;
        } else {
            tokens[idx] = .sub;
        }
    }

    for (iterations - 1..2 * iterations - 1) |idx| {
        tokens[idx] = .{ .var_name = "x" };
    }

    var tree = try createTree(allocator, &tokens);
    defer tree.deinit();

    var context = Context.init(allocator);
    defer context.deinit();

    try context.put("x", 1.0);
    try std.testing.expectEqual(@as(f32, 2.0), tree.eval(&context));
}
