const std = @import("std");
const Allocator = std.mem.Allocator;

const apiNSP = @import("api");
const ArithOp = apiNSP.ArithOp;
const CompareOp = apiNSP.CompareOp;
const binchunk = @import("binchunk").binchunk;
const Instruction = @import("vm").Instruction;
const LuaState = @import("vm").LuaState;
const LuaValue = @import("binchunk").LuaValueNSP.LuaValue;
const LuaVM = @import("vm").LuaVM;
const OpCode = @import("vm").OpCode;

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

        _ = ls.load(data, filename, "b");
        ls.call(0, 0);
    }
}
