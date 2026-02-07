const std = @import("std");

const number = @import("../../number/root.zig").number;
const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const FuncDefExp = ExpPkg.FuncDefExp;
const TableConstructorExp = ExpPkg.TableConstructorExp;
const IntegerExp = ExpPkg.IntegerExp;
const ConcatExp = ExpPkg.ConcatExp;
const BinopExp = ExpPkg.BinopExp;
const FloatExp = ExpPkg.FloatExp;
const StringExp = ExpPkg.StringExp;
const VarargExp = ExpPkg.VarargExp;
const UnopExp = ExpPkg.UnopExp;
const NilExp = ExpPkg.NilExp;
const TrueExp = ExpPkg.TrueExp;
const FalseExp = ExpPkg.FalseExp;
const LexerPkg = @import("../lexer/lexer.zig");
const Lexer = LexerPkg.Lexer;
const TokenPkg = @import("../lexer/token.zig");
const TOKEN_OP_UNM = TokenPkg.TOKEN_OP_UNM;
const TOKEN_OP_SUB = TokenPkg.TOKEN_OP_SUB;
const TOKEN_OP_BXOR = TokenPkg.TOKEN_OP_BXOR;
const TOKEN_OP_BNOT = TokenPkg.TOKEN_OP_BNOT;
const TokenKind = TokenPkg.TokenKind;
const OptimizePkg = @import("optimizer.zig");
const optimizePow = OptimizePkg.optimizePow;
const optimizeUnaryOp = OptimizePkg.optimizeUnaryOp;
const optimizeLogicalOr = OptimizePkg.optimizeLogicalOr;
const optimizeLogicalAnd = OptimizePkg.optimizeLogicalAnd;
const optimizeBitwiseBinaryOp = OptimizePkg.optimizeBitwiseBinaryOp;
const optimizeArithBinaryOp = OptimizePkg.optimizeArithBinaryOp;
const parseBlock = @import("parse_block.zig").parseBlock;
const parsePrefixExp = @import("parse_prefix_exp.zig").parsePrefixExp;
const ParserError = @import("parser.zig").ParserError;

const string = []const u8;

// explist ::= exp {‘,’ exp}
pub fn parseExpList(lexer: *Lexer) ParserError![]Exp {
    var exps = try std.ArrayList(Exp).initCapacity(lexer.allocator, 4);
    try exps.append(lexer.allocator, try parseExp(lexer));
    while (lexer.lookAhead() == .token_sep_comma) {
        _ = try lexer.nextToken();
        try exps.append(lexer.allocator, try parseExp(lexer));
    }
    return exps.toOwnedSlice(lexer.allocator);
}

// exp ::=  nil | false | true | Numeral | LiteralString | ‘...’ | functiondef |
//      prefixexp | tableconstructor | exp binop exp | unop exp

// exp   ::= exp12
// exp12 ::= exp11 {or exp11}
// exp11 ::= exp10 {and exp10}
// exp10 ::= exp9 {(‘<’ | ‘>’ | ‘<=’ | ‘>=’ | ‘~=’ | ‘==’) exp9}
// exp9  ::= exp8 {‘|’ exp8}
// exp8  ::= exp7 {‘~’ exp7}
// exp7  ::= exp6 {‘&’ exp6}
// exp6  ::= exp5 {(‘<<’ | ‘>>’) exp5}
// exp5  ::= exp4 {‘..’ exp4}
// exp4  ::= exp3 {(‘+’ | ‘-’) exp3}
// exp3  ::= exp2 {(‘*’ | ‘/’ | ‘//’ | ‘%’) exp2}
// exp2  ::= {(‘not’ | ‘#’ | ‘-’ | ‘~’)} exp1
// exp1  ::= exp0 {‘^’ exp2}
// exp0  ::= nil | false | true | Numeral | LiteralString
//      | ‘...’ | functiondef | prefixexp | tableconstructor

pub fn parseExp(lexer: *Lexer) ParserError!Exp {
    return try parseExp12(lexer);
}

// x or y
fn parseExp12(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp11(lexer);
    while (lexer.lookAhead() == .token_op_or) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const lor = try lexer.allocator.create(BinopExp);
        lor.* = BinopExp.init(line, op, exp, try parseExp11(lexer));
        exp = optimizeLogicalOr(lor);
    }
    return exp;
}

// x and y
fn parseExp11(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp10(lexer);
    while (lexer.lookAhead() == .token_op_and) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const land = try lexer.allocator.create(BinopExp);
        land.* = BinopExp.init(line, op, exp, try parseExp10(lexer));
        exp = optimizeLogicalAnd(land);
    }
    return exp;
}

// compare
fn parseExp10(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp9(lexer);
    while (true) {
        switch (lexer.lookAhead()) {
            .token_op_lt, .token_op_gt, .token_op_ne, .token_op_le, .token_op_ge, .token_op_eq => {
                const line, const op, const token = try lexer.nextToken();
                _ = token;
                const binop_exp = try lexer.allocator.create(BinopExp);
                binop_exp.* = BinopExp.init(line, op, exp, try parseExp9(lexer));
                exp = .{
                    .binop_exp = binop_exp,
                };
            },
            else => return exp,
        }
    }
    return exp;
}

// x | y
fn parseExp9(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp8(lexer);
    while (lexer.lookAhead() == .token_op_bor) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const bor = try lexer.allocator.create(BinopExp);
        bor.* = BinopExp.init(line, op, exp, try parseExp8(lexer));
        exp = optimizeBitwiseBinaryOp(bor);
    }
    return exp;
}

// x ~ y
fn parseExp8(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp7(lexer);
    while (lexer.lookAhead() == TOKEN_OP_BXOR) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const bxor = try lexer.allocator.create(BinopExp);
        bxor.* = BinopExp.init(line, op, exp, try parseExp7(lexer));
        exp = optimizeBitwiseBinaryOp(bxor);
    }
    return exp;
}

// x & y
fn parseExp7(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp6(lexer);
    while (lexer.lookAhead() == .token_op_band) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const band = lexer.allocator.create(BinopExp) catch @panic("allocation failed");
        band.* = BinopExp.init(line, op, exp, try parseExp6(lexer));
        exp = optimizeBitwiseBinaryOp(band);
    }
    return exp;
}

// shift
fn parseExp6(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp5(lexer);
    while (true) {
        switch (lexer.lookAhead()) {
            .token_op_shl, .token_op_shr => {
                const line, const op, const token = try lexer.nextToken();
                _ = token;
                const shx = lexer.allocator.create(BinopExp) catch @panic("allocation failed");
                shx.* = BinopExp.init(line, op, exp, try parseExp5(lexer));
                exp = optimizeBitwiseBinaryOp(shx);
            },
            else => return exp,
        }
    }
    return exp;
}

// a .. b
fn parseExp5(lexer: *Lexer) ParserError!Exp {
    const exp = try parseExp4(lexer);
    if (lexer.lookAhead() != .token_op_concat) {
        return exp;
    }

    var line: i32 = 0;
    var exps = try std.ArrayList(Exp).initCapacity(lexer.allocator, 8);
    try exps.append(lexer.allocator, exp);
    while (lexer.lookAhead() == .token_op_concat) {
        line, const op, const token = try lexer.nextToken();
        _ = op;
        _ = token;
        try exps.append(lexer.allocator, try parseExp4(lexer));
    }
    return .{
        .concat_exp = ConcatExp.init(
            line,
            try exps.toOwnedSlice(lexer.allocator),
        ),
    };
}

// x +/- y
fn parseExp4(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp3(lexer);
    while (true) {
        switch (lexer.lookAhead()) {
            .token_op_add, TOKEN_OP_SUB => {
                const line, const op, const token = try lexer.nextToken();
                _ = token;
                const arith = try lexer.allocator.create(BinopExp);
                arith.* = BinopExp.init(line, op, exp, try parseExp3(lexer));
                exp = optimizeArithBinaryOp(arith);
            },
            else => return exp,
        }
    }
    return exp;
}

// *, %, /, //
fn parseExp3(lexer: *Lexer) ParserError!Exp {
    var exp = try parseExp2(lexer);
    while (true) {
        switch (lexer.lookAhead()) {
            .token_op_mul, .token_op_mod, .token_op_div, .token_op_idiv => {
                const line, const op, const token = try lexer.nextToken();
                _ = token;
                const arith = try lexer.allocator.create(BinopExp);
                arith.* = BinopExp.init(line, op, exp, try parseExp2(lexer));
                exp = optimizeArithBinaryOp(arith);
            },
            else => return exp,
        }
    }
    return exp;
}

// unary
fn parseExp2(lexer: *Lexer) ParserError!Exp {
    switch (lexer.lookAhead()) {
        TOKEN_OP_UNM, TOKEN_OP_BNOT, .token_op_len, .token_op_not => {
            const line, const op, const token = try lexer.nextToken();
            _ = token;
            const unop_exp = try lexer.allocator.create(UnopExp);
            unop_exp.* = UnopExp.init(line, op, try parseExp2(lexer));
            return optimizeUnaryOp(unop_exp);
        },
        else => {},
    }
    return parseExp1(lexer);
}

// x ^ y
fn parseExp1(lexer: *Lexer) ParserError!Exp { // pow is right associative
    var exp = try parseExp0(lexer);
    if (lexer.lookAhead() == .token_op_pow) {
        const line, const op, const token = try lexer.nextToken();
        _ = token;
        const binop_exp = try lexer.allocator.create(BinopExp);
        binop_exp.* = BinopExp.init(line, op, exp, try parseExp3(lexer));
        exp = .{ .binop_exp = binop_exp };
    }
    return optimizePow(exp);
}

fn parseExp0(lexer: *Lexer) ParserError!Exp {
    return switch (lexer.lookAhead()) {
        .token_vararg => { // ...
            const line, const kind, const token = try lexer.nextToken();
            _ = kind;
            _ = token;
            return .{ .vararg_exp = VarargExp.init(line) };
        },
        .token_kw_nil => { // nil
            const line, const kind, const token = try lexer.nextToken();
            _ = kind;
            _ = token;
            return .{ .nil_exp = NilExp.init(line) };
        },
        .token_kw_true => { // true
            const line, const kind, const token = try lexer.nextToken();
            _ = kind;
            _ = token;
            return .{ .true_exp = TrueExp.init(line) };
        },
        .token_kw_false => { // false
            const line, const kind, const token = try lexer.nextToken();
            _ = kind;
            _ = token;
            return .{ .false_exp = FalseExp.init(line) };
        },
        .token_string => { // LiteralString
            const line, const kind, const token = try lexer.nextToken();
            _ = kind;
            return .{ .string_exp = StringExp.init(line, token) };
        },
        .token_number => { // Numeral
            return try parseNumberExp(lexer);
        },
        .token_sep_lcurly => { // tableconstructor
            return .{ .table_constructor_exp = try parseTableConstructorExp(lexer) };
        },
        .token_kw_function => { // functiondef
            _ = try lexer.nextToken();
            return .{ .func_def_exp = try parseFuncDefExp(lexer) };
        },
        else => { // prefixexp
            return parsePrefixExp(lexer);
        },
    };
}

fn parseNumberExp(lexer: *Lexer) !Exp {
    const line, const kind, const token = try lexer.nextToken();
    _ = kind;
    const i, var ok = number.parseInteger(token);
    if (ok) {
        return .{ .integer_exp = IntegerExp.init(line, i) };
    }
    const f, ok = number.parseFloat(token);
    if (ok) {
        return .{ .float_exp = FloatExp.init(line, f) };
    }
    const msg = try std.fmt.allocPrint(lexer.allocator, "not a number: {s}", .{token});
    @panic(msg);
}

// functiondef ::= function funcbody
// funcbody ::= ‘(’ [parlist] ‘)’ block end
pub fn parseFuncDefExp(lexer: *Lexer) ParserError!*FuncDefExp {
    const line = lexer.line; // function
    _ = try lexer.nextTokenOfKind(.token_sep_lparen); // (
    const par_list, const is_vararg = try _parseParList(lexer); // [parlist]
    _ = try lexer.nextTokenOfKind(.token_sep_rparen); // )
    const block = try parseBlock(lexer); // block
    const last_line, const kind = try lexer.nextTokenOfKind(.token_kw_end); // end
    _ = kind;
    const func_def_exp = try lexer.allocator.create(FuncDefExp);
    func_def_exp.* = FuncDefExp.init(line, last_line, par_list, is_vararg, block);
    return func_def_exp;
}

// [parlist]
// parlist ::= namelist [‘,’ ‘...’] | ‘...’
/// -> (names: ?[]string, is_vararg: bool)
fn _parseParList(lexer: *Lexer) ParserError!struct { ?[]string, bool } {
    switch (lexer.lookAhead()) {
        .token_sep_rparen => {
            return .{ null, false };
        },
        .token_vararg => {
            _ = try lexer.nextToken();
            return .{ null, true };
        },
        else => {},
    }

    var is_vararg = false;
    var names = try std.ArrayList(string).initCapacity(lexer.allocator, 8);
    const line, const name = try lexer.nextIdentifier();
    _ = line;
    try names.append(lexer.allocator, name);
    while (lexer.lookAhead() == .token_sep_comma) {
        _ = try lexer.nextToken();
        if (lexer.lookAhead() == .token_identifier) {
            const line1, const name1 = try lexer.nextIdentifier();
            _ = line1;
            try names.append(lexer.allocator, name1);
        } else {
            _ = try lexer.nextTokenOfKind(.token_vararg);
            is_vararg = true;
            break;
        }
    }
    return .{
        try names.toOwnedSlice(lexer.allocator),
        is_vararg,
    };
}

// tableconstructor ::= ‘{’ [fieldlist] ‘}’
pub fn parseTableConstructorExp(lexer: *Lexer) ParserError!*TableConstructorExp {
    const line = lexer.line;
    _ = try lexer.nextTokenOfKind(.token_sep_lcurly); // {
    const key_exps, const val_exps = try _parseFieldList(lexer); // [fieldlist]
    _ = try lexer.nextTokenOfKind(.token_sep_rcurly); // }
    const last_line = lexer.line;
    const table_constructor_exp = try lexer.allocator.create(TableConstructorExp);
    table_constructor_exp.* = TableConstructorExp.init(line, last_line, key_exps, val_exps);
    return table_constructor_exp;
}

// fieldlist ::= field {fieldsep field} [fieldsep]
/// -> (ks: []?Exp, vs: []?Exp)
fn _parseFieldList(lexer: *Lexer) ParserError!struct { []?Exp, []?Exp } {
    var ks = try std.ArrayList(?Exp).initCapacity(lexer.allocator, 8);
    var vs = try std.ArrayList(?Exp).initCapacity(lexer.allocator, 8);
    while (lexer.lookAhead() != .token_sep_rcurly) {
        const k, const v = try _parseField(lexer);
        try ks.append(lexer.allocator, k);
        try vs.append(lexer.allocator, v);

        while (_isFieldSep(lexer.lookAhead())) {
            _ = try lexer.nextToken();
            if (lexer.lookAhead() != .token_sep_rcurly) {
                const k1, const v1 = try _parseField(lexer);
                try ks.append(lexer.allocator, k1);
                try vs.append(lexer.allocator, v1);
            } else {
                break;
            }
        }
    }
    return .{
        try ks.toOwnedSlice(lexer.allocator),
        try vs.toOwnedSlice(lexer.allocator),
    };
}

// fieldsep ::= ‘,’ | ‘;’
fn _isFieldSep(tokenKind: TokenKind) bool {
    return tokenKind == .token_sep_comma or tokenKind == .token_sep_semi;
}

// field ::= ‘[’ exp ‘]’ ‘=’ exp | Name ‘=’ exp | exp
/// -> (k: ?Exp, v: ?Exp)
fn _parseField(lexer: *Lexer) ParserError!struct { ?Exp, ?Exp } {
    if (lexer.lookAhead() == .token_sep_lbrack) {
        _ = try lexer.nextToken(); // [
        const k = try parseExp(lexer); // exp
        _ = try lexer.nextTokenOfKind(.token_sep_rbrack); // ]
        _ = try lexer.nextTokenOfKind(.token_op_assign); // =
        const v = try parseExp(lexer); // exp
        return .{ k, v };
    }

    const exp = try parseExp(lexer);
    switch (exp) {
        .name_exp => |name_exp| {
            if (lexer.lookAhead() == .token_op_assign) {
                // Name ‘=’ exp => ‘[’ LiteralString ‘]’ = exp
                _ = try lexer.nextToken();
                const k: Exp = .{ .string_exp = StringExp.init(name_exp.line, name_exp.name) };
                const v = try parseExp(lexer);
                return .{ k, v };
            }
        },
        else => {},
    }

    return .{ null, exp };
}
