const std = @import("std");

pub fn GraphEvaluator(comptime Nodes: []const type) type {
    comptime validateDistinctNodes(Nodes);

    const NodesStorage = @Tuple(Nodes);
    const top_order = comptime topoOrder(Nodes);

    return struct {
        const Self = @This();

        nodes: NodesStorage,

        pub fn init() Self {
            return .{ .nodes = undefined };
        }

        pub fn compute(self: *Self) !void {
            self.initDeps();
            inline for (top_order) |i| {
                try @field(self.nodes, fieldName(i)).compute();
            }
        }

        pub fn get(self: *Self, comptime NodePtr: type) NodePtr {
            self.initDeps();
            return self.getNoInit(NodePtr);
        }

        fn initDeps(self: *Self) void {
            inline for (Nodes, 0..) |Node, i| {
                if (@hasField(Node, "deps")) {
                    const node = &@field(self.nodes, fieldName(i));
                    inline for (std.meta.fields(@TypeOf(node.deps))) |dep_field| {
                        @field(node.deps, dep_field.name) = self.getNoInit(dep_field.type);
                    }
                }
            }
        }

        fn getNoInit(self: *Self, comptime NodePtr: type) NodePtr {
            const Node = pointerChild(NodePtr);
            inline for (Nodes, 0..) |Current, i| {
                if (Current == Node) {
                    return &@field(self.nodes, fieldName(i));
                }
            }
            @compileError("node " ++ @typeName(Node) ++ " is not in Nodes");
        }
    };
}

fn validateDistinctNodes(comptime Nodes: []const type) void {
    inline for (Nodes, 0..) |Node, i| {
        inline for (Nodes, 0..) |Other, j| {
            if (i < j and Node == Other) {
                @compileError("Error: Duplicate Node Type " ++ @typeName(Node));
            }
        }
    }
}

fn topoOrder(comptime Nodes: []const type) [Nodes.len]usize {
    comptime var visited = [_]bool{false} ** Nodes.len;
    comptime var visiting = [_]bool{false} ** Nodes.len;
    comptime var order: [Nodes.len]usize = undefined;
    comptime var count: usize = 0;

    comptime var i = Nodes.len;
    while (i > 0) {
        i -= 1;
        visitNode(Nodes, i, &visited, &visiting, &order, &count);
    }

    return order;
}

fn visitNode(
    comptime Nodes: []const type,
    comptime i: usize,
    comptime visited: *[Nodes.len]bool,
    comptime visiting: *[Nodes.len]bool,
    comptime order: *[Nodes.len]usize,
    comptime count: *usize,
) void {
    if (visited.*[i]) {
        return;
    }

    if (visiting.*[i]) {
        @compileError("Error: Cycle dependency");
    }

    visiting.*[i] = true;

    const Node = Nodes[i];
    if (@hasField(Node, "deps")) {
        const Deps = @TypeOf(@as(Node, undefined).deps);
        inline for (std.meta.fields(Deps)) |field| {
            const DepNode = pointerChild(field.type);
            const dep_i = nodeIndex(Nodes, DepNode) orelse {
                @compileError("Dependency " ++ @typeName(DepNode) ++ " is not in Nodes");
            };

            visitNode(Nodes, dep_i, visited, visiting, order, count);
        }
    }

    visiting.*[i] = false;
    visited.*[i] = true;
    order.*[count.*] = i;
    count.* += 1;
}

fn nodeIndex(comptime Nodes: []const type, comptime Node: type) ?usize {
    inline for (Nodes, 0..) |Current, i| {
        if (Current == Node) {
            return i;
        }
    }
    return null;
}

fn pointerChild(comptime Ptr: type) type {
    const info = @typeInfo(Ptr);
    if (info != .pointer or info.pointer.size != .one) {
        @compileError("Expected pointer to node, got " ++ @typeName(Ptr));
    }
    return info.pointer.child;
}

fn fieldName(comptime i: usize) []const u8 {
    return std.fmt.comptimePrint("{d}", .{i});
}

pub fn main() !void {}

var compute_order: [16]u8 = undefined;
var compute_order_len: usize = 0;

fn push(letter: u8) void {
    compute_order[compute_order_len] = letter;
    compute_order_len += 1;
}

const A = struct {
    const Self = @This();

    pub fn compute(_: *Self) !void {
        push('A');
    }
};

const B = struct {
    const Self = @This();

    pub fn compute(_: *Self) !void {
        push('B');
    }
};

const C = struct {
    const Self = @This();

    deps: struct {
        a: *A,
        b: *B,
    },

    pub fn compute(self: *Self) !void {
        _ = self;
        push('C');
    }
};

const D = struct {
    const Self = @This();

    deps: struct {
        b: *B,
    },

    pub fn compute(self: *Self) !void {
        _ = self;
        push('D');
    }
};

const E = struct {
    const Self = @This();

    deps: struct {
        c: *C,
        d: *D,
    },

    pub fn compute(self: *Self) !void {
        _ = self;
        push('E');
    }
};

test "Sorted graph" {
    compute_order_len = 0;

    const Evaluator = GraphEvaluator(&.{ D, A, B, E, C });
    var evaluator = Evaluator.init();
    try evaluator.compute();

    try std.testing.expectEqualStrings("ABCDE", compute_order[0..compute_order_len]);
}

test "Init fills deps and get returns node pointer" {
    const Evaluator = GraphEvaluator(&.{ E, D, C, B, A });
    var evaluator = Evaluator.init();

    const d = evaluator.get(*D);
    try std.testing.expect(d.deps.b == evaluator.get(*B));

    const e = evaluator.get(*E);
    try std.testing.expect(e.deps.c == evaluator.get(*C));
    try std.testing.expect(e.deps.d == evaluator.get(*D));
}
