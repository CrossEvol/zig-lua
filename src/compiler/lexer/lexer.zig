const std = @import("std");
const testing = std.testing;

const regex = @import("pcrez");

const strings = @import("../../api/root.zig").strings;
const keywords = @import("token.zig").keywords;
const TokenKind = @import("token.zig").TokenKind;

const string = []const u8;

const re_newLine_pattern =
    \\\r\n|\n\r|\n|\r
;
const re_identifier_pattern =
    \\^[_\d\w]+
;
const re_number_pattern =
    \\^0[xX][0-9a-fA-F]*(\.[0-9a-fA-F]*)?([pP][+\-]?[0-9]+)?|^[0-9]*(\.[0-9]*)?([eE][+\-]?[0-9]+)?
;
const re_short_pattern =
    \\(?s)(^'(\\\\|\\'|\\\n|\\z\s*|[^'\n])*')|(^"(\\\\|\\"|\\\n|\\z\s*|[^"\n])*")
;
const re_opening_long_bracket_pattern =
    \\^\[=*\[
;
const re_dec_escape_pattern =
    \\^\\[0-9]{1,3}
;
const re_hex_escape_pattern =
    \\^\\x[0-9a-fA-F]{2}
;
const re_unicode_escape_pattern =
    \\^\\u\{[0-9a-fA-F]+\}
;
// const re_integer_pattern =
//     \\^[+-]?[0-9]+$|^-?0x[0-9a-f]+$
// ;
// const re_hex_float_pattern =
//     \\^([0-9a-f]+(\.[0-9a-f]*)?|([0-9a-f]*\.[0-9a-f]+))(p[+\-]?[0-9]+)?$
// ;

pub const LexerError = error{
    SyntaxError,
    UnexpectedSymbol,
    InvalidLongStringDelimiter,
    UnfinishedLongStringOrComment,
    UnfinishedString,
    DecimalEscapeTooLarge,
    UTF8ValueTooLarge,
    InvalidEscapeSequence,
    Unreachable,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    chunk: string,
    chunk_name: string,
    line: i32,
    pos: usize,
    next_token: string,
    next_token_kind: TokenKind,
    next_token_line: i32,

    // Compiled regexes
    re_newline: regex.Regex,
    re_identifier: regex.Regex,
    re_number: regex.Regex,
    re_short_str: regex.Regex,
    re_opening_long_bracket: regex.Regex,
    re_dec_escape_seq: regex.Regex,
    re_hex_escape_seq: regex.Regex,
    re_unicode_escape_seq: regex.Regex,

    pub fn init(allocator: std.mem.Allocator, chunk: string, chunk_name: string) Lexer {
        const re_newline = regex.Regex.from(re_newLine_pattern, true, allocator) catch @panic("regex compiled error");
        const re_identifier = regex.Regex.from(re_identifier_pattern, true, allocator) catch @panic("regex compiled error");
        const re_number = regex.Regex.from(re_number_pattern, true, allocator) catch @panic("regex compiled error");
        const re_short_str = regex.Regex.from(re_short_pattern, true, allocator) catch @panic("regex compiled error");
        const re_opening_long_bracket = regex.Regex.from(re_opening_long_bracket_pattern, true, allocator) catch @panic("regex compiled error");
        const re_dec_escape_seq = regex.Regex.from(re_dec_escape_pattern, true, allocator) catch @panic("regex compiled error");
        const re_hex_escape_seq = regex.Regex.from(re_hex_escape_pattern, true, allocator) catch @panic("regex compiled error");
        const re_unicode_escape_seq = regex.Regex.from(re_unicode_escape_pattern, true, allocator) catch @panic("regex compiled error");

        return .{
            .allocator = allocator,
            .chunk = chunk,
            .chunk_name = chunk_name,
            .line = 1,
            .pos = 0,
            .next_token = "",
            .next_token_kind = .token_eof,
            .next_token_line = 0,
            .re_newline = re_newline,
            .re_identifier = re_identifier,
            .re_number = re_number,
            .re_short_str = re_short_str,
            .re_opening_long_bracket = re_opening_long_bracket,
            .re_dec_escape_seq = re_dec_escape_seq,
            .re_hex_escape_seq = re_hex_escape_seq,
            .re_unicode_escape_seq = re_unicode_escape_seq,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.re_newline.deinit();
        self.re_identifier.deinit();
        self.re_number.deinit();
        self.re_short_str.deinit();
        self.re_opening_long_bracket.deinit();
        self.re_dec_escape_seq.deinit();
        self.re_hex_escape_seq.deinit();
        self.re_unicode_escape_seq.deinit();
    }

    pub fn lookAhead(self: *Lexer) TokenKind {
        if (self.next_token_line > 0) {
            return self.next_token_kind;
        }

        const current_line = self.line;
        const line, const kind, const token = self.nextToken() catch @panic("look ahead failed");
        self.line = current_line;
        self.next_token_line = line;
        self.next_token_kind = kind;
        self.next_token = token;
        return kind;
    }

    /// -> ( line: i32, token: string )
    pub fn nextIdentifier(self: *Lexer) !struct { i32, string } {
        return try self.nextTokenOfKind(.token_identifier);
    }

    /// -> ( line: i32, token: string )
    pub fn nextTokenOfKind(self: *Lexer, kind: TokenKind) !struct { i32, string } {
        const line, const _kind, const token = try self.nextToken();
        if (kind != _kind) {
            return self.@"error"(LexerError.SyntaxError, "syntax error near '{s}'", .{token});
        }
        return .{ line, token };
    }

    /// -> (line: i32, kind: TokenKind, token: string)
    ///
    /// -> (line: i32, op: TokenKind, token: string)
    pub fn nextToken(self: *Lexer) !struct { i32, TokenKind, string } {
        if (self.next_token_line > 0) {
            const line = self.next_token_line;
            const kind = self.next_token_kind;
            const token = self.next_token;
            self.line = self.next_token_line;
            self.next_token_line = 0;
            return .{ line, kind, token };
        }

        try self.skipWhiteSpaces();
        if (self.chunk.len == 0) {
            return .{ self.line, .token_eof, "EOF" };
        }

        switch (self.chunk[0]) {
            ';' => {
                self.next(1);
                return .{ self.line, .token_sep_semi, ";" };
            },
            ',' => {
                self.next(1);
                return .{ self.line, .token_sep_comma, "," };
            },
            '(' => {
                self.next(1);
                return .{ self.line, .token_sep_lparen, "(" };
            },
            ')' => {
                self.next(1);
                return .{ self.line, .token_sep_rparen, ")" };
            },
            ']' => {
                self.next(1);
                return .{ self.line, .token_sep_rbrack, "]" };
            },
            '{' => {
                self.next(1);
                return .{ self.line, .token_sep_lcurly, "{" };
            },
            '}' => {
                self.next(1);
                return .{ self.line, .token_sep_rcurly, "}" };
            },
            '+' => {
                self.next(1);
                return .{ self.line, .token_op_add, "+" };
            },
            '-' => {
                self.next(1);
                return .{ self.line, .token_op_minus, "-" };
            },
            '*' => {
                self.next(1);
                return .{ self.line, .token_op_mul, "*" };
            },
            '^' => {
                self.next(1);
                return .{ self.line, .token_op_pow, "^" };
            },
            '%' => {
                self.next(1);
                return .{ self.line, .token_op_mod, "%" };
            },
            '&' => {
                self.next(1);
                return .{ self.line, .token_op_band, "&" };
            },
            '|' => {
                self.next(1);
                return .{ self.line, .token_op_bor, "|" };
            },
            '#' => {
                self.next(1);
                return .{ self.line, .token_op_len, "#" };
            },
            ':' => {
                if (self.@"test"("::")) {
                    self.next(2);
                    return .{ self.line, .token_sep_label, "::" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_sep_colon, ":" };
                }
            },
            '/' => {
                if (self.@"test"("//")) {
                    self.next(2);
                    return .{ self.line, .token_op_idiv, "//" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_op_div, "/" };
                }
            },
            '~' => {
                if (self.@"test"("~=")) {
                    self.next(2);
                    return .{ self.line, .token_op_ne, "~=" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_op_wave, "~" };
                }
            },
            '=' => {
                if (self.@"test"("==")) {
                    self.next(2);
                    return .{ self.line, .token_op_eq, "==" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_op_assign, "=" };
                }
            },
            '<' => {
                if (self.@"test"("<<")) {
                    self.next(2);
                    return .{ self.line, .token_op_shl, "<<" };
                } else if (self.@"test"("<=")) {
                    self.next(2);
                    return .{ self.line, .token_op_le, "<=" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_op_lt, "<" };
                }
            },
            '>' => {
                if (self.@"test"(">>")) {
                    self.next(2);
                    return .{ self.line, .token_op_shr, ">>" };
                } else if (self.@"test"(">=")) {
                    self.next(2);
                    return .{ self.line, .token_op_ge, ">=" };
                } else {
                    self.next(1);
                    return .{ self.line, .token_op_gt, ">" };
                }
            },
            '.' => {
                if (self.@"test"("...")) {
                    self.next(3);
                    return .{ self.line, .token_vararg, "..." };
                } else if (self.@"test"("..")) {
                    self.next(2);
                    return .{ self.line, .token_op_concat, ".." };
                } else if (self.chunk.len == 1 or !isDigit(self.chunk[1])) {
                    self.next(1);
                    return .{ self.line, .token_sep_dot, "." };
                }
            },
            '[' => {
                if (self.@"test"("[[") or self.@"test"("[=")) {
                    const long_string = try self.scanLongString();
                    return .{ self.line, .token_string, try self.allocator.dupe(u8, long_string) };
                } else {
                    self.next(1);
                    return .{ self.line, .token_sep_lbrack, "[" };
                }
            },
            '\'', '"' => {
                const short_string = try self.scanShortString();
                return .{ self.line, .token_string, short_string };
            },
            else => {},
        }

        const c = self.chunk[0];
        if (c == '.' or isDigit(c)) {
            const token = try self.scanNumber();
            return .{ self.line, .token_number, token };
        }
        if (c == '_' or isLetter(c)) {
            const token = try self.scanIdentifier();
            if (keywords.get(token)) |kind| {
                return .{ self.line, kind, token };
            } else {
                return .{ self.line, .token_identifier, token };
            }
        }

        return self.@"error"(LexerError.UnexpectedSymbol, "unexpected symbol near {c}", .{c});
    }

    fn next(self: *Lexer, n: usize) void {
        self.chunk = self.chunk[n..];
    }

    fn @"test"(self: *Lexer, s: string) bool {
        return strings.HasPrefix(self.chunk, s);
    }

    fn @"error"(self: *const Lexer, err: LexerError, comptime fmt: string, args: anytype) LexerError {
        std.debug.print("{s}:{d}:", .{ self.chunk_name, self.line });
        std.debug.print(fmt, args);
        std.debug.print("\n", .{});
        return err;
    }

    fn skipWhiteSpaces(self: *Lexer) !void {
        while (self.chunk.len > 0) {
            if (self.@"test"("--")) {
                try self.skipComment();
            } else if (self.@"test"("\r\n") or self.@"test"("\n\r")) {
                self.next(2);
                self.line += 1;
            } else if (isNewline(self.chunk[0])) {
                self.next(1);
                self.line += 1;
            } else if (isWhiteSpace(self.chunk[0])) {
                self.next(1);
            } else {
                break;
            }
        }
    }

    fn skipComment(self: *Lexer) !void {
        self.next(2); // skip --

        // long comment ?
        if (self.@"test"("[")) {
            if (!std.mem.eql(u8, self.re_opening_long_bracket.findString(self.chunk), "")) {
                _ = try self.scanLongString();
                return;
            }
        }

        // short comment
        while (self.chunk.len > 0 and !isNewline(self.chunk[0])) {
            self.next(1);
        }
    }

    fn scanIdentifier(self: *Lexer) !string {
        return try self.scan(&self.re_identifier);
    }

    fn scanNumber(self: *Lexer) !string {
        return try self.scan(&self.re_number);
    }

    fn scan(self: *Lexer, re: *regex.Regex) !string {
        const token = re.findString(self.chunk);
        if (!std.mem.eql(u8, token, "")) {
            self.next(token.len);
            return self.allocator.dupe(u8, token);
        }

        return LexerError.Unreachable;
    }

    fn scanLongString(self: *Lexer) !string {
        const opening_long_bracket = self.re_opening_long_bracket.findString(self.chunk);
        if (std.mem.eql(u8, opening_long_bracket, "")) {
            return self.@"error"(LexerError.InvalidLongStringDelimiter, "invalid long string delimiter near '{s}'", .{self.chunk[0..2]});
        }

        const closing_long_bracket = try strings.Replace(self.allocator, opening_long_bracket, "[", "]", -1);
        const closing_long_bracket_idx = strings.Index(self.chunk, closing_long_bracket);
        if (closing_long_bracket_idx < 0) {
            return self.@"error"(LexerError.UnfinishedLongStringOrComment, "unfinished long string or comment", .{});
        }

        const str = self.chunk[opening_long_bracket.len..@as(usize, @intCast(closing_long_bracket_idx))];
        self.next(@as(usize, @intCast(closing_long_bracket_idx)) + closing_long_bracket.len);

        var a = self.re_newline.replaceAllString(str, "\n").?;
        defer a.deinit();
        const replaced_str = a.allocatedSlice()[0..a.items.len];
        self.line += @intCast(strings.Count(replaced_str, "\n"));
        if (replaced_str.len > 0 and replaced_str[0] == '\n') {
            return self.allocator.dupe(u8, replaced_str[1..]);
        }

        return self.allocator.dupe(u8, replaced_str);
    }

    fn scanShortString(self: *Lexer) !string {
        const str = self.re_short_str.findString(self.chunk);
        if (!std.mem.eql(u8, str, "")) {
            self.next(str.len);
            const replaced_str = str[1 .. str.len - 1];
            if (strings.Contains(replaced_str, "\\")) {
                const all_strings = self.re_newline.findAllString(replaced_str, -1, self.allocator);
                self.line += @intCast(if (all_strings) |ss| ss.len else 0);
                return try self.escape(replaced_str);
            }
            return self.allocator.dupe(u8, replaced_str);
        }

        return self.@"error"(LexerError.UnfinishedString, "unfinished string", .{});
    }

    fn escape(self: *Lexer, s: string) !string {
        var str = s;
        var buf = try std.ArrayList(u8).initCapacity(self.allocator, str.len);
        errdefer buf.deinit(self.allocator);

        while (str.len > 0) {
            if (str[0] != '\\') {
                try buf.append(self.allocator, str[0]);
                str = str[1..];
                continue;
            }

            if (str.len == 1) {
                return self.@"error"(LexerError.UnfinishedString, "unfinished string", .{});
            }

            switch (str[1]) {
                'a' => {
                    try buf.append(self.allocator, '\x07');
                    str = str[2..];
                    continue;
                },
                'b' => {
                    try buf.append(self.allocator, '\x08');
                    str = str[2..];
                    continue;
                },
                'f' => {
                    try buf.append(self.allocator, '\x0C');
                    str = str[2..];
                    continue;
                },
                'n' => {
                    try buf.append(self.allocator, '\n');
                    str = str[2..];
                    continue;
                },
                'r' => {
                    try buf.append(self.allocator, '\r');
                    str = str[2..];
                    continue;
                },
                't' => {
                    try buf.append(self.allocator, '\t');
                    str = str[2..];
                    continue;
                },
                'v' => {
                    try buf.append(self.allocator, '\x0B');
                    str = str[2..];
                    continue;
                },
                '"' => {
                    try buf.append(self.allocator, '"');
                    str = str[2..];
                    continue;
                },
                '\'' => {
                    try buf.append(self.allocator, '\'');
                    str = str[2..];
                    continue;
                },
                '\\' => {
                    try buf.append(self.allocator, '\\');
                    str = str[2..];
                    continue;
                },
                '0'...'9' => { // \ddd
                    const found = self.re_dec_escape_seq.findString(str);
                    if (!std.mem.eql(u8, found, "")) {
                        const d = std.fmt.parseInt(i32, found[1..], 10) catch 0;
                        if (d < 0xFF) {
                            try buf.append(self.allocator, @as(u8, @intCast(d)));
                            str = str[found.len..];
                            continue;
                        }
                        return self.@"error"(LexerError.DecimalEscapeTooLarge, "decimal escape too large near '{s}'", .{found});
                    }
                },
                'x' => { // \xXX
                    const found = self.re_hex_escape_seq.findString(str);
                    if (!std.mem.eql(u8, found, "")) {
                        const d = std.fmt.parseInt(i32, found[2..], 16) catch 0;
                        try buf.append(self.allocator, @as(u8, @intCast(d)));
                        str = str[found.len..];
                        continue;
                    }
                },
                'u' => { // \u{XXX}
                    const found = self.re_unicode_escape_seq.findString(str);
                    if (!std.mem.eql(u8, found, "")) {
                        if (std.fmt.parseInt(i32, found[3 .. found.len - 1], 16)) |d| {
                            if (d <= 0x10FFFF) {
                                var utf8_buf: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(@intCast(d), &utf8_buf) catch unreachable;
                                try buf.appendSlice(self.allocator, utf8_buf[0..len]);
                                str = str[found.len..];
                                continue;
                            } else {
                                return self.@"error"(LexerError.UTF8ValueTooLarge, "UTF-8 value too large near '{s}'", .{found});
                            }
                        } else |_| {
                            return self.@"error"(LexerError.UTF8ValueTooLarge, "UTF-8 value too large near '{s}'", .{found});
                        }
                    }
                },
                'z' => {
                    str = str[2..];
                    while (str.len > 0 and isWhiteSpace(str[0])) {
                        str = str[1..];
                    }
                    continue;
                },
                else => {
                    return self.@"error"(LexerError.InvalidEscapeSequence, "invalid escape sequence near '\\{c}'", .{str[1]});
                },
            }
        }

        return buf.toOwnedSlice(self.allocator);
    }

    fn isWhiteSpace(c: u8) bool {
        return switch (c) {
            '\t', '\n', '\x0B', '\x0C', '\r', ' ' => true,
            else => false,
        };
    }

    fn isNewline(c: u8) bool {
        return c == '\r' or c == '\n';
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isLetter(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }
};

test "verify all regex patterns compile" {
    const patterns = [_][]const u8{
        re_newLine_pattern,
        re_identifier_pattern,
        re_number_pattern,
        re_short_pattern,
        re_opening_long_bracket_pattern,
        re_dec_escape_pattern,
        re_hex_escape_pattern,
        re_unicode_escape_pattern,
    };

    const pattern_names = [_][]const u8{
        "re_newLine_pattern",
        "re_identifier_pattern",
        "re_number_pattern",
        "re_short_pattern",
        "re_opening_long_bracket_pattern",
        "re_dec_escape_pattern",
        "re_hex_escape_pattern",
        "re_unicode_escape_pattern",
    };

    for (patterns, pattern_names) |pattern, name| {
        var re = regex.Regex.from(pattern, true, testing.allocator) catch |err| {
            std.debug.print("Failed to compile pattern '{s}': {s}\n", .{ name, pattern });
            return err;
        };
        defer re.deinit();

        try testing.expect(re.isValid());
        std.debug.print("✓ Pattern '{s}' compiled successfully\n", .{name});
    }
}
