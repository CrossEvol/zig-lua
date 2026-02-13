const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const LUA_MULTRET = ApiPKg.LUA_MULTRET;
const ThreadStatus = ApiPKg.ThreadStatus;
const strings = ApiPKg.strings;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;
const default_zig_function_impl = @import("../state/root.zig").default_zig_function_impl;

var coFuncs = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "create", coCreate },
        .{ "resume", coResume },
        .{ "yield", coYield },
        .{ "status", coStatus },
        .{ "isyieldable", coYieldable },
        .{ "running", coRunning },
        .{ "wrap", coWrap },
    },
);

pub fn openCoroutineLib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(coFuncs);
    return 1;
}

// coroutine.create (f)
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.create
// lua-5.3.4/src/lcorolib.c#luaB_cocreate()
fn coCreate(ls: *LuaState) LuaError!i32 {
    try ls.checkType(1, .lua_t_function);
    const ls2 = try ls.newThread();
    try ls.pushValue(1); // move function to top
    try ls.xMove(ls2, 1); // move function from ls to ls2
    return 1;
}

// coroutine.resume (co [, val1, ···])
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.resume
// lua-5.3.4/src/lcorolib.c#luaB_coresume()
fn coResume(ls: *LuaState) LuaError!i32 {
    const option_co = ls.toThread(1);
    try ls.argCheck(option_co != null, 1, "thread expected");

    if (option_co) |co| {
        const r = try _auxResume(ls, co, ls.getTop() - 1);
        if (r < 0) {
            try ls.pushBoolean(false);
            ls.insert(-2);
            return 2; // return false + error message
        } else {
            try ls.pushBoolean(true);
            ls.insert(-(r + 1));
            return r + 1; // return true + 'resume' returns
        }
    }
    unreachable;
}

fn _auxResume(ls: *LuaState, co: *LuaState, n_arg: i32) LuaError!i32 {
    if (!ls.checkStack(n_arg)) {
        try ls.pushString("too many arguments to resume");
        return -1; //  error flag
    }
    if (co.Status() == .lua_ok and co.getTop() == 0) {
        try ls.pushString("cannot resume dead coroutine");
        return -1; // error flag
    }

    try ls.xMove(co, n_arg);
    const status = try co.Resume(ls, n_arg);
    if (status == .lua_ok or status == .lua_yield) {
        const n_res = co.getTop();
        if (!ls.checkStack(n_res + 1)) {
            try co.pop(n_res); // remove results anyway
            try ls.pushString("too many results to resume");
            return -1; // error flag
        }
        try co.xMove(ls, n_res); // move yielded values
        return n_res;
    } else {
        try co.xMove(ls, 1);
        return -1;
    }
}

// coroutine.yield (···)
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.yield
// lua-5.3.4/src/lcorolib.c#luaB_yield()
fn coYield(ls: *LuaState) LuaError!i32 {
    return try ls.yield(ls.getTop());
}

// coroutine.status (co)
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.status
// lua-5.3.4/src/lcorolib.c#luaB_costatus()
fn coStatus(ls: *LuaState) LuaError!i32 {
    const option_co = ls.toThread(1);
    try ls.argCheck(option_co != null, 1, "thread expected");

    if (option_co) |co| {
        if (ls == co) {
            try ls.pushString("running");
        } else {
            switch (co.Status()) {
                .lua_yield => {
                    try ls.pushString("suspended");
                },
                .lua_ok => {
                    if (co.getStack()) { // does it have frames?
                        try ls.pushString("normal"); // it is running
                    } else if (co.getTop() == 0) {
                        try ls.pushString("dead");
                    } else {
                        try ls.pushString("suspended");
                    }
                },
                else => { // some error occurred
                    try ls.pushString("dead");
                },
            }
        }
    }

    return 1;
}

// coroutine.isyieldable ()
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.isyieldable
fn coYieldable(ls: *LuaState) LuaError!i32 {
    try ls.pushBoolean(ls.isYieldable());
    return 1;
}

// coroutine.running ()
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.running
fn coRunning(ls: *LuaState) LuaError!i32 {
    const is_main = try ls.pushThread();
    try ls.pushBoolean(is_main);
    return 2;
}

// coroutine.wrap (f)
// http://www.lua.org/manual/5.3/manual.html#pdf-coroutine.wrap
fn coWrap(ls: *LuaState) LuaError!i32 {
    _ = ls;
    @panic("todo: coWrap!");
}
