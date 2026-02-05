const std = @import("std");

const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const NameExp = ExpPkg.NameExp;
const ParensExp = ExpPkg.ParensExp;
const VarargExp = ExpPkg.VarargExp;
const FuncCallExp = ExpPkg.FuncCallExp;
const TableAccessExp = ExpPkg.TableAccessExp;
const StringExp = ExpPkg.StringExp;
const LexerPkg = @import("../lexer/lexer.zig");
const Lexer = LexerPkg.Lexer;
const parseExp = @import("parse_exp.zig").parseExp;
const parseExpList = @import("parse_exp.zig").parseExpList;
const ParserError = @import("parser.zig").ParserError;
const parseTableConstructorExp = @import("parse_exp.zig").parseTableConstructorExp;

// prefixexp ::= var | functioncall | ‘(’ exp ‘)’
// var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name
// functioncall ::=  prefixexp args | prefixexp ‘:’ Name args

// prefixexp ::= Name
//
//      | ‘(’ exp ‘)’
//      | prefixexp ‘[’ exp ‘]’
//      | prefixexp ‘.’ Name
//      | prefixexp [‘:’ Name] args
pub fn parsePrefixExp(lexer: *Lexer) ParserError!Exp {
    var exp: Exp = undefined;
    if (lexer.lookAhead() == .token_identifier) {
        const line, const name = try lexer.nextIdentifier(); // Name
        exp = .{ .name_exp = NameExp.init(line, name) };
    } else { // ‘(’ exp ‘)’
        exp = try parseParensExp(lexer);
    }
    return try _finishPrefixExp(lexer, exp);
}

fn parseParensExp(lexer: *Lexer) ParserError!Exp {
    _ = try lexer.nextTokenOfKind(.token_sep_lparen); // (
    const exp = try parseExp(lexer); // exp
    _ = try lexer.nextTokenOfKind(.token_sep_rparen); // )

    return switch (exp) {
        .vararg_exp, .func_call_exp, .name_exp, .table_access_exp => {
            const parent_exp = try lexer.allocator.create(ParensExp);
            parent_exp.* = ParensExp.init(exp);
            return .{ .parens_exp = parent_exp };
        },
        else => exp, // no need to keep parens
    };
}

fn _finishPrefixExp(lexer: *Lexer, exp0: Exp) ParserError!Exp {
    var exp = exp0;
    while (true) {
        switch (lexer.lookAhead()) {
            .token_sep_lbrack => { // prefixexp ‘[’ exp ‘]’
                _ = try lexer.nextToken(); // ‘[’
                const key_exp = try parseExp(lexer); // exp
                _ = try lexer.nextTokenOfKind(.token_sep_rbrack); // ‘]’
                const last_line = lexer.line;
                const table_access_exp = try lexer.allocator.create(TableAccessExp);
                table_access_exp.* = TableAccessExp.init(last_line, exp, key_exp);
                exp = .{ .table_access_exp = table_access_exp };
            },
            .token_sep_dot => { // prefixexp ‘.’ Name
                _ = try lexer.nextToken(); // ‘.’
                const line, const name = try lexer.nextIdentifier(); // Name
                const key_exp: Exp = .{ .string_exp = StringExp.init(line, name) };
                const table_access_exp = try lexer.allocator.create(TableAccessExp);
                table_access_exp.* = TableAccessExp.init(line, exp, key_exp);
                exp = .{ .table_access_exp = table_access_exp };
            },
            .token_sep_colon, // prefixexp ‘:’ Name args
            .token_sep_lparen, // prefixexp args
            .token_sep_lcurly, // prefixexp args
            .token_string, // prefixexp args
            => {
                const func_call_exp = try _finishFuncCallExp(lexer, exp);
                exp = .{ .func_call_exp = func_call_exp };
            },
            else => return exp,
        }
    }
    return exp;
}

// functioncall ::=  prefixexp args | prefixexp ‘:’ Name args
fn _finishFuncCallExp(lexer: *Lexer, prefix_exp: Exp) ParserError!*FuncCallExp {
    const name_exp = try _parseNameExp(lexer);
    const line = lexer.line;
    const args = try _parseArgs(lexer);
    const last_line = lexer.line;
    const func_call_exp = try lexer.allocator.create(FuncCallExp);
    func_call_exp.* = FuncCallExp.init(line, last_line, prefix_exp, name_exp, args);
    return func_call_exp;
}

fn _parseNameExp(lexer: *Lexer) ParserError!?StringExp {
    if (lexer.lookAhead() == .token_sep_colon) {
        _ = try lexer.nextToken();
        const line, const name = try lexer.nextIdentifier();
        return StringExp.init(line, name);
    }
    return null;
}

// args ::=  ‘(’ [explist] ‘)’ | tableconstructor | LiteralString
fn _parseArgs(lexer: *Lexer) ParserError![]Exp {
    var args = try std.ArrayList(Exp).initCapacity(lexer.allocator, 8);
    switch (lexer.lookAhead()) {
        .token_sep_lparen => { // ‘(’ [explist] ‘)’
            _ = try lexer.nextToken(); // TOKEN_SEP_LPAREN
            if (lexer.lookAhead() != .token_sep_rparen) {
                try args.appendSlice(lexer.allocator, try parseExpList(lexer));
            }
            _ = try lexer.nextTokenOfKind(.token_sep_rparen);
        },
        .token_sep_lcurly => { // ‘{’ [fieldlist] ‘}’
            try args.append(lexer.allocator, .{ .table_constructor_exp = try parseTableConstructorExp(lexer) });
        },
        else => { // LiteralString
            const line, const str = try lexer.nextTokenOfKind(.token_string);
            try args.append(lexer.allocator, .{ .string_exp = StringExp.init(line, str) });
        },
    }
    return try args.toOwnedSlice(lexer.allocator);
}
