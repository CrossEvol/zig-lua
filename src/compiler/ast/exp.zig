//  exp ::=  nil | false | true | Numeral | LiteralString | ‘...’ | functiondef |
//      prefixexp | tablepub constructor | exp binop exp | unop exp

//  prefixexp ::= var | functioncall | ‘(’ exp ‘)’

//  var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name

//  functioncall ::=  prefixexp args | prefixexp ‘:’ Name args

const TokenKind = @import("../lexer/token.zig").TokenKind;
const Block = @import("block.zig").Block;

const string = []const u8;

pub const Exp = union(enum) {
    nil_exp: NilExp,
    true_exp: TrueExp,
    false_exp: FalseExp,
    vararg_exp: VarargExp,
    integer_exp: IntegerExp,
    float_exp: FloatExp,
    string_exp: StringExp,
    unop_exp: *UnopExp,
    binop_exp: *BinopExp,
    concat_exp: ConcatExp,
    table_constructor_exp: *TableConstructorExp,
    func_def_exp: *FuncDefExp,
    name_exp: NameExp,
    parens_exp: *ParensExp,
    table_access_exp: *TableAccessExp,
    func_call_exp: *FuncCallExp,

    pub fn isIntegerExp(exp: Exp) bool {
        return switch (exp) {
            .integer_exp => true,
            else => false,
        };
    }

    pub fn asIntegerExp(exp: Exp) IntegerExp {
        return exp.integer_exp;
    }

    pub fn isFloatExp(exp: Exp) bool {
        return switch (exp) {
            .float_exp => true,
            else => false,
        };
    }

    pub fn asFloatExp(exp: Exp) FloatExp {
        return exp.float_exp;
    }
};

pub const NilExp = struct {
    line: usize, // nil

    pub fn init(line: usize) NilExp {
        return .{ .line = line };
    }
};
pub const TrueExp = struct {
    line: usize, // true

    pub fn init(line: usize) TrueExp {
        return .{ .line = line };
    }
};
pub const FalseExp = struct {
    line: usize, // false

    pub fn init(line: usize) FalseExp {
        return .{ .line = line };
    }
};
pub const VarargExp = struct {
    line: usize, // ...

    pub fn init(line: usize) VarargExp {
        return .{ .line = line };
    }
};

// Numeral
pub const IntegerExp = struct {
    line: usize,
    val: i64,

    pub fn init(line: usize, val: i64) IntegerExp {
        return .{ .line = line, .val = val };
    }
};

pub const FloatExp = struct {
    line: usize,
    val: f64,

    pub fn init(line: usize, val: f64) FloatExp {
        return .{ .line = line, .val = val };
    }
};

// LiteralString
pub const StringExp = struct {
    line: usize,
    str: string,

    pub fn init(line: usize, str: string) StringExp {
        return .{ .line = line, .str = str };
    }
};

// unop exp
pub const UnopExp = struct {
    line: usize, // line of operator
    op: TokenKind, // operator
    exp: Exp,

    pub fn init(line: usize, op: TokenKind, exp: Exp) UnopExp {
        return .{ .line = line, .op = op, .exp = exp };
    }
};
// exp1 op exp2
pub const BinopExp = struct {
    line: usize, // line of operator
    op: TokenKind, // operator
    exp1: Exp,
    exp2: Exp,

    pub fn init(line: usize, op: TokenKind, exp1: Exp, exp2: Exp) BinopExp {
        return .{ .line = line, .op = op, .exp1 = exp1, .exp2 = exp2 };
    }
};

pub const ConcatExp = struct {
    line: usize, // line of last ..
    exps: []Exp,

    pub fn init(line: usize, exps: []Exp) ConcatExp {
        return .{ .line = line, .exps = exps };
    }
};

// tablepub constructor ::= ‘{’ [fieldlist] ‘}’
// fieldlist ::= field {fieldsep field} [fieldsep]
// field ::= ‘[’ exp ‘]’ ‘=’ exp | Name ‘=’ exp | exp
// fieldsep ::= ‘,’ | ‘;’
pub const TableConstructorExp = struct {
    line: usize, // line of `{` ?
    last_line: usize, // line of `}`
    key_exps: []?Exp,
    val_exps: []?Exp,

    pub fn init(line: usize, last_line: usize, key_exps: []?Exp, val_exps: []?Exp) TableConstructorExp {
        return .{ .line = line, .last_line = last_line, .key_exps = key_exps, .val_exps = val_exps };
    }
};

// functiondef ::= function funcbody
// funcbody ::= ‘(’ [parlist] ‘)’ block end
// parlist ::= namelist [‘,’ ‘...’] | ‘...’
// namelist ::= Name {‘,’ Name}
pub const FuncDefExp = struct {
    line: usize,
    last_line: usize,
    par_list: ?[]string,
    is_vararg: bool,
    block: Block,

    pub fn init(line: usize, last_line: usize, par_list: ?[]string, is_vararg: bool, block: Block) FuncDefExp {
        return .{ .line = line, .last_line = last_line, .par_list = par_list, .is_vararg = is_vararg, .block = block };
    }
};

// prefixexp ::= Name |
//               ‘(’ exp ‘)’ |
//               prefixexp ‘[’ exp ‘]’ |
//               prefixexp ‘.’ Name |
//               prefixexp ‘:’ Name args |
//               prefixexp args

pub const NameExp = struct {
    line: usize,
    name: string,

    pub fn init(line: usize, name: string) NameExp {
        return .{ .line = line, .name = name };
    }
};

pub const ParensExp = struct {
    exp: Exp,

    pub fn init(exp: Exp) ParensExp {
        return .{ .exp = exp };
    }
};

pub const TableAccessExp = struct {
    last_line: usize, // line of `]` ?
    prefix_exp: Exp,
    key_exp: Exp,

    pub fn init(last_line: usize, prefix_exp: Exp, key_exp: Exp) TableAccessExp {
        return .{ .last_line = last_line, .prefix_exp = prefix_exp, .key_exp = key_exp };
    }
};

pub const FuncCallExp = struct {
    line: usize, // line of `(` ?
    last_line: usize, // line of ')'
    prefix_exp: Exp,
    name_exp: ?StringExp,
    args: []Exp,

    pub fn init(line: usize, last_line: usize, prefix_exp: Exp, name_exp: ?StringExp, args: []Exp) FuncCallExp {
        return .{ .line = line, .last_line = last_line, .prefix_exp = prefix_exp, .name_exp = name_exp, .args = args };
    }
};
