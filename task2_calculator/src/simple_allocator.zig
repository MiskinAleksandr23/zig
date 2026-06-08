const std = @import("std");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const max_alignment = @alignOf(std.c.max_align_t);

const Page = struct {
    ptr: [*]u8,
    len: usize,
    next: ?*Page,
};

const Block = struct {
    ptr: [*]u8,
    len: usize,
    used: bool,
    next: ?*Block,
};

pub const SimpleAllocator = struct {
    const Self = @This();

    page_allocator: Allocator = std.heap.page_allocator,
    pages: ?*Page = null,
    blocks: ?*Block = null,
    current_page: ?*Page = null,
    current_used: usize = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        const page_size = std.heap.pageSize();
        const page_alignment = Alignment.fromByteUnits(page_size);

        var block = self.blocks;
        while (block) |node| {
            const next = node.next;
            self.page_allocator.destroy(node);
            block = next;
        }

        var page = self.pages;
        while (page) |node| {
            const next = node.next;
            self.page_allocator.rawFree(node.ptr[0..node.len], page_alignment, @returnAddress());
            self.page_allocator.destroy(node);
            page = next;
        }

        self.* = .{ .page_allocator = self.page_allocator };
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        if (len == 0) return null;
        if (alignment.toByteUnits() > max_alignment) return null;

        var block = self.blocks;
        while (block) |node| {
            if (!node.used and node.len >= len) {
                node.used = true;
                return node.ptr;
            }
            block = node.next;
        }

        return self.allocFresh(len) catch null;
    }

    fn resize(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) bool {
        return false;
    }

    fn remap(_: *anyopaque, _: []u8, _: Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        const block = self.findBlock(memory.ptr) orelse return;
        block.used = false;
    }

    fn findBlock(self: *Self, ptr: [*]u8) ?*Block {
        var block = self.blocks;
        while (block) |node| {
            if (@intFromPtr(node.ptr) == @intFromPtr(ptr)) return node;
            block = node.next;
        }
        return null;
    }

    fn allocFresh(self: *Self, len: usize) Allocator.Error![*]u8 {
        while (true) {
            if (self.current_page == null) try self.addPage(len + max_alignment);

            const page = self.current_page.?;
            const page_start = @intFromPtr(page.ptr);
            const raw_addr = page_start + self.current_used;
            const aligned_addr = std.mem.alignForward(usize, raw_addr, max_alignment);
            const end_addr = aligned_addr + len;

            if (end_addr <= page_start + page.len) {
                self.current_used = end_addr - page_start;

                const ptr: [*]u8 = @ptrFromInt(aligned_addr);
                try self.addBlock(ptr, len);
                return ptr;
            }

            try self.addPage(len + max_alignment);
        }
    }

    fn addPage(self: *Self, min_len: usize) Allocator.Error!void {
        const page_size = std.heap.pageSize();
        const page_alignment = Alignment.fromByteUnits(page_size);
        const len = std.mem.alignForward(usize, @max(min_len, page_size), page_size);

        const ptr = self.page_allocator.rawAlloc(len, page_alignment, @returnAddress()) orelse {
            return error.OutOfMemory;
        };
        errdefer self.page_allocator.rawFree(ptr[0..len], page_alignment, @returnAddress());

        const page = try self.page_allocator.create(Page);
        page.* = .{
            .ptr = ptr,
            .len = len,
            .next = self.pages,
        };

        self.pages = page;
        self.current_page = page;
        self.current_used = 0;
    }

    fn addBlock(self: *Self, ptr: [*]u8, len: usize) Allocator.Error!void {
        const block = try self.page_allocator.create(Block);
        block.* = .{
            .ptr = ptr,
            .len = len,
            .used = true,
            .next = self.blocks,
        };
        self.blocks = block;
    }
};
