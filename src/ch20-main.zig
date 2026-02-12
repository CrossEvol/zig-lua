const std = @import("std");
const Allocator = std.mem.Allocator;

const vm = @import("vm/root.zig");
const LuaVM = vm.LuaVM;

// ********************************************************************

/// test20.lua :

// ********************************************************************

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit(); // This checks for leaks.
    const gpa = debug_allocator.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.skip();
    if (args.next()) |filename| {
        var ls = try LuaVM.init(gpa);
        defer ls.deinit();
        try ls.openLibs();
        _ = try ls.loadFile(filename);
        try ls.call(0, -1);
    }
}
