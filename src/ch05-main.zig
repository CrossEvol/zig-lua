const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
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
                std.debug.print("[\"{s}\"]", .{ls.toString(i).data()});
            },
            else => {
                std.debug.print("[{s}]", .{ls.typeName(t)});
            },
        }
    }
    std.debug.print("\n", .{});
}
