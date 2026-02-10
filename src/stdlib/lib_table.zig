const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const strings = ApiPKg.strings;
const LUA_MAXINTEGER = ApiPKg.LUA_MAXINTEGER;
const number = @import("../number/root.zig");
const default_zig_function_impl = @import("../state/root.zig").default_zig_function_impl;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;

const string = []const u8;

const MAX_LEN = 1000000;

// Operations that an object must define to mimic a table
// (some functions only need some of them)
const TAB_R = 1; // read
const TAB_W = 2; // write
const TAB_L = 4; // length
const TAB_RW = (TAB_R | TAB_W); // read/write

var tabFuncs = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "move", tabMove },
        .{ "insert", tabInsert },
        .{ "remove", tabRemove },
        .{ "sort", tabSort },
        .{ "concat", tabConcat },
        .{ "pack", tabPack },
        .{ "unpack", tabUnpack },
    },
);

pub fn openTableLib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(tabFuncs);
    return 1;
}

// table.move (a1, f, e, t [,a2])
// http://www.lua.org/manual/5.3/manual.html#pdf-table.move
// lua-5.3.4/src/ltablib.c#tremove()
fn tabMove(ls: *LuaState) LuaError!i32 {
    const f = try ls.checkInteger(2);
    const e = try ls.checkInteger(3);
    const t = try ls.checkInteger(4);
    var tt: i32 = 1; // destination table
    if (!ls.isNoneOrNil(5)) {
        tt = 5;
    }
    try _checkTab(ls, 1, TAB_R);
    try _checkTab(ls, tt, TAB_W);
    if (e >= f) { // otherwise, nothing to move
        var n: i64 = undefined;
        var i: i64 = 0;
        try ls.argCheck(f > 0 or e < LUA_MAXINTEGER + f, 3, "too many elements to move");
        n = e - f + 1; // number of elements to move
        try ls.argCheck(t <= LUA_MAXINTEGER - n + 1, 4, "destination wrap around");
        if (t > e or t <= f or (tt != 1 and !(try ls.compare(1, tt, .lua_op_eq)))) {
            while (i < n) : (i += 1) {
                _ = try ls.getI(1, f + i);
                try ls.setI(tt, t + i);
            }
        } else {
            i = n - 1;
            while (i >= 0) : (i -= 1) {
                _ = try ls.getI(1, f + i);
                try ls.setI(tt, t + i);
            }
        }
    }
    try ls.pushValue(tt); // return destination table
    return 1;
}

// table.insert (list, [pos,] value)
// http://www.lua.org/manual/5.3/manual.html#pdf-table.insert
// lua-5.3.4/src/ltablib.c#tinsert()
fn tabInsert(ls: *LuaState) LuaError!i32 {
    const e = try _auxGetN(ls, 1, TAB_RW) + 1; // first empty element
    var pos: i64 = undefined; // where to insert new element
    switch (ls.getTop()) {
        2 => { // called with only 2 arguments
            pos = e; // insert new element at the end
        },
        3 => {
            pos = try ls.checkInteger(2); // 2nd argument is the position
            try ls.argCheck(1 <= pos and pos <= e, 2, "position out of bounds");
            {
                var i = e;
                while (i > pos) : (i -= 1) { // t[i] = t[i - 1]
                    _ = try ls.getI(1, i - 1);
                    try ls.setI(1, i);
                }
            }
        },
        else => {
            return ls.error2("wrong number of arguments to 'insert'", .{});
        },
    }
    try ls.setI(1, pos); // t[pos] = v
    return 0;
}

// table.remove (list [, pos])
// http://www.lua.org/manual/5.3/manual.html#pdf-table.remove
// lua-5.3.4/src/ltablib.c#tremove()
fn tabRemove(ls: *LuaState) LuaError!i32 {
    const size = try _auxGetN(ls, 1, TAB_RW);
    var pos = try ls.optInteger(2, size);
    if (pos != size) { // validate 'pos' if give
        try ls.argCheck(1 <= pos and pos <= size + 1, 1, "position out of bounds");
    }
    _ = try ls.getI(1, pos); // result = t[pos]
    while (pos < size) : (pos += 1) {
        _ = try ls.getI(1, pos + 1);
        try ls.setI(1, pos); // t[pos] = t[pos + 1]
    }
    try ls.pushNil();
    try ls.setI(1, pos); // t[pos] = nil
    return 1;
}

// table.concat (list [, sep [, i [, j]]])
// http://www.lua.org/manual/5.3/manual.html#pdf-table.concat
// lua-5.3.4/src/ltablib.c#tconcat()
fn tabConcat(ls: *LuaState) LuaError!i32 {
    const tab_len = try _auxGetN(ls, 1, TAB_R);
    const sep = try ls.optString(2, "");
    const i = try ls.optInteger(3, 1);
    const j = try ls.optInteger(4, tab_len);

    if (i > j) {
        try ls.pushString("");
        return 1;
    }
    const buf = try ls.allocator.alloc(string, @intCast(j - i + 1));
    defer ls.allocator.free(buf);
    {
        var k = i;
        while (k > 0 and k <= j) : (k += 1) {
            _ = try ls.getI(1, k);
            if (!ls.isString(-1)) {
                _ = try ls.error2("invalid value ({s}) at index {d} in table for 'concat'", .{ try ls.typeName2(-1), i });
            }
            buf[@as(usize, @intCast(k - i))] = (try ls.toString(-1)).bytes;
            try ls.pop(1);
        }
    }

    const joined = try strings.Join(ls.allocator, buf, sep);
    defer ls.allocator.free(joined);
    try ls.pushString(joined);

    return 1;
}

fn _auxGetN(ls: *LuaState, n: i32, w: i32) !i64 {
    try _checkTab(ls, n, w | TAB_L);
    return try ls.len2(n);
}

// Check that 'arg' either is a table or can behave like one (that is,
// has a metatable with the required metamethods)
fn _checkTab(ls: *LuaState, arg: i32, what: i32) !void {
    if (ls.Type(arg) != .lua_t_table) { // is it not a table?
        var n: i32 = 1; // number of elements to pop
        if ((try ls.GetMetatable(arg)) and // must have metatable
            ((what & TAB_R) != 0 or try _checkField(ls, "__index", &n)) and
            ((what & TAB_W) != 0 or try _checkField(ls, "__newindex", &n)) and
            ((what & TAB_L) != 0 or try _checkField(ls, "__len", &n)))
        {
            try ls.pop(n); // pop metatable and tested metamethods
        } else {
            try ls.checkType(arg, .lua_t_table); // force an error
        }
    }
}

fn _checkField(ls: *LuaState, key: string, n: *i32) !bool {
    try ls.pushString(key);
    n.* += 1;
    return try ls.rawGet(-n.*) != .lua_t_nil;
}

// Pack/unpack

// table.pack (···)
// http://www.lua.org/manual/5.3/manual.html#pdf-table.pack
// lua-5.3.4/src/ltablib.c#pack()
fn tabPack(ls: *LuaState) LuaError!i32 {
    const n = @as(i64, @intCast(ls.getTop())); // number of elements to pack
    try ls.createTable(@intCast(n), 1); // create result table
    ls.insert(1); // put it at index 1
    {
        var i = n;
        while (i >= 1) : (i -= 1) { // assign elements
            try ls.setI(1, i);
        }
    }
    try ls.pushInteger(n);
    try ls.setField(1, "n"); // t.n = number of elements
    return 1; // return table
}

// table.unpack (list [, i [, j]])
// http://www.lua.org/manual/5.3/manual.html#pdf-table.unpack
// lua-5.3.4/src/ltablib.c#unpack()
fn tabUnpack(ls: *LuaState) LuaError!i32 {
    var i = try ls.optInteger(2, 1);
    const e = try ls.optInteger(3, try ls.len2(1));
    if (i > e) { // empty range
        return 0;
    }

    const n: i32 = @intCast(e - i + 1);
    if (n <= 0 or n >= MAX_LEN or !ls.checkStack(n)) {
        return ls.error2("too many results to unpack", .{});
    }

    while (i < e) : (i += 1) { // push arg[i..e - 1] (to avoid overflows)
        _ = try ls.getI(1, i);
    }
    _ = try ls.getI(1, e); //  push last element
    return n;
}

// sort

// table.sort (list [, comp])
// http://www.lua.org/manual/5.3/manual.html#pdf-table.sort
fn tabSort(ls: *LuaState) LuaError!i32 {
    const ctx = LuaSortContext.init(ls);
    const n = try ctx.len();
    try ls.argCheck(n < MAX_LEN, 1, "array too big");
    if (n > 1) {
        try quickSort(&ctx, 0, n - 1);
    }

    return 0;
}

fn quickSort(ctx: *const LuaSortContext, low: i64, high: i64) LuaError!void {
    if (low < high) {
        const pi = try partition(ctx, low, high);
        try quickSort(ctx, low, pi - 1);
        try quickSort(ctx, pi + 1, high);
    }
}

fn partition(ctx: *const LuaSortContext, low: i64, high: i64) !i64 {
    var i = low - 1;
    var j = low;
    while (j < high) : (j += 1) {
        if (try ctx.less(@intCast(j), @intCast(high))) {
            i += 1;
            if (i != j) {
                try ctx.swap(@intCast(i), @intCast(j));
            }
        }
    }

    i += 1;
    if (i != high) {
        try ctx.swap(@intCast(i), @intCast(high));
    }
    return i;
}

const LuaSortContext = struct {
    ls: *LuaState, // referenced

    pub fn init(ls: *LuaState) LuaSortContext {
        return .{ .ls = ls };
    }

    fn len(self: *const LuaSortContext) !i32 {
        return @intCast(try self.ls.len2(1));
    }

    fn less(self: *const LuaSortContext, i: i32, j: i32) !bool {
        const ls = self.ls;

        if (ls.isFunction(2)) { // cmp is given
            try ls.pushValue(2);
            _ = try ls.getI(1, @intCast(i + 1));
            _ = try ls.getI(1, @intCast(j + 1));
            try ls.call(2, 1);
            const b = ls.toBoolean(-1);
            try ls.pop(1);
            return b;
        } else { // cmp is missing
            _ = try ls.getI(1, @intCast(i + 1));
            _ = try ls.getI(1, @intCast(j + 1));
            const b = try ls.compare(-2, -1, .lua_op_lt);
            try ls.pop(2);
            return b;
        }
    }

    fn swap(self: *const LuaSortContext, i: i32, j: i32) !void {
        const ls = self.ls;
        _ = try ls.getI(1, @intCast(i + 1));
        _ = try ls.getI(1, @intCast(j + 1));
        _ = try ls.setI(1, @intCast(i + 1));
        _ = try ls.setI(1, @intCast(j + 1));
    }
};
