const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig");
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaError = @import("api/root.zig").LuaError;
const binchunk = @import("binchunk/root.zig");
const GC = @import("state/gc.zig").GC;
const LuaValue = @import("state/root.zig").LuaValue;
const LuaState = @import("state/root.zig").LuaState;
const vm = @import("vm/root.zig");
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

    try ls.pushInteger(1);
    try ls.pushString("2.0");
    try ls.pushString("3.0");
    try ls.pushNumber(4.0);
    try printStack(ls);

    try ls.arith(ArithOp.lua_op_add);
    try printStack(ls);
    try ls.arith(ArithOp.lua_op_bnot);
    try printStack(ls);
    try ls.len(2);
    try printStack(ls);
    try ls.concat(ls.allocator, 3);
    try printStack(ls);
    try ls.pushBoolean(try ls.compare(1, 2, CompareOp.lua_op_eq));
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
