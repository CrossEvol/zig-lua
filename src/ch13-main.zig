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

/// test13.lua :
// function div0(a, b)
//     if b == 0 then
//         error("DIV BY ZERO !")
//     else
//         return a / b
//     end
// end

// function div1(a, b) return div0(a, b) end
// function div2(a, b) return div1(a, b) end

// ok, result = pcall(div2, 4, 2); print(ok, result)
// ok, err = pcall(div2, 5, 0);    print(ok, err)
// ok, err = pcall(div2, {}, {});  print(ok, err)

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
        try ls.register("next", next);
        try ls.register("pairs", pairs);
        try ls.register("ipairs", iPairs);
        try ls.register("error", @"error");
        try ls.register("pcall", pCall);

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
            std.debug.print("\t", .{});
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

fn next(ls: *LuaState) LuaError!i32 {
    try ls.setTop(2); // create a 2nd argument if there isn't one
    if (try ls.next(1)) {
        return 2;
    } else {
        try ls.pushNil();
        return 1;
    }
}

// function pairs(t)
//     return next, t, nil
// end
fn pairs(ls: *LuaState) LuaError!i32 {
    try ls.pushZigFunction(next); // will return generator,
    try ls.pushValue(1); // state,
    try ls.pushNil();
    return 3;
}

fn iPairs(ls: *LuaState) LuaError!i32 {
    try ls.pushZigFunction(_iParisAux); // iteration function
    try ls.pushValue(1); // state
    try ls.pushInteger(0); // initial value
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
fn _iParisAux(ls: *LuaState) LuaError!i32 {
    const i = ls.toInteger(2) + 1;
    try ls.pushInteger(i);
    if ((try ls.getI(1, i)) == .lua_t_nil) {
        return 1;
    } else {
        return 2;
    }
}

fn @"error"(ls: *LuaState) LuaError!i32 {
    return ls.Error();
}

fn pCall(ls: *LuaState) LuaError!i32 {
    const n_args = ls.getTop() - 1;
    const status = ls.pCall(n_args, -1, 0);
    try ls.pushBoolean(status == .lua_ok);
    ls.insert(1);
    return ls.getTop();
}
