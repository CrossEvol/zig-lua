const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const luaUpvalueIndex = ApiPKg.luaUpvalueIndex;
const strings = ApiPKg.strings;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;
const StrPkg = @import("str.zig");
const parseFmtStr = StrPkg.parseFmtStr;
const find = StrPkg.find;
const match = StrPkg.match;
const gsub = StrPkg.gsub;

const string = []const u8;

var strLib = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "len", strLen },
        .{ "rep", strRep },
        .{ "reverse", strReverse },
        .{ "lower", strLower },
        .{ "upper", strUpper },
        .{ "sub", strSub },
        .{ "byte", strByte },
        .{ "char", strChar },
        .{ "dump", strDump },
        .{ "format", strFormat },
        .{ "packsize", strPackSize },
        .{ "pack", strPack },
        .{ "unpack", strUnpack },
        .{ "find", strFind },
        .{ "match", strMatch },
        .{ "gsub", strGsub },
        .{ "gmatch", strGmatch },
    },
);

pub fn openStringLib(ls: *LuaState) !i32 {
    try ls.newLib(strLib);
    try createMetatable(ls);
    return 1;
}

fn createMetatable(ls: *LuaState) !void {
    try ls.createTable(0, 1); // table to be metatable for strings
    try ls.pushString("dummy"); // dummy string
    try ls.pushValue(-2); // copy table
    try ls.SetMetatable(-2); // set table as metatable for strings
    try ls.pop(1); // pop dummy string
    try ls.pushValue(-2); // get string library
    try ls.setField(-2, "__index"); // metatable.__index = string
    try ls.pop(1); // pop metatable
}

// Basic String Functions

// string.len (s)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.len
// lua-5.3.4/src/lstrlib.c#str_len()
fn strLen(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    try ls.pushInteger(@intCast(s.len));
    return 1;
}

// string.rep (s, n [, sep])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.rep
// lua-5.3.4/src/lstrlib.c#str_rep()
fn strRep(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const n: usize = @intCast(try ls.checkInteger(2));
    const sep = try ls.optString(3, "");

    if (n <= 0) {
        try ls.pushString("");
    } else if (n == 1) {
        try ls.pushString(s);
    } else {
        const a = try ls.allocator.alloc(string, n);
        defer ls.allocator.free(a);
        for (0..n) |i| {
            a[i] = s;
        }
        const joined = try strings.Join(ls.allocator, a, sep);
        defer ls.allocator.free(joined);
        try ls.pushString(joined);
    }

    return 1;
}

// string.reverse (s)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.reverse
// lua-5.3.4/src/lstrlib.c#str_reverse()
fn strReverse(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);

    const str_len = s.len;
    if (str_len > 1) {
        const a = try ls.allocator.alloc(u8, str_len);
        defer ls.allocator.free(a);
        for (0..str_len) |i| {
            a[i] = s[str_len - 1 - i];
        }
        try ls.pushString(a);
    } else {
        try ls.pushString(s);
    }

    return 1;
}

// string.lower (s)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.lower
// lua-5.3.4/src/lstrlib.c#str_lower()
fn strLower(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const lower = try strings.ToLower(ls.allocator, s);
    defer ls.allocator.free(lower);
    try ls.pushString(lower);
    return 1;
}

// string.upper (s)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.upper
// lua-5.3.4/src/lstrlib.c#str_upper()
fn strUpper(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const upper = try strings.ToUpper(ls.allocator, s);
    defer ls.allocator.free(upper);
    try ls.pushString(upper);
    return 1;
}

// string.sub (s, i [, j])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.sub
// lua-5.3.4/src/lstrlib.c#str_sub()
fn strSub(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const s_len: i32 = @intCast(s.len);
    var i = posRelat(try ls.checkInteger(2), s_len);
    var j = posRelat(try ls.optInteger(3, -1), s_len);

    if (i < 1) {
        i = 1;
    }
    if (j > s_len) {
        j = s_len;
    }

    if (i <= j) {
        try ls.pushString(s[@as(usize, @intCast(i - 1))..@as(usize, @intCast(j))]);
    } else {
        try ls.pushString("");
    }

    return 1;
}

// string.byte (s [, i [, j]])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.byte
// lua-5.3.4/src/lstrlib.c#str_byte()
fn strByte(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const s_len: i32 = @intCast(s.len);
    var i = posRelat(try ls.optInteger(2, 1), s_len);
    var j = posRelat(try ls.optInteger(3, @intCast(i)), s_len);

    if (i < 1) {
        i = 1;
    }
    if (j > s_len) {
        j = s_len;
    }

    if (i > j) {
        return 0; // empty interval; return no values
    }

    //if (j - i >= INT_MAX) { /* arithmetic overflow? */
    //  return ls.Error2("string slice too long")
    //}

    const n = j - i + 1;
    try ls.checkStack2(n, "string slice too long");
    {
        var k: i32 = 0;
        while (k < n) : (k += 1) {
            try ls.pushInteger(@intCast(s[@as(usize, @intCast(i + k - 1))]));
        }
    }

    return n;
}

// string.char (···)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.char
// lua-5.3.4/src/lstrlib.c#str_char()
fn strChar(ls: *LuaState) !i32 {
    const n_args: usize = @intCast(ls.getTop());

    const s = try ls.allocator.alloc(u8, n_args);
    defer ls.allocator.free(s);
    for (1..n_args + 1) |i| {
        const c = try ls.checkInteger(@intCast(i));
        try ls.argCheck(
            @as(i64, @intCast(@as(u8, @intCast(c)))) == c,
            @intCast(i),
            "value out of range",
        );
        s[i - 1] = @intCast(c);
    }

    try ls.pushString(s);
    return 1;
}

// string.dump (function [, strip])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.dump
// lua-5.3.4/src/lstrlib.c#str_dump()
fn strDump(ls: *LuaState) !i32 {
    _ = ls;
    // strip := ls.ToBoolean(2)
    // ls.CheckType(1, LUA_TFUNCTION)
    // ls.SetTop(1)
    // ls.PushString(string(ls.Dump(strip)))
    // return 1
    @panic("todo: strDump!");
}

// PACK/UNPACK

// string.packsize (fmt)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.packsize
fn strPackSize(ls: *LuaState) !i32 {
    const fmt = try ls.checkString(1);
    if (std.mem.eql(u8, fmt, "j")) {
        try ls.pushInteger(8);
    } else {
        @panic("todo: strPackSize!");
    }
    return 1;
}

// string.pack (fmt, v1, v2, ···)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.pack
fn strPack(ls: *LuaState) !i32 {
    _ = ls;
    @panic("todo: strPack!");
}

// string.unpack (fmt, s [, pos])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.unpack
fn strUnpack(ls: *LuaState) !i32 {
    _ = ls;
    @panic("todo: strUnpack!");
}

// STRING FORMAT

// string.format (formatstring, ···)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.format
fn strFormat(ls: *LuaState) !i32 {
    const fmt_str = try ls.checkString(1);
    if (fmt_str.len <= 1 or strings.IndexByte(fmt_str, '%') < 0) {
        try ls.pushString(fmt_str);
        return 1;
    }

    var arg_idx: i32 = 1;
    const arr = try parseFmtStr(ls.allocator, fmt_str);
    defer ls.allocator.free(arr);

    var strings_to_free = try std.ArrayList(string).initCapacity(ls.allocator, arr.len);
    defer {
        for (strings_to_free.items) |s| {
            ls.allocator.free(s);
        }
        strings_to_free.deinit(ls.allocator);
    }

    for (0.., arr) |i, s| {
        if (s.len > 0 and s[0] == '%') {
            if (std.mem.eql(u8, s, "%%")) {
                arr[i] = "%";
            } else {
                arg_idx += 1;
                const repl = try _fmtArg(ls.allocator, s, ls, arg_idx);
                errdefer ls.allocator.free(repl);
                arr[i] = repl;
                try strings_to_free.append(ls.allocator, repl);
            }
        }
    }

    const result = try strings.Join(ls.allocator, arr, "");
    defer ls.allocator.free(result);
    try ls.pushString(result);
    return 1;
}

fn _fmtArg(allocator: std.mem.Allocator, tag: string, ls: *LuaState, arg_idx: i32) !string {
    switch (tag[tag.len - 1]) {
        'c' => {
            const result = try std.fmt.allocPrint(allocator, "{c}", .{@as(u8, @intCast(ls.toInteger(arg_idx)))});
            return result;
        },
        'i' => {
            const fmt = "{d}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{ls.toInteger(arg_idx)});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        'd', 'o' => { // integer, octal
            const fmt = "{d}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{ls.toInteger(arg_idx)});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        'u' => { // unsigned integer
            const fmt = "{u}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{@as(u21, @intCast(ls.toInteger(arg_idx)))});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        'x', 'X' => { // hex integer
            const fmt = "{x}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{ls.toInteger(arg_idx)});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        'f' => { // float
            const fmt = "{d}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{ls.toNumber(arg_idx)});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        's', 'q' => { // string
            const fmt = "{s}";
            const segment = try std.fmt.allocPrint(allocator, fmt, .{try ls.toString2(arg_idx)});
            defer allocator.free(segment);
            const result = try std.mem.concat(allocator, u8, &.{ tag[0 .. tag.len - 2], segment[0..segment.len] });
            return result;
        },
        else => {
            std.debug.print("todo! tag={s}", .{tag});
            return LuaError.Panic;
        },
    }
}

// PATTERN MATCHING

// string.find (s, pattern [, init [, plain]])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.find
fn strFind(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const s_len: i32 = @intCast(s.len);
    const pattern = try ls.checkString(2);
    var init = posRelat(try ls.optInteger(3, 1), s_len);
    if (init < 1) {
        init = 1;
    } else if (init > s_len + 1) { // start after string's end?
        try ls.pushNil();
        return 1;
    }

    const plain = ls.toBoolean(4);

    const start, const end = try find(ls.allocator, s, pattern, init, plain);

    if (start < 0) {
        try ls.pushNil();
        return 1;
    }
    try ls.pushInteger(@intCast(start));
    try ls.pushInteger(@intCast(end));
    return 2;
}

// string.match (s, pattern [, init])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.match
fn strMatch(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const s_len: i32 = @intCast(s.len);
    const pattern = try ls.checkString(2);
    var init = posRelat(try ls.optInteger(3, 1), s_len);
    if (init < 1) {
        init = 1;
    } else if (init > s_len + 1) { // start after string's end?
        try ls.pushNil();
        return 1;
    }

    const option_captures = try match(ls.allocator, s, pattern, init);
    defer if (option_captures) |captures| {
        ls.allocator.free(captures);
    };

    if (option_captures) |captures| {
        var i: usize = 0;
        while (i < captures.len) : (i += 2) {
            const capture = s[captures[i]..captures[i + 1]];
            try ls.pushString(capture);
        }
        return @intCast(captures.len / 2);
    } else {
        try ls.pushNil();
        return 1;
    }
}

// string.gsub (s, pattern, repl [, n])
// http://www.lua.org/manual/5.3/manual.html#pdf-string.gsub
fn strGsub(ls: *LuaState) !i32 {
    const s = try ls.checkString(1);
    const pattern = try ls.checkString(2);
    const repl = try ls.checkString(3);
    const n = @as(i32, @intCast(try ls.optInteger(4, -1)));

    const new_str, const n_matches = try gsub(ls.allocator, s, pattern, repl, n);
    defer ls.allocator.free(new_str);
    try ls.pushString(new_str);
    try ls.pushInteger(@intCast(n_matches));
    return 2;
}

// string.gmatch (s, pattern)
// http://www.lua.org/manual/5.3/manual.html#pdf-string.gmatch
fn strGmatch(ls: *LuaState) !i32 {
    _ = try ls.checkString(1); // s
    _ = try ls.checkString(2); // pattern

    try ls.pushValue(1); // upvalue 1: s
    try ls.pushValue(2); // upvalue 2: pattern
    try ls.pushInteger(1); // upvalue 3: init pos
    try ls.pushZigClosure(gmatchAux, 3);
    return 1;
}

fn gmatchAux(ls: *LuaState) !i32 {
    const s = try ls.toString2(luaUpvalueIndex(1));
    const pattern = try ls.toString2(luaUpvalueIndex(2));
    const init: i32 = @intCast(ls.toInteger(luaUpvalueIndex(3)));

    const option_captures = try match(ls.allocator, s, pattern, init);
    defer if (option_captures) |captures| {
        ls.allocator.free(captures);
    };

    if (option_captures) |captures| {
        var i: usize = 0;
        while (i < captures.len) : (i += 2) {
            const capture = s[captures[i]..captures[i + 1]];
            try ls.pushString(capture);
        }

        const next_init: i64 = @intCast(captures[captures.len - 1] + 1);
        try ls.pushInteger(next_init);
        try ls.replace(luaUpvalueIndex(3));

        return @intCast(captures.len / 2);
    } else {
        return 0;
    }
}

// helper

// translate a relative string position: negative means back from end
pub fn posRelat(pos: i64, _len: i32) i32 {
    const _pos: i32 = @intCast(pos);
    if (_pos >= 0) {
        return _pos;
    } else if (-_pos > _len) {
        return 0;
    } else {
        return _len + _pos + 1;
    }
}
