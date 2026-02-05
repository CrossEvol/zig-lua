const std = @import("std");

const Block = @import("../ast/block.zig").Block;
const Exp = @import("../ast/exp.zig").Exp;
const Stat = @import("../ast/stat.zig").Stat;
const LexerPkg = @import("../lexer/lexer.zig");
const Lexer = LexerPkg.Lexer;
const TokenKind = @import("../lexer/token.zig").TokenKind;
const parseExpList = @import("parse_exp.zig").parseExpList;
const ParserError = @import("parser.zig").ParserError;
const parseStat = @import("parse_stat.zig").parseStat;

// block ::= {stat} [retstat]
pub fn parseBlock(lexer: *Lexer) ParserError!Block {
    const stats = try parseStats(lexer);
    const ret_exps = try parseRetExps(lexer);
    return .{
        .stats = stats,
        .ret_exps = ret_exps,
        .last_line = lexer.line,
    };
}

fn parseStats(lexer: *Lexer) ParserError![]Stat {
    var stats = try std.ArrayList(Stat).initCapacity(lexer.allocator, 8);
    while (!_isReturnOrBlockEnd(lexer.lookAhead())) {
        const stat = try parseStat(lexer);
        switch (stat) {
            .empty_stat => {},
            else => try stats.append(lexer.allocator, stat),
        }
    }
    return try stats.toOwnedSlice(lexer.allocator);
}

fn _isReturnOrBlockEnd(tokenKind: TokenKind) bool {
    return switch (tokenKind) {
        .token_kw_return, .token_eof, .token_kw_end, .token_kw_else, .token_kw_elseif, .token_kw_until => true,
        else => false,
    };
}

// retstat ::= return [explist] [‘;’]
// explist ::= exp {‘,’ exp}
fn parseRetExps(lexer: *Lexer) ParserError!?[]Exp {
    if (lexer.lookAhead() != .token_kw_return) {
        return null;
    }

    _ = try lexer.nextToken();
    const empty_exps = try lexer.allocator.alloc(Exp, 0);
    return switch (lexer.lookAhead()) {
        .token_eof, .token_kw_end, .token_kw_else, .token_kw_elseif, .token_kw_until => empty_exps,
        .token_sep_semi => {
            _ = try lexer.nextToken();
            return empty_exps;
        },
        else => {
            const exps = try parseExpList(lexer);
            if (lexer.lookAhead() == .token_sep_semi) {
                _ = try lexer.nextToken();
            }
            return exps;
        },
    };
}
