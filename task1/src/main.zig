const std = @import("std");
const Io = std.Io;

pub const FileLines = struct {
    alloc: std.mem.Allocator,
    file_data: []const u8,
    slices: std.ArrayList([]const u8),

    pub fn read(alloc: std.mem.Allocator, io: Io, dir: Io.Dir, filename: []const u8) !FileLines {
        const data = try dir.readFileAlloc(io, filename, alloc, .unlimited);

        var slices: std.ArrayList([]const u8) = .empty;
        var itr = std.mem.splitScalar(u8, data, '\n');
        while (itr.next()) |line| {
            try slices.append(alloc, std.mem.trim(u8, line, "\r"));
        }

        return .{
            .alloc = alloc,
            .file_data = data,
            .slices = slices,
        };
    }

    pub fn deinit(self: *FileLines) void {
        self.alloc.free(self.file_data);
        self.slices.deinit(self.alloc);
    }

    pub fn lines(self: *const FileLines) [][]const u8 {
        return self.slices.items;
    }
};

pub fn main(init: std.process.Init) !void {
    var fl = try FileLines.read(init.gpa, init.io, Io.Dir.cwd(), "data.txt");
    defer fl.deinit();

    var answer: usize = 0;
    var current: usize = 50;

    const size: usize = 100;

    for (fl.lines()) |line| {
        if (line.len == 0) continue;
        if (line[0] == 'L') {
            const number = try std.fmt.parseInt(usize, line[1..], 10);
            current = @mod(current + size - @mod(number, size), size);
        } else if (line[0] == 'R') {
            const number = try std.fmt.parseInt(usize, line[1..], 10);
            current = @mod(current + @mod(number, size), size);
        }
        if (current == 0) {
            answer += 1;
        }
    }
    std.debug.print("answer = {}\n", .{answer});
}
