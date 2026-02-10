const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig");
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaError = @import("api/root.zig").LuaError;
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
        try ls.register("print", print);
        try ls.register("getmetatable", getMetatable);
        try ls.register("setmetatable", setMetatable);

        _ = try ls.load(data, filename, "b");
        try ls.call(0, 0);
    }
}

fn print(ls: *LuaState) LuaError!i32 {
    const n_args = ls.getTop();
    var i: i32 = 1;
    while (i <= n_args) : (i += 1) {
        if (ls.isBoolean(i)) {
            std.debug.print("{}", .{ls.toBoolean(i)});
        } else if (ls.isString(i)) {
            std.debug.print("{s}", .{(try ls.toString(i)).data()});
        } else {
            std.debug.print("{s}", .{ls.typeName(ls.Type(i))});
        }
        if (i < n_args) {
            std.debug.print("\n", .{});
        }
    }
    std.debug.print("\n", .{});
    return 0;
}

fn getMetatable(ls: *LuaState) LuaError!i32 {
    if (!(try ls.GetMetatable(1))) {
        try ls.pushNil();
    }
    return 1;
}

fn setMetatable(ls: *LuaState) LuaError!i32 {
    try ls.SetMetatable(1);
    return 1;
}
