const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig");
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const binchunk = @import("binchunk/root.zig");
const LuaValue = @import("state/root.zig").LuaValue;
const LuaState = @import("state/root.zig").LuaState;
const vm = @import("vm/root.zig");
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const string = []const u8;
const int = i32;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit(); // This checks for leaks.
    const gpa = debug_allocator.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.skip();
    if (args.next()) |filename| {
        var threaded: std.Io.Threaded = .init(gpa, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        const file = try cwd.openFile(io, filename, .{ .mode = .read_only });
        defer file.close(io);
        const stat = try file.stat(io);
        const file_size = stat.size;
        const data = try gpa.alloc(u8, file_size);
        defer gpa.free(data);

        var fr = file.reader(io, data);
        var reader = &fr.interface;
        try reader.readSliceAll(data);

        var ls = try LuaVM.init(gpa);
        defer ls.deinit();

        _ = try ls.load(data, filename, "b");
        try ls.call(0, 0);
    }
}
