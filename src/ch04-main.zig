const std = @import("std");
const Allocator = std.mem.Allocator;

const binchunk = @import("binchunk").binchunk;
const Instruction = @import("vm").Instruction;
const LuaState = @import("state").LUaState;
const LuaValue = @import("state").LuaValue;

const string = []const u8;
const int = i32;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit(); // This checks for leaks.
    const gpa = debug_allocator.allocator();

    var lua_state = try LuaState.init(gpa);
    defer lua_state.deinit();

    var ls = &lua_state;
    ls.pushBoolean(true);
    printStack(ls);
    ls.pushInteger(10);
    printStack(ls);
    ls.pushNil();
    printStack(ls);
    ls.pushString("hello");
    printStack(ls);
    ls.pushValue(-4);
    printStack(ls);
    ls.replace(3);
    printStack(ls);
    ls.setTop(6);
    printStack(ls);
    ls.remove(-3);
    printStack(ls);
    ls.setTop(-5);
    printStack(ls);
}

fn printStack(ls: *LuaState) void {
    const top = ls.getTop();
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
                std.debug.print("[\"{s}\"]", .{ls.toString(i)});
            },
            else => {
                std.debug.print("[{s}]", .{ls.typeName(t)});
            },
        }
    }
    std.debug.print("\n", .{});
}
