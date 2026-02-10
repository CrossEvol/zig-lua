const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const LUA_MAXINTEGER = ApiPKg.LUA_MAXINTEGER;
const strings = ApiPKg.strings;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;
const default_zig_function_impl = @import("../state/root.zig").default_zig_function_impl;
const posRelat = @import("lib_string.zig").posRelat;

const string = []const u8;
// pattern to match a single UTF-8 character
// const UTF8PATT = "[\x00-\x7F\xC2-\xF4][\x80-\xBF]*"

const UTF8PATT =
    \\(.)
;

const MAX_UNICODE = 0x10FFFF;

var utf8Lib = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "len", utfLen },
        .{ "offset", utfByteOffset },
        .{ "codepoint", utfCodePoint },
        .{ "char", utfChar },
        .{ "codes", utfIterCodes },
        //  placeholders
        .{ "charpattern", default_zig_function_impl },
    },
);

pub fn openUTF8Lib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(utf8Lib);
    try ls.pushString(UTF8PATT);
    try ls.setField(-2, "charpattern");
    return 1;
}

// utf8.len (s [, i [, j]])
// http://www.lua.org/manual/5.3/manual.html#pdf-utf8.len
// lua-5.3.4/src/lutf8lib.c#utflen()
pub fn utfLen(ls: *LuaState) LuaError!i32 {
    const s = try ls.checkString(1);
    const s_len = s.len;
    const i = @as(usize, @intCast(posRelat(try ls.optInteger(2, 1), @intCast(s_len))));
    const j = @as(usize, @intCast(posRelat(try ls.optInteger(3, -1), @intCast(s_len))));
    try ls.argCheck(1 <= i and i <= s_len + 1, 2, "initial position out of string");
    try ls.argCheck(j <= s_len, 3, "final position out of string");

    if (i > j) {
        try ls.pushInteger(0);
    } else {
        const n = std.unicode.utf8CountCodepoints(s[i - 1 .. j]) catch {
            std.debug.print("utf8 error", .{});
            return LuaError.Panic;
        };
        try ls.pushInteger(@intCast(n));
    }

    return 1;
}

// utf8.offset (s, n [, i])
// http://www.lua.org/manual/5.3/manual.html#pdf-utf8.offset
pub fn utfByteOffset(ls: *LuaState) LuaError!i32 {
    const s = try ls.checkString(1);
    const s_len = s.len;
    var n = try ls.checkInteger(2);
    var i: usize = 1;
    if (n < 0) {
        i = s_len + 1;
    }
    i = @as(usize, @intCast(posRelat(try ls.optInteger(3, @intCast(i)), @intCast(s_len))));
    try ls.argCheck(1 <= i and i <= s_len + 1, 3, "position out of range");
    i -= 1;

    if (n == 0) {
        // find beginning of current byte sequence
        while (i > 0 and _isCont(s[i])) {
            i -= 1;
        }
    } else {
        if (i < s_len and _isCont(s[i])) {
            _ = try ls.error2("initial position is a continuation byte", .{});
        }
        if (n < 0) {
            while (n < 0 and i > 0) { // move back
                while (true) { // find beginning of previous character
                    i -= 1;
                    if (!(i > 0 and _isCont(s[i]))) {
                        break;
                    }
                }
                n += 1;
            }
        } else {
            n -= 1; // do not move for 1st character
            while (n > 0 and i < s_len) {
                while (true) { // find beginning of next character
                    i += 1;
                    if (i >= s_len or !_isCont(s[i])) {
                        break; // (cannot pass final '\0')
                    }
                }
                n -= 1;
            }
        }
    }
    if (n == 0) { // did it find given character?
        try ls.pushInteger(@intCast(i + 1));
    } else { // no such character
        try ls.pushNil();
    }
    return 1;
}

// utf8.codepoint (s [, i [, j]])
// http://www.lua.org/manual/5.3/manual.html#pdf-utf8.codepoint
// lua-5.3.4/src/lutf8lib.c#codepoint()
pub fn utfCodePoint(ls: *LuaState) LuaError!i32 {
    var s = try ls.checkString(1);
    const s_len = @as(i32, @intCast(s.len));
    var i = posRelat(try ls.optInteger(2, 1), s_len);
    const j = posRelat(try ls.optInteger(3, @intCast(i)), s_len);

    try ls.argCheck(i >= 1, 2, "out of range");
    try ls.argCheck(j <= s_len, 3, "out of range");
    if (i > j) {
        return 0; // empty interval; return no values
    }
    if (j - i >= LUA_MAXINTEGER) { // (lua_Integer -> int) overflow?
        return ls.error2("string slice too long", .{});
    }
    var n = j - i + 1;
    try ls.checkStack2(n, "string slice too long");

    n = 0;
    s = s[@as(usize, @intCast(i - 1))..];
    while (i <= j) {
        const cp_len = @as(usize, @intCast(std.unicode.utf8ByteSequenceLength(s[0]) catch {
            return ls.error2("invalid UTF-8 code", .{});
        }));
        if (s.len < cp_len) return ls.error2("invalid UTF-8 code", .{});
        const code = std.unicode.utf8Decode(s[0..cp_len]) catch {
            return ls.error2("invalid UTF-8 code", .{});
        };

        try ls.pushInteger(@intCast(code));
        n += 1;
        i += @intCast(cp_len);
        s = s[cp_len..];
    }
    return n;
}

// utf8.char (···)
// http://www.lua.org/manual/5.3/manual.html#pdf-utf8.char
// lua-5.3.4/src/lutf8lib.c#utfchar()
pub fn utfChar(ls: *LuaState) LuaError!i32 {
    const n = @as(usize, @intCast(ls.getTop())); // number of arguments
    var code_points = try ls.allocator.alloc(u32, n);
    defer ls.allocator.free(code_points);

    for (1..n + 1) |i| {
        const cp = try ls.checkInteger(@intCast(i));
        try ls.argCheck(0 <= cp and cp <= MAX_UNICODE, @intCast(i), "value out of range");
        code_points[i - 1] = @intCast(cp);
    }

    const encoded = _encodeUtf8(ls.allocator, code_points) catch {
        std.debug.print("invalid utf8 for {any}", .{code_points});
        return LuaError.Panic;
    };
    defer ls.allocator.free(encoded);
    try ls.pushString(encoded);
    return 1;
}

fn _encodeUtf8(allocator: std.mem.Allocator, code_points: []u32) !string {
    var str = try std.ArrayList(u8).initCapacity(allocator, code_points.len);
    errdefer str.deinit(allocator);

    var buf: [6]u8 = undefined;
    for (code_points) |cp| {
        const n = try std.unicode.utf8Encode(@intCast(cp), &buf);
        try str.appendSlice(allocator, buf[0..n]);
    }

    return try str.toOwnedSlice(allocator);
}

// utf8.codes (s)
// http://www.lua.org/manual/5.3/manual.html#pdf-utf8.codes
pub fn utfIterCodes(ls: *LuaState) LuaError!i32 {
    _ = try ls.checkString(1);
    try ls.pushZigFunction(_iterAux);
    try ls.pushValue(1);
    try ls.pushInteger(0);
    return 3;
}

fn _iterAux(ls: *LuaState) LuaError!i32 {
    const s = try ls.checkString(1);
    const s_len: i64 = @intCast(s.len);
    var n: i64 = ls.toInteger(2) - 1;
    if (n < 0) { // first iteration?
        n = 0; // start from here
    } else if (n < s_len) {
        n += 1;
        while (n < s_len and _isCont(s[@intCast(n)])) {
            n += 1;
        } // and its continuations
    }

    if (n >= s_len) {
        return 0; // no more codepoints
    } else {
        const idx: usize = @intCast(n);
        const cp_len = std.unicode.utf8ByteSequenceLength(s[idx]) catch {
            return ls.error2("invalid UTF-8 code", .{});
        };
        if (s.len < idx + @as(usize, @intCast(cp_len))) return ls.error2("invalid UTF-8 code", .{});
        const code = std.unicode.utf8Decode(s[idx .. idx + @as(usize, @intCast(cp_len))]) catch {
            return ls.error2("invalid UTF-8 code", .{});
        };

        try ls.pushInteger(@intCast(n + 1));
        try ls.pushInteger(@intCast(code));
        return 2;
    }
}

fn _isCont(b: u8) bool {
    return b & 0xC0 == 0x80;
}
