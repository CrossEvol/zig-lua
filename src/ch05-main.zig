const std = @import("std");
const Allocator = std.mem.Allocator;

const apiNSP = @import("api");
const ArithOp = apiNSP.ArithOp;
const CompareOp = apiNSP.CompareOp;
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
    ls.pushInteger(1);
    ls.pushString("2.0");
    ls.pushString("3.0");
    ls.pushNumber(4.0);
    printStack(ls);

    ls.arith(ArithOp.lua_op_add);
    printStack(ls);
    ls.arith(ArithOp.lua_op_bnot);
    printStack(ls);
    ls.len(2);
    printStack(ls);
    ls.concat(3);
    printStack(ls);
    ls.pushBoolean(ls.compare(1, 2, CompareOp.lua_op_eq));
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
