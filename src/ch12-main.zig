const std = @import("std");
const Allocator = std.mem.Allocator;

const api = @import("api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const binchunk = @import("binchunk/root.zig").binchunk;
const LuaValue = @import("state/root.zig").state.LuaValue;
const LuaState = @import("state/root.zig").state.LuaState;
const vm = @import("vm/root.zig").vm;
const Instruction = vm.Instruction;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;

const string = []const u8;
const int = i32;

/// test12.lua :
// t = {a = 1, b = 2, c = 3}
// for k, v in pairs(t) do
//     print(k, v)
// end

// t = {"a", "b", "c"}
// for k, v in ipairs(t) do
//     print(k, v)
// end

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
        ls.register("print", print);
        ls.register("getmetatable", getMetatable);
        ls.register("setmetatable", setMetatable);
        ls.register("next", next);
        ls.register("pairs", pairs);
        ls.register("ipairs", iPairs);

        _ = ls.load(data, filename, "b");
        ls.call(0, 0);
    }
}

fn print(ls: *LuaState) i32 {
    const n_args = ls.getTop();
    var i: i32 = 1;
    while (i <= n_args) : (i += 1) {
        if (ls.isBoolean(i)) {
            std.debug.print("{}", .{ls.toBoolean(i)});
        } else if (ls.isString(i)) {
            std.debug.print("{s}", .{ls.toString(i).data()});
        } else {
            std.debug.print("{s}", .{ls.typeName(ls.Type(i))});
        }
        if (i < n_args) {
            std.debug.print("\t", .{});
        }
    }
    std.debug.print("\n", .{});
    return 0;
}

fn getMetatable(ls: *LuaState) i32 {
    if (!ls.GetMetatable(1)) {
        ls.pushNil();
    }
    return 1;
}

fn setMetatable(ls: *LuaState) i32 {
    ls.SetMetatable(1);
    return 1;
}

fn next(ls: *LuaState) i32 {
    ls.setTop(2); // create a 2nd argument if there isn't one
    if (ls.next(1)) {
        return 2;
    } else {
        ls.pushNil();
        return 1;
    }
}

// function pairs(t)
//     return next, t, nil
// end
fn pairs(ls: *LuaState) i32 {
    ls.pushZigFunction(next); // will return generator,
    ls.pushValue(1); // state,
    ls.pushNil();
    return 3;
}

fn iPairs(ls: *LuaState) i32 {
    ls.pushZigFunction(_iParisAux); // iteration function
    ls.pushValue(1); // state
    ls.pushInteger(0); // initial value
    return 3;
}

// function inext(t, i)
//     local nextIdx = i + 1
//     local nextVal = t[nextIdx]
//     if nextVal == nil then
//         return nil
//     else
//         return nextIdx, nextVal
//     end
// end
fn _iParisAux(ls: *LuaState) i32 {
    const i = ls.toInteger(2) + 1;
    ls.pushInteger(i);
    if (ls.getI(1, i) == .lua_t_nil) {
        return 1;
    } else {
        return 2;
    }
}
