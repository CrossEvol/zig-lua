const std = @import("std");

const Block = @import("../ast/block.zig").Block;
const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const IntegerExp = ExpPkg.IntegerExp;
const TrueExp = ExpPkg.TrueExp;
const TableAccessExp = ExpPkg.TableAccessExp;
const NameExp = ExpPkg.NameExp;
const StringExp = ExpPkg.StringExp;
const StatPkg = @import("../ast/stat.zig");
const EmptyStat = StatPkg.EmptyStat;
const BreakStat = StatPkg.BreakStat;
const LabelStat = StatPkg.LabelStat;
const GotoStat = StatPkg.GotoStat;
const DoStat = StatPkg.DoStat;
const WhileStat = StatPkg.WhileStat;
const RepeatStat = StatPkg.RepeatStat;
const IfStat = StatPkg.IfStat;
const Stat = StatPkg.Stat;
const ForNumStat = StatPkg.ForNumStat;
const ForInStat = StatPkg.ForInStat;
const LocalFuncDefStat = StatPkg.LocalFuncDefStat;
const LocalVarDeclStat = StatPkg.LocalVarDeclStat;
const AssignStat = StatPkg.AssignStat;
const LexerPkg = @import("../lexer/lexer.zig");
const Lexer = LexerPkg.Lexer;
const parseBlock = @import("parse_block.zig").parseBlock;
const parseExp = @import("parse_exp.zig").parseExp;
const parseExpList = @import("parse_exp.zig").parseExpList;
const parseFuncDefExp = @import("parse_exp.zig").parseFuncDefExp;
const parsePrefixExp = @import("parse_prefix_exp.zig").parsePrefixExp;
const ParserError = @import("parser.zig").ParserError;

const string = []const u8;

const _statEmpty = EmptyStat.init();

// stat ::=  ‘;’
//
//      | break
//      | ‘::’ Name ‘::’
//      | goto Name
//      | do block end
//      | while exp do block end
//      | repeat block until exp
//      | if exp then block {elseif exp then block} [else block] end
//      | for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end
//      | for namelist in explist do block end
//      | function funcname funcbody
//      | local function Name funcbody
//      | local namelist [‘=’ explist]
//      | varlist ‘=’ explist
//      | functioncall
pub fn parseStat(lexer: *Lexer) ParserError!Stat {
    return switch (lexer.lookAhead()) {
        .token_sep_semi => .{ .empty_stat = try parseEmptyStat(lexer) },
        .token_kw_break => .{ .break_stat = try parseBreakStat(lexer) },
        .token_sep_label => .{ .label_stat = try parseLabelStat(lexer) },
        .token_kw_goto => .{ .goto_stat = try parseGotoStat(lexer) },
        .token_kw_do => .{ .do_stat = try parseDoStat(lexer) },
        .token_kw_while => .{ .while_stat = try parseWhileStat(lexer) },
        .token_kw_repeat => .{ .repeat_stat = try parseRepeatStat(lexer) },
        .token_kw_if => .{ .if_stat = try parseIfStat(lexer) },
        .token_kw_for => try parseForStat(lexer),
        .token_kw_function => .{ .assign_stat = try parseFuncDefStat(lexer) },
        .token_kw_local => try parseLocalAssignOrFuncDefStat(lexer),
        else => try parseAssignOrFuncCallStat(lexer),
    };
}

// ;
fn parseEmptyStat(lexer: *Lexer) ParserError!EmptyStat {
    _ = try lexer.nextTokenOfKind(.token_sep_semi);
    return _statEmpty;
}

// break
fn parseBreakStat(lexer: *Lexer) ParserError!BreakStat {
    _ = try lexer.nextTokenOfKind(.token_kw_break);
    return BreakStat.init(lexer.line);
}

// ‘::’ Name ‘::’
fn parseLabelStat(lexer: *Lexer) ParserError!LabelStat {
    _ = try lexer.nextTokenOfKind(.token_sep_label); // ::
    const line, const name = try lexer.nextIdentifier(); // name
    _ = line;
    _ = try lexer.nextTokenOfKind(.token_sep_label); // ::
    return LabelStat.init(name);
}

// goto Name
fn parseGotoStat(lexer: *Lexer) ParserError!GotoStat {
    _ = try lexer.nextTokenOfKind(.token_kw_goto); // goto
    const line, const name = try lexer.nextIdentifier(); // name
    _ = line;
    return GotoStat.init(name);
}

// do block end
fn parseDoStat(lexer: *Lexer) ParserError!DoStat {
    _ = try lexer.nextTokenOfKind(.token_kw_do); // do
    const block = try parseBlock(lexer); // block
    _ = try lexer.nextTokenOfKind(.token_kw_end); // end
    return DoStat.init(block);
}

// while exp do block end
fn parseWhileStat(lexer: *Lexer) ParserError!*WhileStat {
    _ = try lexer.nextTokenOfKind(.token_kw_while); // while
    const exp = try parseExp(lexer); // exp
    _ = try lexer.nextTokenOfKind(.token_kw_do); // do
    const block = try parseBlock(lexer); // block
    _ = try lexer.nextTokenOfKind(.token_kw_end); // end
    const while_stat = try lexer.allocator.create(WhileStat);
    while_stat.* = WhileStat.init(exp, block);
    return while_stat;
}

// repeat block until exp
fn parseRepeatStat(lexer: *Lexer) ParserError!*RepeatStat {
    _ = try lexer.nextTokenOfKind(.token_kw_repeat); // repeat
    const block = try parseBlock(lexer); // block
    _ = try lexer.nextTokenOfKind(.token_kw_until); // until
    const exp = try parseExp(lexer); // exp
    const repeat_stat = try lexer.allocator.create(RepeatStat);
    repeat_stat.* = RepeatStat.init(block, exp);
    return repeat_stat;
}

// if exp then block {elseif exp then block} [else block] end
fn parseIfStat(lexer: *Lexer) ParserError!IfStat {
    const allocator = lexer.allocator;
    var exps = try std.ArrayList(Exp).initCapacity(allocator, 4);
    var blocks = try std.ArrayList(Block).initCapacity(allocator, 4);

    _ = try lexer.nextTokenOfKind(.token_kw_if); // if
    try exps.append(allocator, try parseExp(lexer)); // exp
    _ = try lexer.nextTokenOfKind(.token_kw_then); // then
    try blocks.append(allocator, try parseBlock(lexer)); // block

    while (lexer.lookAhead() == .token_kw_elseif) {
        _ = try lexer.nextToken(); // elseif
        try exps.append(allocator, try parseExp(lexer)); // exp
        _ = try lexer.nextTokenOfKind(.token_kw_then); // then
        try blocks.append(allocator, try parseBlock(lexer)); // block
    }

    // else block => elseif true then block
    if (lexer.lookAhead() == .token_kw_else) {
        _ = try lexer.nextToken(); // else
        try exps.append(allocator, .{ .true_exp = TrueExp.init(lexer.line) }); //
        try blocks.append(allocator, try parseBlock(lexer)); // block
    }

    _ = try lexer.nextTokenOfKind(.token_kw_end); // end
    return IfStat.init(
        try exps.toOwnedSlice(allocator),
        try blocks.toOwnedSlice(allocator),
    );
}

// for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end
// for namelist in explist do block end
fn parseForStat(lexer: *Lexer) ParserError!Stat {
    const line_of_for, const kind = try lexer.nextTokenOfKind(.token_kw_for);
    _ = kind;
    const line, const name = try lexer.nextIdentifier();
    _ = line;
    if (lexer.lookAhead() == .token_op_assign) {
        return .{ .for_num_stat = try _finishForNumStat(lexer, line_of_for, name) };
    } else {
        return .{ .for_in_stat = try _finishForInStat(lexer, name) };
    }
}

// for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end
fn _finishForNumStat(lexer: *Lexer, line_of_for: usize, var_name: string) ParserError!*ForNumStat {
    _ = try lexer.nextTokenOfKind(.token_op_assign); // for name =
    const init_exp = try parseExp(lexer); // exp
    _ = try lexer.nextTokenOfKind(.token_sep_comma); // ,
    const limit_exp = try parseExp(lexer); // exp

    var step_exp: Exp = undefined;
    if (lexer.lookAhead() == .token_sep_comma) {
        _ = try lexer.nextToken(); // ,
        step_exp = try parseExp(lexer); // exp
    } else {
        step_exp = .{ .integer_exp = IntegerExp.init(lexer.line, 1) };
    }

    const line_of_do, const kind = try lexer.nextTokenOfKind(.token_kw_do); // do
    _ = kind;
    const block = try parseBlock(lexer); // block
    _ = try lexer.nextTokenOfKind(.token_kw_end); // end

    const for_num_stat = try lexer.allocator.create(ForNumStat);
    for_num_stat.* = ForNumStat.init(
        line_of_for,
        line_of_do,
        var_name,
        init_exp,
        limit_exp,
        step_exp,
        block,
    );
    return for_num_stat;
}

// for namelist in explist do block end
// namelist ::= Name {‘,’ Name}
// explist ::= exp {‘,’ exp}
fn _finishForInStat(lexer: *Lexer, name0: string) ParserError!*ForInStat {
    const name_list = try _finishNameList(lexer, name0); // for namelist
    _ = try lexer.nextTokenOfKind(.token_kw_in); // in
    const exp_list = try parseExpList(lexer); // explist
    const line_of_do, const token = try lexer.nextTokenOfKind(.token_kw_do); // do
    _ = token;
    const block = try parseBlock(lexer); // block
    _ = try lexer.nextTokenOfKind(.token_kw_end); // end
    const for_in_stat = try lexer.allocator.create(ForInStat);
    for_in_stat.* = ForInStat.init(line_of_do, name_list, exp_list, block);
    return for_in_stat;
}

// namelist ::= Name {‘,’ Name}
fn _finishNameList(lexer: *Lexer, name0: string) ParserError![]string {
    const allocator = lexer.allocator;
    var names = try std.ArrayList(string).initCapacity(allocator, 4);
    try names.append(allocator, name0);
    while (lexer.lookAhead() == .token_sep_comma) {
        _ = try lexer.nextToken(); // ,
        const line, const name = try lexer.nextIdentifier(); // Name
        _ = line;
        try names.append(allocator, name);
    }
    return try names.toOwnedSlice(allocator);
}

// local function Name funcbody
// local namelist [‘=’ explist]
fn parseLocalAssignOrFuncDefStat(lexer: *Lexer) ParserError!Stat {
    _ = try lexer.nextTokenOfKind(.token_kw_local);
    if (lexer.lookAhead() == .token_kw_function) {
        return .{ .local_func_def_stat = try _finishLocalFuncDefStat(lexer) };
    } else {
        return .{ .local_var_decl_stat = try _finishLocalVarDeclStat(lexer) };
    }
}

// http://www.lua.org/manual/5.3/manual.html#3.4.11
//
// function f() end          =>  f = function() end
// function t.a.b.c.f() end  =>  t.a.b.c.f = function() end
// function t.a.b.c:f() end  =>  t.a.b.c.f = function(self) end
// local function f() end    =>  local f; f = function() end
//
// The statement `local function f () body end`
// translates to `local f; f = function () body end`
// not to `local f = function () body end`
// (This only makes a difference when the body of the function
//  contains references to f.)

// local function Name funcbody
fn _finishLocalFuncDefStat(lexer: *Lexer) ParserError!LocalFuncDefStat {
    _ = try lexer.nextTokenOfKind(.token_kw_function); // local function
    const line, const name = try lexer.nextIdentifier(); // name
    _ = line;
    const fd_exp = try parseFuncDefExp(lexer); // funcbody
    return LocalFuncDefStat.init(name, fd_exp);
}

// local namelist [‘=’ explist]
fn _finishLocalVarDeclStat(lexer: *Lexer) ParserError!LocalVarDeclStat {
    const line, const name0 = try lexer.nextIdentifier(); // local Name
    _ = line;
    const name_list = try _finishNameList(lexer, name0); // { , Name }
    var exp_list: ?[]Exp = null;
    if (lexer.lookAhead() == .token_op_assign) {
        _ = try lexer.nextToken(); // ==
        exp_list = try parseExpList(lexer); // explist
    }
    const last_line = lexer.line;
    return LocalVarDeclStat.init(last_line, name_list, exp_list);
}

// varlist ‘=’ explist
// functioncall
fn parseAssignOrFuncCallStat(lexer: *Lexer) ParserError!Stat {
    const prefix_exp = try parsePrefixExp(lexer);
    return switch (prefix_exp) {
        .func_call_exp => |f| .{ .func_call_stat = f },
        else => .{ .assign_stat = try parseAssignStat(lexer, prefix_exp) },
    };
}

// varlist ‘=’ explist |
fn parseAssignStat(lexer: *Lexer, var0: Exp) ParserError!AssignStat {
    const var_list = try _finishVarList(lexer, var0); // varlist
    _ = try lexer.nextTokenOfKind(.token_op_assign); // =
    const exp_list = try parseExpList(lexer); // explist
    const last_line = lexer.line;
    return AssignStat.init(last_line, var_list, exp_list);
}

// varlist ::= var {‘,’ var}
fn _finishVarList(lexer: *Lexer, var0: Exp) ParserError![]Exp {
    const allocator = lexer.allocator;
    var vars = try std.ArrayList(Exp).initCapacity(allocator, 4); // var
    try vars.append(allocator, try _checkVar(lexer, var0)); // {
    while (lexer.lookAhead() == .token_sep_comma) { // ,
        _ = try lexer.nextToken(); // var
        const exp = try parsePrefixExp(lexer); //
        try vars.append(allocator, try _checkVar(lexer, exp)); // }
    }
    return try vars.toOwnedSlice(allocator);
}

// var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name
fn _checkVar(lexer: *Lexer, exp: Exp) ParserError!Exp {
    switch (exp) {
        .name_exp, .table_access_exp => {
            return exp;
        },
        else => {},
    }
    _ = try lexer.nextTokenOfKind(.token_unknown_error); // trigger error
    @panic("unreachable!");
}

// function funcname funcbody
// funcname ::= Name {‘.’ Name} [‘:’ Name]
// funcbody ::= ‘(’ [parlist] ‘)’ block end
// parlist ::= namelist [‘,’ ‘...’] | ‘...’
// namelist ::= Name {‘,’ Name}
fn parseFuncDefStat(lexer: *Lexer) ParserError!AssignStat {
    const allocator = lexer.allocator;
    _ = try lexer.nextTokenOfKind(.token_kw_function); // function
    const fn_exp, const has_colon = try _parseFuncName(lexer); // funcname
    const fd_exp = try parseFuncDefExp(lexer); // funcbody
    if (has_colon) { // insert self
        if (fd_exp.par_list) |list| {
            const len = list.len;
            fd_exp.par_list = try allocator.realloc(list, len + 1);
            std.mem.copyBackwards(string, list[1..], list[0..len]);
            fd_exp.par_list.?[0] = "self";
        } else {
            fd_exp.par_list = try allocator.alloc(string, 1);
            fd_exp.par_list.?[0] = "self";
        }
    }

    const var_list = try allocator.alloc(Exp, 1);
    var_list[0] = fn_exp;
    const exp_list = try allocator.alloc(Exp, 1);
    exp_list[0] = .{ .func_def_exp = fd_exp };
    return AssignStat.init(fd_exp.line, var_list, exp_list);
}

// funcname ::= Name {‘.’ Name} [‘:’ Name]
fn _parseFuncName(lexer: *Lexer) ParserError!struct { Exp, bool } {
    const allocator = lexer.allocator;
    var line, var name = try lexer.nextIdentifier();
    var exp: Exp = .{ .name_exp = NameExp.init(line, name) };
    var has_colon = false;

    while (lexer.lookAhead() == .token_sep_dot) {
        _ = try lexer.nextToken();
        line, name = try lexer.nextIdentifier();
        const idx: Exp = .{ .string_exp = StringExp.init(line, name) };
        const table_access_exp = try allocator.create(TableAccessExp);
        table_access_exp.* = TableAccessExp.init(line, exp, idx);
        exp = .{ .table_access_exp = table_access_exp };
    }
    if (lexer.lookAhead() == .token_sep_colon) {
        _ = try lexer.nextToken();
        line, name = try lexer.nextIdentifier();
        const idx: Exp = .{ .string_exp = StringExp.init(line, name) };
        const table_access_exp = try allocator.create(TableAccessExp);
        table_access_exp.* = TableAccessExp.init(line, exp, idx);
        exp = .{ .table_access_exp = table_access_exp };
        has_colon = true;
    }
    return .{ exp, has_colon };
}
