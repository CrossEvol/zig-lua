const std = @import("std");

const regex = @import("pcrez");

const ApiPkg = @import("../api/root.zig");
const strings = ApiPkg.strings;
const LuaError = ApiPkg.LuaError;

const string = []const u8;

// tag = %[flags][width][.precision]specifier
const re_tag_pattern =
    \\%[ #+-0]?[0-9]*(\.[0-9]+)?[cdeEfgGioqsuxX%]
;

pub fn parseFmtStr(allocator: std.mem.Allocator, fmt0: string) ![]string {
    var fmt = fmt0;

    if (std.mem.eql(u8, fmt, "") or strings.IndexByte(fmt, '%') < 0) {
        const slices = try allocator.alloc(string, 1);
        slices[0] = fmt;
        return slices;
    }

    var parsed = try std.ArrayList(string).initCapacity(allocator, fmt.len / 2);
    errdefer parsed.deinit(allocator);

    var tag_pattern = regex.Regex.from(re_tag_pattern, true, allocator) catch return LuaError.Panic;
    defer tag_pattern.deinit();

    while (true) {
        if (std.mem.eql(u8, fmt, "")) {
            break;
        }

        if (tag_pattern.findStringIndex(fmt, allocator)) |loc| {
            defer allocator.free(loc);
            const head = fmt[0..loc[0]];
            const tag = fmt[loc[0]..loc[1]];
            const tail = fmt[loc[1]..];

            if (!std.mem.eql(u8, head, "")) {
                try parsed.append(allocator, head);
            }
            try parsed.append(allocator, tag);
            fmt = tail;
        } else {
            try parsed.append(allocator, fmt);
            break;
        }
    }
    return try parsed.toOwnedSlice(allocator);
}

/// -> (start: i32, end: i32)
pub fn find(allocator: std.mem.Allocator, s: string, pattern: string, init: i32, plain: bool) !struct { i32, i32 } {
    var tail = s;
    if (init > 1) {
        tail = s[@as(usize, @intCast(init - 1))..];
    }

    var start: i32 = 0;
    var end: i32 = 0;

    if (plain) {
        start = strings.Index(tail, pattern);
        end = if (start >= 0)
            start + @as(i32, @intCast(pattern.len)) - 1
        else
            -1;
    } else {
        if (_compile(allocator, pattern)) |re| {
            defer {
                re.deinit();
                allocator.destroy(re);
            }
            if (re.findStringIndex(tail, allocator)) |loc| {
                defer allocator.free(loc);
                start = @intCast(loc[0]);
                end = @intCast(loc[1] - 1);
            } else {
                start = -1;
                end = -1;
            }
        } else |_| {
            return LuaError.Panic;
        }
    }

    if (start >= 0) {
        start += @as(i32, @intCast(s.len - tail.len + 1));
        end += @as(i32, @intCast(s.len - tail.len + 1));
    }

    return .{ start, end };
}

pub fn match(allocator: std.mem.Allocator, s: string, pattern: string, init: i32) !?[]usize {
    var tail = s;
    if (init > 1) {
        tail = s[@as(usize, @intCast(init - 1))..];
    }

    if (_compile(allocator, pattern)) |re| {
        defer {
            re.deinit();
            allocator.destroy(re);
        }
        if (re.findStringSubmatchIndex(tail, allocator)) |found| {
            if (found.len > 2) {
                const captures = try allocator.alloc(usize, found.len - 2);
                @memcpy(captures, found[2..]);
                allocator.free(found);
                return captures;
            } else {
                return found;
            }
        } else {
            return null;
        }
    } else |_| {
        return LuaError.Panic;
    }
}

pub fn gsub(allocator: std.mem.Allocator, s: string, pattern: string, repl: string, n: i32) !struct { string, i32 } {
    if (_compile(allocator, pattern)) |re| {
        defer {
            re.deinit();
            allocator.destroy(re);
        }
        if (re.findAllStringIndex(s, n, allocator)) |indexes| {
            defer {
                for (indexes) |index| {
                    allocator.free(index);
                }
                allocator.free(indexes);
            }
            const n_matches = indexes.len;
            const last_end = indexes[n_matches - 1][1];
            const head = s[0..last_end];
            const tail = s[last_end..];
            if (re.replaceAllString(head, repl)) |new_head| {
                defer new_head.deinit();
                const concat_str = try std.fmt.allocPrint(allocator, "{s}{s}", .{ new_head.items, tail });
                return .{ concat_str, @intCast(n_matches) };
            } else {
                return .{ try allocator.dupe(u8, s), 0 };
            }
        } else {
            return .{ try allocator.dupe(u8, s), 0 };
        }
    } else |_| {
        return LuaError.Panic;
    }
}

fn _compile(allocator: std.mem.Allocator, pattern: string) !*regex.Regex {
    const re = try allocator.create(regex.Regex);
    re.* = try regex.Regex.from(pattern, true, allocator);
    return re;
}

// ==================== parseFmtStr Tests ====================
test "parseFmtStr - empty string" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("", result[0]);
}

test "parseFmtStr - no format specifiers" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "hello world");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("hello world", result[0]);
}

test "parseFmtStr - single specifier" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "Hello %s");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("Hello ", result[0]);
    try std.testing.expectEqualStrings("%s", result[1]);
}

test "parseFmtStr - multiple specifiers" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "Hello %s world %d");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("Hello ", result[0]);
    try std.testing.expectEqualStrings("%s", result[1]);
    try std.testing.expectEqualStrings(" world ", result[2]);
    try std.testing.expectEqualStrings("%d", result[3]);
}

test "parseFmtStr - complex format" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "%d + %f = %.2f");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 5), result.len);
    try std.testing.expectEqualStrings("%d", result[0]);
    try std.testing.expectEqualStrings(" + ", result[1]);
    try std.testing.expectEqualStrings("%f", result[2]);
    try std.testing.expectEqualStrings(" = ", result[3]);
    try std.testing.expectEqualStrings("%.2f", result[4]);
}

test "parseFmtStr - with flags and width" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "%-10s %+d");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("%-10s", result[0]);
    try std.testing.expectEqualStrings(" ", result[1]);
    try std.testing.expectEqualStrings("%+d", result[2]);
}

test "parseFmtStr - specifier at beginning" {
    const allocator = std.testing.allocator;
    const result = try parseFmtStr(allocator, "%d%% complete");
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("%d", result[0]);
    try std.testing.expectEqualStrings("%%", result[1]);
    try std.testing.expectEqualStrings(" complete", result[2]);
}

// ==================== find Tests ====================
test "find - plain mode - found at beginning" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello world", "hello", 1, true);
    try std.testing.expectEqual(@as(i32, 1), result[0]);
    try std.testing.expectEqual(@as(i32, 5), result[1]); // "hello" is 5 chars
}

test "find - plain mode - found in middle" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello world", "world", 1, true);
    try std.testing.expectEqual(@as(i32, 7), result[0]);
    try std.testing.expectEqual(@as(i32, 11), result[1]); // "world" ends at index 11
}

test "find - plain mode - not found" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello world", "xyz", 1, true);
    try std.testing.expectEqual(@as(i32, -1), result[0]);
    try std.testing.expectEqual(@as(i32, -1), result[1]);
}

test "find - plain mode - with init offset" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello hello world", "hello", 5, true);
    try std.testing.expectEqual(@as(i32, 7), result[0]);
    try std.testing.expectEqual(@as(i32, 11), result[1]);
}

test "find - plain mode - single char" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "abc", "b", 1, true);
    try std.testing.expectEqual(@as(i32, 2), result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
}

test "find - regex mode - digit pattern" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "abc123def", "\\d+", 1, false);
    try std.testing.expectEqual(@as(i32, 4), result[0]);
    try std.testing.expectEqual(@as(i32, 6), result[1]);
}

test "find - regex mode - word pattern" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello world", "\\w+", 1, false);
    try std.testing.expectEqual(@as(i32, 1), result[0]);
    try std.testing.expectEqual(@as(i32, 5), result[1]);
}

test "find - regex mode - not found" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "hello world", "\\d+", 1, false);
    try std.testing.expectEqual(@as(i32, -1), result[0]);
    try std.testing.expectEqual(@as(i32, -1), result[1]);
}

test "find - regex mode - with init offset" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "abc123def456", "\\d+", 4, false);
    try std.testing.expectEqual(@as(i32, 4), result[0]);
    try std.testing.expectEqual(@as(i32, 6), result[1]);
}

test "find - regex mode - complex pattern" {
    const allocator = std.testing.allocator;
    const result = try find(allocator, "test@example.com", "[@.]", 1, false);
    try std.testing.expectEqual(@as(i32, 5), result[0]);
    try std.testing.expectEqual(@as(i32, 5), result[1]);
}

// ==================== match Tests ====================
test "match - simple word pattern" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "hello", "\\w+", 1);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 2), r.len); // full match only, no captures
    }
}

test "match - capture groups" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "hello world", "(\\w+)\\s+(\\w+)", 1);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 4), r.len); // 2 captures = 2 pairs = 4 elements
    }
}

test "match - no match" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "hello world", "\\d+", 1);
    try std.testing.expect(result == null);
}

test "match - digit capture" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "abc123def", "(\\d+)", 1);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 2), r.len); // 1 capture = 1 pair = 2 elements
    }
}

test "match - with init offset" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "abc123def", "\\d+", 4);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 2), r.len); // full match only
    }
}

test "match - multiple captures" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "2024-01-15", "(\\d{4})-(\\d{2})-(\\d{2})", 1);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 6), r.len); // 3 captures = 3 pairs = 6 elements
    }
}

test "match - email pattern" {
    const allocator = std.testing.allocator;
    const result = try match(allocator, "test@example.com", "(\\w+)@(\\w+)\\.(\\w+)", 1);
    try std.testing.expect(result != null);
    if (result) |r| {
        defer allocator.free(r);
        try std.testing.expectEqual(@as(usize, 6), r.len); // 3 captures = 3 pairs = 6 elements
    }
}

// ==================== gsub Tests ====================
test "gsub - replace all occurrences" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "hello world, hello universe", "hello", "hi", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("hi world, hi universe", result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
}

test "gsub - regex pattern digits" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "abc123def456", "\\d+", "X", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("abcXdefX", result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
}

test "gsub - limited replacements" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "a.b.c.d", "\\.", "-", 2);
    defer allocator.free(result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
}

test "gsub - no match" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "hello world", "xyz", "foo", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("hello world", result[0]);
    try std.testing.expectEqual(@as(i32, 0), result[1]);
}

test "gsub - word replacement" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "foo bar foo baz foo", "foo", "qux", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("qux bar qux baz qux", result[0]);
    try std.testing.expectEqual(@as(i32, 3), result[1]);
}

test "gsub - replace with spaces" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "hello    world", "\\s+", " ", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("hello world", result[0]);
    try std.testing.expectEqual(@as(i32, 1), result[1]);
}

test "gsub - remove pattern" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "test123string456end", "\\d+", "", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("teststringend", result[0]);
    try std.testing.expectEqual(@as(i32, 2), result[1]);
}

test "gsub - single replacement" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "hello world", "world", "everyone", 1);
    defer allocator.free(result[0]);
    try std.testing.expectEqualStrings("hello everyone", result[0]);
    try std.testing.expectEqual(@as(i32, 1), result[1]);
}

test "gsub - case sensitive" {
    const allocator = std.testing.allocator;
    const result = try gsub(allocator, "Hello HELLO hello", "HELLO", "hi", -1);
    defer allocator.free(result[0]);
    try std.testing.expectEqual(@as(i32, 1), result[1]); // Only exact match
}
