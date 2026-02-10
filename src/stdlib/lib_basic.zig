const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const api = @import("../api/root.zig");
const LUA_MULTRET = api.LUA_MULTRET;
const ThreadStatus = api.ThreadStatus;
const strings = @import("../api/strings.zig");
const ZigFunction = @import("../state/closure.zig").ZigFunction;
const LuaState = @import("../state/root.zig").LuaState;

fn baseFuncImpl(ls: *LuaState) LuaError!i32 {
    _ = ls;
    return LuaError.Panic;
}

var baseFuncs = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "print", basePrint },
        .{ "assert", baseAssert },
        .{ "error", baseError },
        .{ "select", baseSelect },
        .{ "ipairs", baseIPairs },
        .{ "pairs", basePairs },
        .{ "next", baseNext },
        .{ "load", baseLoad },
        .{ "loadfile", baseLoadFile },
        .{ "dofile", baseDoFile },
        .{ "pcall", basePCall },
        .{ "xpcall", baseXPCall },
        .{ "getmetatable", baseGetMetatable },
        .{ "setmetatable", baseSetMetatable },
        .{ "rawequal", baseRawEqual },
        .{ "rawlen", baseRawLen },
        .{ "rawget", baseRawGet },
        .{ "rawset", baseRawSet },
        .{ "type", baseType },
        .{ "tostring", baseToString },
        .{ "tonumber", baseToNumber },
        // placeholders
        .{ "_G", baseFuncImpl }, // null
        .{ "_VERSION", baseFuncImpl }, // null
    },
);

// lua-5.3.4/src/lbaselib.c#luaopen_base()
pub fn openBaseLib(ls: *LuaState) LuaError!i32 {
    // open lib into global table
    try ls.pushGlobalTable();
    try ls.setFuncs(baseFuncs, 0);
    // set global _G
    try ls.pushValue(-1);
    try ls.setField(-2, "_G");
    // set global _VERSION
    try ls.pushString("Lua 5.3");
    try ls.setField(-2, "_VERSION");
    return 1;
}

// print (···)
// http://www.lua.org/manual/5.3/manual.html#pdf-print
// lua-5.3.4/src/lbaselib.c#luaB_print()
fn basePrint(ls: *LuaState) LuaError!i32 {
    const n = @as(usize, @intCast(ls.getTop())); // number of arguments
    _ = try ls.getGlobal("tostring");
    for (1..n + 1) |i| {
        try ls.pushValue(-1); // function to be called
        try ls.pushValue(@intCast(i)); // value to print
        try ls.call(1, 1);
        const s, const ok = try ls.toStringX(ls.allocator, -1); // get result
        if (!ok) {
            return ls.error2("'tostring' must return a string to 'print'", .{});
        }
        if (i > 1) {
            std.debug.print("\t", .{});
        }
        std.debug.print("{s}", .{s.bytes});
        try ls.pop(1);
    }
    std.debug.print("\n", .{});
    return 0;
}

// assert (v [, message])
// http://www.lua.org/manual/5.3/manual.html#pdf-assert
// lua-5.3.4/src/lbaselib.c#luaB_assert()
fn baseAssert(ls: *LuaState) LuaError!i32 {
    if (ls.toBoolean(1)) { // condition is true?
        return ls.getTop(); // return all arguments
    } else { // error
        try ls.checkAny(1); // there must be a condition
        try ls.remove(1); // remove it
        try ls.pushString("assertion failed!"); // default message
        try ls.setTop(1); // leave only message (default if no other one)
        return baseError(ls); // call 'error'
    }
}

// error (message [, level])
// http://www.lua.org/manual/5.3/manual.html#pdf-error
// lua-5.3.4/src/lbaselib.c#luaB_error()
fn baseError(ls: *LuaState) LuaError!i32 {
    const level = try ls.optInteger(2, 1);
    try ls.setTop(1);
    if (ls.Type(1) == .lua_t_string and level > 0) {
        // ls.Where(level) /* add extra information */
        // ls.PushValue(1)
        // ls.Concat(2)
    }
    return ls.Error();
}

// select (index, ···)
// http://www.lua.org/manual/5.3/manual.html#pdf-select
// lua-5.3.4/src/lbaselib.c#luaB_select()
fn baseSelect(ls: *LuaState) LuaError!i32 {
    const n = @as(i64, @intCast(ls.getTop()));
    if (ls.Type(1) == .lua_t_string and std.mem.eql(u8, try ls.checkString(1), "#")) {
        try ls.pushInteger(n - 1);
        return 1;
    } else {
        var i = try ls.checkInteger(1);
        if (i < 0) {
            i = n + i;
        } else if (i > n) {
            i = n;
        }
        try ls.argCheck(1 <= i, 1, "index out of range");
        return @intCast(n - i);
    }
}

// ipairs (t)
// http://www.lua.org/manual/5.3/manual.html#pdf-ipairs
// lua-5.3.4/src/lbaselib.c#luaB_ipairs()
fn baseIPairs(ls: *LuaState) LuaError!i32 {
    try ls.checkAny(1);
    try ls.pushZigFunction(iPairsAux); // iteration function
    try ls.pushValue(1); // state
    try ls.pushInteger(0); // initial value
    return 3;
}

// lua-5.3.4/src/lbaselib.c#luaopen_base()
fn iPairsAux(ls: *LuaState) LuaError!i32 {
    const i = (try ls.checkInteger(2)) + 1;
    try ls.pushInteger(i);
    if ((try ls.getI(1, i)) == .lua_t_nil) {
        return 1;
    } else {
        return 2;
    }
}

// pairs (t)
// http://www.lua.org/manual/5.3/manual.html#pdf-pairs
// lua-5.3.4/src/lbaselib.c#luaB_pairs()
fn basePairs(ls: *LuaState) LuaError!i32 {
    try ls.checkAny(1);
    if (try ls.GetMetafield(1, "__pairs") == .lua_t_nil) { // no metamethod?
        try ls.pushZigFunction(baseNext); // will return generator,
        try ls.pushValue(1); // state,
        try ls.pushNil();
    } else {
        try ls.pushValue(1); // argument 'self' to metamethod
        try ls.call(1, 3); // get 3 values from metamethod
    }
    return 3;
}

// next (table [, index])
// http://www.lua.org/manual/5.3/manual.html#pdf-next
// lua-5.3.4/src/lbaselib.c#luaB_next()
fn baseNext(ls: *LuaState) LuaError!i32 {
    try ls.checkType(1, .lua_t_table);
    try ls.setTop(2); // create a 2nd argument if there isn't one
    if (try ls.next(1)) {
        return 2;
    } else {
        try ls.pushNil();
        return 1;
    }
}

// load (chunk [, chunkname [, mode [, env]]])
// http://www.lua.org/manual/5.3/manual.html#pdf-load
// lua-5.3.4/src/lbaselib.c#luaB_load()
fn baseLoad(ls: *LuaState) LuaError!i32 {
    var status: ThreadStatus = undefined;
    const chunk, const is_str = try ls.toStringX(ls.allocator, 1);
    const mode = try ls.optString(3, "bt");
    var env: i32 = 0; // 'env' index or 0 if no 'env'
    if (!ls.isNone(4)) {
        env = 4;
    }
    if (is_str) { // loading a string?
        const chunk_name = try ls.optString(2, chunk.bytes);
        status = @enumFromInt(try ls.load(chunk.bytes, chunk_name, mode));
    } else { // loading from a reader function
        std.debug.print("loading from a reader function", .{});
        std.debug.print("\n", .{});
        return LuaError.Panic;
    }
    return try loadAux(ls, status, env);
}

// lua-5.3.4/src/lbaselib.c#load_aux()
fn loadAux(ls: *LuaState, status: ThreadStatus, env_idx: i32) LuaError!i32 {
    if (status == .lua_ok) {
        if (env_idx != 0) { // 'env' parameter?
            @panic("todo!");
        }
        return 1;
    } else { // error (message is on top of the stack)
        try ls.pushNil();
        ls.insert(-2); // put before error message
        return 2; // return nil plus error message
    }
}

// loadfile ([filename [, mode [, env]]])
// http://www.lua.org/manual/5.3/manual.html#pdf-loadfile
// lua-5.3.4/src/lbaselib.c#luaB_loadfile()
fn baseLoadFile(ls: *LuaState) LuaError!i32 {
    const fname = try ls.optString(1, "");
    const mode = try ls.optString(1, "bt");
    var env: i32 = 0;
    if (!ls.isNone(3)) {
        env = 3;
    }
    const status = try ls.loadFileX(fname, mode);
    return try loadAux(ls, status, env);
}

// dofile ([filename])
// http://www.lua.org/manual/5.3/manual.html#pdf-dofile
// lua-5.3.4/src/lbaselib.c#luaB_dofile()
fn baseDoFile(ls: *LuaState) LuaError!i32 {
    const fname = try ls.optString(1, "bt");
    try ls.setTop(1);
    if ((try ls.loadFile(fname)) != .lua_ok) {
        return ls.Error();
    }
    try ls.call(0, LUA_MULTRET);
    return ls.getTop() - 1;
}

// pcall (f [, arg1, ···])
// http://www.lua.org/manual/5.3/manual.html#pdf-pcall
fn basePCall(ls: *LuaState) LuaError!i32 {
    const n_args = ls.getTop() - 1;
    const status = ls.pCall(n_args, -1, 0);
    try ls.pushBoolean(status == .lua_ok);
    ls.insert(1);
    return ls.getTop();
}

// xpcall (f, msgh [, arg1, ···])
// http://www.lua.org/manual/5.3/manual.html#pdf-xpcall
fn baseXPCall(ls: *LuaState) LuaError!i32 {
    _ = ls;
    @panic("todo!");
}

// getmetatable (object)
// http://www.lua.org/manual/5.3/manual.html#pdf-getmetatable
// lua-5.3.4/src/lbaselib.c#luaB_getmetatable()
fn baseGetMetatable(ls: *LuaState) LuaError!i32 {
    try ls.checkAny(1);
    if (!(try ls.GetMetatable(1))) {
        try ls.pushNil();
        return 1; // no metatable
    }
    _ = try ls.GetMetafield(1, "__metatable");
    return 1; // returns either __metatable field (if present) or metatable
}

// setmetatable (table, metatable)
// http://www.lua.org/manual/5.3/manual.html#pdf-setmetatable
// lua-5.3.4/src/lbaselib.c#luaB_setmetatable()
fn baseSetMetatable(ls: *LuaState) LuaError!i32 {
    const t = ls.Type(2);
    try ls.checkType(1, .lua_t_table);
    try ls.argCheck(t == .lua_t_nil or t == .lua_t_table, 2, "nil or table expected");
    if (try ls.GetMetafield(1, "__metatable") != .lua_t_nil) {
        return ls.error2("cannot change a protected metatable", .{});
    }
    try ls.setTop(2);
    try ls.SetMetatable(1);
    return 1;
}

// rawequal (v1, v2)
// http://www.lua.org/manual/5.3/manual.html#pdf-rawequal
// lua-5.3.4/src/lbaselib.c#luaB_rawequal()
fn baseRawEqual(ls: *LuaState) LuaError!i32 {
    try ls.checkAny(1);
    try ls.checkAny(2);
    try ls.pushBoolean(try ls.rawEqual(1, 2));
    return 1;
}

// rawlen (v)
// http://www.lua.org/manual/5.3/manual.html#pdf-rawlen
// lua-5.3.4/src/lbaselib.c#luaB_rawlen()
fn baseRawLen(ls: *LuaState) LuaError!i32 {
    const t = ls.Type(1);
    try ls.argCheck(t == .lua_t_table or t == .lua_t_string, 1, "table or string expected");
    try ls.pushInteger(@intCast(try ls.rawLen(1)));
    return 1;
}

// rawget (table, index)
// http://www.lua.org/manual/5.3/manual.html#pdf-rawget
// lua-5.3.4/src/lbaselib.c#luaB_rawget()
fn baseRawGet(ls: *LuaState) LuaError!i32 {
    try ls.checkType(1, .lua_t_table);
    try ls.checkAny(2);
    try ls.setTop(2);
    _ = try ls.rawGet(1);
    return 1;
}

// rawset (table, index, value)
// http://www.lua.org/manual/5.3/manual.html#pdf-rawset
// lua-5.3.4/src/lbaselib.c#luaB_rawset()
fn baseRawSet(ls: *LuaState) LuaError!i32 {
    try ls.checkType(1, .lua_t_table);
    try ls.checkAny(2);
    try ls.checkAny(3);
    try ls.setTop(3);
    try ls.rawSet(1);
    return 1;
}

// type (v)
// http://www.lua.org/manual/5.3/manual.html#pdf-type
// lua-5.3.4/src/lbaselib.c#luaB_type()
fn baseType(ls: *LuaState) LuaError!i32 {
    const t = ls.Type(1);
    try ls.argCheck(t != .lua_t_none, 1, "value expected");
    try ls.pushString(ls.typeName(t));
    return 1;
}

// tostring (v)
// http://www.lua.org/manual/5.3/manual.html#pdf-tostring
// lua-5.3.4/src/lbaselib.c#luaB_tostring()
fn baseToString(ls: *LuaState) LuaError!i32 {
    try ls.checkAny(1);
    _ = try ls.toString2(1);
    return 1;
}

// tonumber (e [, base])
// http://www.lua.org/manual/5.3/manual.html#pdf-tonumber
// lua-5.3.4/src/lbaselib.c#luaB_tonumber()
fn baseToNumber(ls: *LuaState) LuaError!i32 {
    if (ls.isNoneOrNil(2)) { // standard conversion?
        try ls.checkAny(1);
        if (ls.Type(1) == .lua_t_number) { // already a number?
            try ls.setTop(1); // yes; return it
            return 1;
        } else {
            const s, const ok = try ls.toStringX(ls.allocator, 1);
            if (ok) {
                if (try ls.stringToNumber(s.bytes)) {
                    return 1; // successful conversion to number
                } // else not a number
            }
        }
    } else {
        try ls.checkType(1, .lua_t_string); // no numbers as strings
        const s = strings.TrimSpace((try ls.toString(1)).bytes);
        const base = try ls.checkInteger(2);
        try ls.argCheck(2 <= base and base <= 36, 2, "base out of range");
        if (std.fmt.parseInt(i64, s, @intCast(base))) |n| {
            try ls.pushInteger(n);
            return 1;
        } else |_| {} // else not a number
    } // else not a number
    try ls.pushNil(); // not a number
    return 1;
}
