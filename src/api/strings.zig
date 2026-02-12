const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;

const string = []const u8;

// HasPrefix reports whether the string s begins with prefix.
pub fn HasPrefix(s: string, prefix: string) bool {
    return std.mem.startsWith(u8, s, prefix);
}

test "HasPrefix" {
    const t = std.testing;

    // √
    try t.expect(HasPrefix("hello", "hello"));
    try t.expect(HasPrefix("hello world", "hello"));
    try t.expect(HasPrefix("hello", "he"));
    try t.expect(HasPrefix("hello", ""));
    try t.expect(HasPrefix("", ""));

    // ❌
    try t.expect(!HasPrefix("hello", "helloo"));
    try t.expect(!HasPrefix("hello", "ello"));
    try t.expect(!HasPrefix("hello", "world"));
    try t.expect(!HasPrefix("hello", "H"));
    try t.expect(!HasPrefix("", "a"));

    // 漢字
    try t.expect(HasPrefix("你好世界", "你好"));
    try t.expect(!HasPrefix("你好世界", "世界"));

    // edge cases
    try t.expect(HasPrefix(" space", " "));
    try t.expect(!HasPrefix("a", "ab"));
    try t.expect(HasPrefix("ab", "a"));
}

// Count counts the number of non-overlapping instances of substr in s.
// If substr is an empty string, Count returns 1 + the number of Unicode code points in s.
pub fn Count(s: string, substr: string) usize {
    if (substr.len == 0) {
        return 1 + (std.unicode.utf8CountCodepoints(s) catch 0);
    }

    if (substr.len > s.len) return 0;

    var count: usize = 0;
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, s, start, substr)) |idx| {
        count += 1;
        start = idx + substr.len;
    }
    return count;
}

test "Count" {
    try std.testing.expectEqual(@as(usize, 3), Count("aaa", "a"));
    try std.testing.expectEqual(@as(usize, 1), Count("banana", "ana"));
    try std.testing.expectEqual(@as(usize, 1), Count("hello", "ll"));
    try std.testing.expectEqual(@as(usize, 0), Count("hello", "x"));
    try std.testing.expectEqual(@as(usize, 0), Count("", "abc"));
    try std.testing.expectEqual(@as(usize, 1), Count("", ""));
    try std.testing.expectEqual(@as(usize, 5), Count("你好世界", "")); // 1 + 4 个码点
    try std.testing.expectEqual(@as(usize, 2), Count("a b c", " "));
}

// Index returns the index of the first instance of substr in s, or -1 if substr is not present in s.
pub fn Index(s: string, substr: string) i32 {
    return if (std.mem.indexOf(u8, s, substr)) |pos|
        @as(i32, @intCast(pos))
    else
        -1;
}

test "Index" {
    const testing = std.testing;

    try testing.expectEqual(@as(i32, 0), Index("hello", "hello"));
    try testing.expectEqual(@as(i32, 2), Index("hello", "ll"));
    try testing.expectEqual(@as(i32, 0), Index("hello", ""));
    try testing.expectEqual(@as(i32, -1), Index("hello", "x"));
    try testing.expectEqual(@as(i32, -1), Index("", "abc"));
    try testing.expectEqual(@as(i32, 0), Index("", ""));
    try testing.expectEqual(@as(i32, 6), Index("你好世界", "世"));
    try testing.expectEqual(@as(i32, -1), Index("你好世界", "啊"));
}

// Replace returns a copy of the string s with the first n
// non-overlapping instances of old replaced by new.
// If old is empty, it matches at the beginning of the string
// and after each UTF-8 sequence, yielding up to k+1 replacements
// for a k-rune string.
// If n < 0, there is no limit on the number of replacements.
pub fn Replace(allocator: std.mem.Allocator, s: string, old: string, new: string, n: i32) !string {
    if (old.len == 0) {
        return replaceEmptyOld(allocator, s, new, n);
    }

    if (n == 0 or old.len > s.len) {
        return try allocator.dupe(u8, s);
    }

    var sb = try std.ArrayList(u8).initCapacity(allocator, 8);
    errdefer sb.deinit(allocator);

    var count: i32 = 0;
    var start: usize = 0;

    while (true) {
        // stop when we've replaced enough
        if (n >= 0 and count >= n) break;
        if (std.mem.indexOfPos(u8, s, start, old)) |pos| {
            // append the text before the old string
            try sb.appendSlice(allocator, s[start..pos]);
            // append the new string
            try sb.appendSlice(allocator, new);
            // advance to the end of the old string
            start = pos + old.len;
            count += 1;
        } else {
            break;
        }
    }

    // append the rest
    try sb.appendSlice(allocator, s[start..]);

    return try sb.toOwnedSlice(allocator);
}

fn replaceEmptyOld(allocator: std.mem.Allocator, s: string, new: string, n: i32) !string {
    if (new.len == 0) {
        return try allocator.dupe(u8, s);
    }

    var sb = try std.ArrayList(u8).initCapacity(allocator, 8);
    errdefer sb.deinit(allocator);

    var insertions: i32 = 0;
    var iter = (std.unicode.Utf8View.init(s) catch |err| {
        std.debug.print("{s}", .{@errorName(err)});
        return LuaError.Panic;
    }).iterator();

    // Insert at the beginning
    if (n != 0 and (n < 0 or insertions < n)) {
        try sb.appendSlice(allocator, new);
        insertions += 1;
    }

    // Insert after each codepoint
    while (iter.nextCodepoint()) |codepoint| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
        try sb.appendSlice(allocator, buf[0..len]);

        if (n < 0 or insertions < n) {
            try sb.appendSlice(allocator, new);
            insertions += 1;
        }
    }

    return try sb.toOwnedSlice(allocator);
}

test "Replace" {
    const t = std.testing;
    const a = t.allocator;

    {
        const got = try Replace(a, "hello hello", "hello", "hi", 1);
        defer a.free(got);
        try t.expectEqualStrings("hi hello", got);
    }
    {
        const got = try Replace(a, "hello hello hello", "hello", "hi", -1);
        defer a.free(got);
        try t.expectEqualStrings("hi hi hi", got);
    }
    {
        const got = try Replace(a, "banana", "ana", "x", -1);
        defer a.free(got);
        try t.expectEqualStrings("bxna", got); // 非重疊
    }
    {
        const got = try Replace(a, "你好世界", "", "-", -1);
        defer a.free(got);
        try t.expectEqualStrings("-你-好-世-界-", got);
    }
    {
        const got = try Replace(a, "abc", "", "x", 2);
        defer a.free(got);
        try t.expectEqualStrings("xaxbc", got); // 最多 3+1 = 4 次，但只做 2 次
    }
    {
        const got = try Replace(a, "hello", "xxx", "yyy", 0);
        defer a.free(got);
        try t.expectEqualStrings("hello", got); // n=0 不替換
    }
}

// TrimSpace returns a slice of the string s, with all leading
// and trailing white space removed, as defined by Unicode.
pub fn TrimSpace(s: string) string {
    if (s.len == 0) return s;

    // Find the start of non-whitespace content
    var start: usize = 0;
    var iter = (std.unicode.Utf8View.init(s) catch return s).iterator();
    while (iter.nextCodepoint()) |codepoint| {
        if (!isUnicodeWhitespace(codepoint)) {
            break;
        }
        start = iter.i;
    }

    if (start >= s.len) return s[s.len..s.len]; // All whitespace

    // Find the end of non-whitespace content (work backwards)
    var end: usize = s.len;
    var last_non_ws_end: usize = s.len;

    // Reset iterator and find last non-whitespace position
    var reverse_iter = (std.unicode.Utf8View.init(s) catch return s).iterator();
    while (reverse_iter.nextCodepoint()) |codepoint| {
        if (!isUnicodeWhitespace(codepoint)) {
            last_non_ws_end = reverse_iter.i;
        }
    }
    end = last_non_ws_end;

    return s[start..end];
}

fn isUnicodeWhitespace(codepoint: u21) bool {
    return switch (codepoint) {
        // ASCII whitespace
        0x09, // TAB
        0x0A, // LF
        0x0B, // VT
        0x0C, // FF
        0x0D, // CR
        0x20, // SPACE
        // Unicode whitespace
        0x85, // NEL (Next Line)
        0xA0, // NBSP (Non-breaking space)
        0x1680, // OGHAM SPACE MARK
        0x2000, // EN QUAD
        0x2001, // EM QUAD
        0x2002, // EN SPACE
        0x2003, // EM SPACE
        0x2004, // THREE-PER-EM SPACE
        0x2005, // FOUR-PER-EM SPACE
        0x2006, // SIX-PER-EM SPACE
        0x2007, // FIGURE SPACE
        0x2008, // PUNCTUATION SPACE
        0x2009, // THIN SPACE
        0x200A, // HAIR SPACE
        0x2028, // LINE SEPARATOR
        0x2029, // PARAGRAPH SEPARATOR
        0x202F, // NARROW NO-BREAK SPACE
        0x205F, // MEDIUM MATHEMATICAL SPACE
        0x3000, // IDEOGRAPHIC SPACE
        => true,
        else => false,
    };
}

test "TrimSpace" {
    const t = std.testing;

    // basis
    try t.expectEqualStrings("hello", TrimSpace("hello"));
    try t.expectEqualStrings("hello", TrimSpace("  hello  "));
    try t.expectEqualStrings("hello world", TrimSpace("  hello world  "));
    try t.expectEqualStrings("", TrimSpace("   "));
    try t.expectEqualStrings("", TrimSpace(""));

    // Unicode whitespace
    try t.expectEqualStrings("hello", TrimSpace("\u{2000}hello\u{3000}")); // 不同宽度的空格
    try t.expectEqualStrings("你好", TrimSpace("　你好　")); // 全形空格
    try t.expectEqualStrings("test", TrimSpace("\t\r\n test \n\r\t"));
    try t.expectEqualStrings("a b c", TrimSpace("  a b c  "));

    // edge cases
    try t.expectEqualStrings("hello", TrimSpace("hello\n"));
    try t.expectEqualStrings("hello", TrimSpace("\nhello"));
    try t.expectEqualStrings("hello", TrimSpace("\n  hello  \n"));
    try t.expectEqualStrings("hello", TrimSpace("hello"));
    try t.expectEqualStrings("", TrimSpace("\u{2028}\u{2029}")); // 行分隔符

    // mixture
    try t.expectEqualStrings("こんにちは", TrimSpace("　こんにちは　"));
    try t.expectEqualStrings("😊 world", TrimSpace("  😊 world  "));
}

// ToLower returns s with all Unicode letters mapped to their lower case.
pub fn ToLower(allocator: std.mem.Allocator, s: string) !string {
    var sb = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer sb.deinit(allocator);

    for (s) |c| {
        if (std.ascii.isUpper(c)) {
            try sb.append(allocator, std.ascii.toLower(c));
        } else {
            try sb.append(allocator, c);
        }
    }

    return try sb.toOwnedSlice(allocator);
}

test "ToLower ASCII" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        const result = try ToLower(allocator, "Hello World 123 !@#");
        defer allocator.free(result);
        try testing.expectEqualStrings("hello world 123 !@#", result);
    }
    {
        const result = try ToLower(allocator, "abcXYZ");
        defer allocator.free(result);
        try testing.expectEqualStrings("abcxyz", result);
    }
    {
        const result = try ToLower(allocator, "");
        defer allocator.free(result);
        try testing.expectEqualStrings("", result);
    }
    {
        const result = try ToLower(allocator, "1234567890");
        defer allocator.free(result);
        try testing.expectEqualStrings("1234567890", result);
    }
}

// ToUpper returns s with all Unicode letters mapped to their upper case.
pub fn ToUpper(allocator: std.mem.Allocator, s: string) !string {
    var sb = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer sb.deinit(allocator);

    for (s) |c| {
        if (std.ascii.isLower(c)) {
            try sb.append(allocator, std.ascii.toUpper(c));
        } else {
            try sb.append(allocator, c);
        }
    }

    return try sb.toOwnedSlice(allocator);
}

test "ToUpper ASCII" {
    const testing = std.testing;
    const allocator = testing.allocator;

    {
        const result = try ToUpper(allocator, "Hello World 123 !@#");
        defer allocator.free(result);
        try testing.expectEqualStrings("HELLO WORLD 123 !@#", result);
    }

    {
        const result = try ToUpper(allocator, "abcXYZ");
        defer allocator.free(result);
        try testing.expectEqualStrings("ABCXYZ", result);
    }

    {
        const result = try ToUpper(allocator, "");
        defer allocator.free(result);
        try testing.expectEqualStrings("", result);
    }

    {
        const result = try ToUpper(allocator, "1234567890");
        defer allocator.free(result);
        try testing.expectEqualStrings("1234567890", result);
    }
}

// Contains reports whether substr is within s.
pub fn Contains(s: string, substr: string) bool {
    return std.mem.indexOf(u8, s, substr) != null;
}

test "Contains" {
    const t = std.testing;

    // basic cases
    try t.expect(Contains("hello", "hello"));
    try t.expect(Contains("hello world", "hello"));
    try t.expect(Contains("hello world", "world"));
    try t.expect(Contains("hello world", "lo wo"));
    try t.expect(Contains("hello", "ll"));
    try t.expect(Contains("hello", "h"));
    try t.expect(Contains("hello", "o"));

    // not contains cases
    try t.expect(!Contains("hello", "helloo"));
    try t.expect(!Contains("hello", "elloo"));
    try t.expect(!Contains("hello", "xyz"));
    try t.expect(!Contains("hello", "Hello")); // 大小寫敏感

    // empty cases
    try t.expect(Contains("", ""));
    try t.expect(Contains("anything", ""));
    try t.expect(!Contains("", "a"));
    try t.expect(!Contains("", "abc"));

    // unicode cases
    try t.expect(Contains("你好世界", "你好"));
    try t.expect(Contains("你好世界", "世界"));
    try t.expect(Contains("你好世界", "好世"));
    try t.expect(Contains("こんにちは世界", "ちは世"));
    try t.expect(!Contains("你好世界", "你世界"));
    try t.expect(!Contains("你好世界", "啊"));

    // edge cases
    try t.expect(Contains("a", "a"));
    try t.expect(!Contains("a", "ab"));
    try t.expect(Contains("ab", "a"));
    try t.expect(Contains("ab", "b"));
    try t.expect(Contains(" spaces ", " "));
    try t.expect(Contains("\t\n\r", "\n"));
    try t.expect(Contains("😊😂", "😂"));
    try t.expect(!Contains("😊😂", "😄"));
}

// Split slices s into all substrings separated by sep and returns a slice of
// the substrings between those separators.
//
// If s does not contain sep and sep is not empty, Split returns a
// slice of length 1 whose only element is s.
//
// If sep is empty, Split splits after each UTF-8 sequence. If both s
// and sep are empty, Split returns an empty slice.
pub fn Split(allocator: std.mem.Allocator, s: string, sep: string) ![]string {
    var list = try std.ArrayList(string).initCapacity(allocator, 8);
    errdefer list.deinit(allocator);

    if (sep.len == 0) {
        if (s.len == 0) return try list.toOwnedSlice(allocator);
        var iter = (std.unicode.Utf8View.init(s) catch |err| {
            std.debug.print("{s}", .{@errorName(err)});
            return LuaError.Panic;
        }).iterator();
        while (iter.nextCodepointSlice()) |slice| {
            try list.append(allocator, slice);
        }
        return list.toOwnedSlice(allocator);
    }

    var start: usize = 0;
    while (std.mem.indexOfPos(u8, s, start, sep)) |pos| {
        try list.append(allocator, s[start..pos]);
        start = pos + sep.len;
    }
    try list.append(allocator, s[start..]);

    return list.toOwnedSlice(allocator);
}

test "Split normal sep" {
    const t = std.testing;
    const a = t.allocator;

    {
        const parts = try Split(a, "a,b,c", ",");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 3), parts.len);
        try t.expectEqualStrings("a", parts[0]);
        try t.expectEqualStrings("b", parts[1]);
        try t.expectEqualStrings("c", parts[2]);
    }

    {
        const parts = try Split(a, "hello world", " ");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 2), parts.len);
        try t.expectEqualStrings("hello", parts[0]);
        try t.expectEqualStrings("world", parts[1]);
    }

    {
        const parts = try Split(a, "banana", "ana");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 2), parts.len);
        try t.expectEqualStrings("b", parts[0]);
        try t.expectEqualStrings("na", parts[1]);
    }
}

test "Split empty sep (split by rune)" {
    const t = std.testing;
    const a = t.allocator;

    {
        const parts = try Split(a, "你好世界", "");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 4), parts.len);
        try t.expectEqualStrings("你", parts[0]);
        try t.expectEqualStrings("好", parts[1]);
        try t.expectEqualStrings("世", parts[2]);
        try t.expectEqualStrings("界", parts[3]);
    }

    {
        const parts = try Split(a, "abc😊123", "");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 7), parts.len);
        try t.expectEqualStrings("a", parts[0]);
        try t.expectEqualStrings("b", parts[1]);
        try t.expectEqualStrings("c", parts[2]);
        try t.expectEqualStrings("😊", parts[3]);
        try t.expectEqualStrings("1", parts[4]);
        try t.expectEqualStrings("2", parts[5]);
        try t.expectEqualStrings("3", parts[6]);
    }
}

test "Split edge cases" {
    const t = std.testing;
    const a = t.allocator;

    // s is empty while sep is not
    {
        const parts = try Split(a, "", ",");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 1), parts.len);
        try t.expectEqualStrings("", parts[0]);
    }

    // s !contains sep
    {
        const parts = try Split(a, "hello", ",");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 1), parts.len);
        try t.expectEqualStrings("hello", parts[0]);
    }

    // s and sep both are empty -> return empty
    {
        const parts = try Split(a, "", "");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 0), parts.len);
    }

    // contiguous sep
    {
        const parts = try Split(a, "a,,b,,c", ",");
        defer a.free(parts);

        try t.expectEqual(@as(usize, 5), parts.len);
        try t.expectEqualStrings("a", parts[0]);
        try t.expectEqualStrings("", parts[1]);
        try t.expectEqualStrings("b", parts[2]);
        try t.expectEqualStrings("", parts[3]);
        try t.expectEqualStrings("c", parts[4]);
    }
}

// Join concatenates the elements of its first argument to create a single string. The separator
// string sep is placed between elements in the resulting string.
pub fn Join(allocator: std.mem.Allocator, elements: []const string, sep: string) !string {
    if (elements.len == 0) {
        return try allocator.dupe(u8, "");
    }

    if (elements.len == 1) {
        return try allocator.dupe(u8, elements[0]);
    }

    var total_len: usize = elements[0].len;
    for (elements[1..]) |item| {
        total_len += sep.len + item.len;
    }

    var sb = try std.ArrayList(u8).initCapacity(allocator, total_len);
    errdefer sb.deinit(allocator);

    try sb.appendSlice(allocator, elements[0]);
    for (elements[1..]) |item| {
        try sb.appendSlice(allocator, sep);
        try sb.appendSlice(allocator, item);
    }

    return try sb.toOwnedSlice(allocator);
}

test "Join" {
    const t = std.testing;
    const a = t.allocator;

    // basis
    {
        {
            const parts = [_][]const u8{ "hello", "world" };
            const result = try Join(a, &parts, " ");
            defer a.free(result);
            try t.expectEqualStrings("hello world", result);
        }

        {
            const parts = [_][]const u8{ "a", "b", "c" };
            const result = try Join(a, &parts, ",");
            defer a.free(result);
            try t.expectEqualStrings("a,b,c", result);
        }

        {
            const parts = [_][]const u8{ "zig", "is", "fun" };
            const result = try Join(a, &parts, " - ");
            defer a.free(result);
            try t.expectEqualStrings("zig - is - fun", result);
        }
    }

    // edge cases
    {

        // [0]T
        {
            const parts: []const []const u8 = &[_][]const u8{};
            const result = try Join(a, parts, ",");
            defer a.free(result);
            try t.expectEqualStrings("", result);
        }

        // [1]T
        {
            const parts = [_][]const u8{"alone"};
            const result = try Join(a, &parts, "whatever");
            defer a.free(result);
            try t.expectEqualStrings("alone", result);
        }

        // sep = ""
        {
            const parts = [_][]const u8{ "a", "b", "c" };
            const result = try Join(a, &parts, "");
            defer a.free(result);
            try t.expectEqualStrings("abc", result);
        }

        // empty element
        {
            const parts = [_][]const u8{ "", "middle", "" };
            const result = try Join(a, &parts, "-");
            defer a.free(result);
            try t.expectEqualStrings("-middle-", result);
        }

        // unicode & emojis
        {
            const parts = [_][]const u8{ "你好", "世界", "😊" };
            const result = try Join(a, &parts, " | ");
            defer a.free(result);
            try t.expectEqualStrings("你好 | 世界 | 😊", result);
        }
    }
}

// IndexByte returns the index of the first instance of c in s, or -1 if c is not present in s.
pub fn IndexByte(s: string, c: u8) i32 {
    return if (std.mem.indexOfScalar(u8, s, c)) |pos|
        @as(i32, @intCast(pos))
    else
        -1;
}

test "IndexByte" {
    const t = std.testing;

    // basis
    try t.expectEqual(@as(i32, 0), IndexByte("hello", 'h'));
    try t.expectEqual(@as(i32, 2), IndexByte("hello", 'l'));
    try t.expectEqual(@as(i32, 4), IndexByte("hello", 'o'));
    try t.expectEqual(@as(i32, -1), IndexByte("hello", 'x'));

    // case sensitive
    try t.expectEqual(@as(i32, -1), IndexByte("Hello", 'h'));

    // edge cases
    try t.expectEqual(@as(i32, -1), IndexByte("", 'a'));
    try t.expectEqual(@as(i32, 0), IndexByte("a", 'a'));
    try t.expectEqual(@as(i32, -1), IndexByte("a", 'b'));

    // control characters
    try t.expectEqual(@as(i32, 5), IndexByte("hello\nworld", '\n'));
    try t.expectEqual(@as(i32, 0), IndexByte("\tleading", '\t'));
    try t.expectEqual(@as(i32, 0), IndexByte(" space", ' '));

    // duplicate bytes return first found index
    try t.expectEqual(@as(i32, 2), IndexByte("banana", 'n'));
    try t.expectEqual(@as(i32, 0), IndexByte("aaaaa", 'a'));
}
