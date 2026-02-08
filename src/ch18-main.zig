const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaError = @import("api/root.zig").Api.LuaError;
const binchunk = @import("binchunk/root.zig").binchunk;
const LuaValue = @import("state/root.zig").state.LuaValue;
const LuaState = @import("state/root.zig").state.LuaState;
const vm = @import("vm/root.zig").vm;
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const string = []const u8;
const int = i32;

// ********************************************************************

/// hello_world.lua :
// print("Hello, World!")

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
