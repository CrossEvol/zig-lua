const std = @import("std");
const Allocator = std.mem.Allocator;

const LuaError = @import("api/root.zig").Api.LuaError;
const binchunk = @import("binchunk/root.zig").binchunk;
const GC = @import("state/gc.zig").GC;
const LuaValue = @import("state/root.zig").state.LuaValue;
const LuaState = @import("state/root.zig").state.LuaState;
const vm = @import("vm/root.zig").vm;
const Instruction = vm.Instruction;

const string = []const u8;
const int = i32;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit(); // This checks for leaks.
    const gpa = debug_allocator.allocator();

    const gc = try gpa.create(GC);
    gc.* = GC.init(gpa);
    defer {
        gc.deinit();
        gpa.destroy(gc);
    }
    var lua_state = try LuaState.init(gpa, gc);
    defer lua_state.deinit(gpa);

    var ls = &lua_state;
    gc.lua_state = ls;

    try ls.pushBoolean(true);
    try printStack(ls);
    try ls.pushInteger(10);
    try printStack(ls);
    try ls.pushNil();
    try printStack(ls);
    try ls.pushString("hello");
    try printStack(ls);
    try ls.pushValue(-4);
    try printStack(ls);
    try ls.replace(3);
    try printStack(ls);
    try ls.setTop(6);
    try printStack(ls);
    try ls.remove(-3);
    try printStack(ls);
    try ls.setTop(-5);
    try printStack(ls);
}

fn printStack(ls: *LuaState) LuaError!void {
    const top = @as(usize, @intCast(ls.getTop()));
    for (1..top + 1) |x| {
        const i: i32 = @intCast(x);
        const t = ls.Type(i);
        switch (t) {
            .lua_t_boolean => {
                std.debug.print("[{}]", .{ls.toBoolean(i)});
            },
            .lua_t_number => {
                std.debug.print("[{d}]", .{ls.toNumber(i)});
            },
            .lua_t_string => {
                std.debug.print("[\"{s}\"]", .{(try ls.toString(i)).data()});
            },
            else => {
                std.debug.print("[{s}]", .{ls.typeName(t)});
            },
        }
    }
    std.debug.print("\n", .{});
}
