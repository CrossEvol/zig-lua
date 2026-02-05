// stat ::=  ‘;’ |
//      varlist ‘=’ explist |
//      functioncall |
//      label |
//      break |
//      goto Name |
//      do block end |
//      while exp do block end |
//      repeat block until exp |
//      if exp then block {elseif exp then block} [else block] end |
//      for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end |
//      for namelist in explist do block end |
//      function funcname funcbody |
//      local function Name funcbody |
//      local namelist [‘=’ explist]

const Block = @import("block.zig").Block;
const Exp = @import("exp.zig").Exp;
const FuncCallExp = @import("exp.zig").FuncCallExp;
pub const FuncCallStat = FuncCallExp;
const FuncDefExp = @import("exp.zig").FuncDefExp;

const string = []const u8;

pub const Stat = union(enum) {
    empty_stat: EmptyStat,
    break_stat: BreakStat,
    label_stat: LabelStat,
    goto_stat: GotoStat,
    do_stat: DoStat,
    func_call_stat: *FuncCallStat, // functioncall
    if_stat: IfStat,
    while_stat: *WhileStat,
    repeat_stat: *RepeatStat,
    for_num_stat: *ForNumStat,
    for_in_stat: *ForInStat,
    assign_stat: AssignStat,
    local_var_decl_stat: LocalVarDeclStat,
    local_func_def_stat: LocalFuncDefStat,
};

pub const EmptyStat = struct {
    // ‘;’

    pub fn init() EmptyStat {
        return .{};
    }
};
pub const BreakStat = struct {
    line: usize, // break

    pub fn init(line: usize) BreakStat {
        return .{ .line = line };
    }
};
pub const LabelStat = struct {
    name: string, // ‘::’ Name ‘::’

    pub fn init(name: string) LabelStat {
        return .{ .name = name };
    }
};
pub const GotoStat = struct {
    name: string, // goto Name

    pub fn init(name: string) GotoStat {
        return .{ .name = name };
    }
};
pub const DoStat = struct {
    block: Block, // do block end

    pub fn init(block: Block) DoStat {
        return .{ .block = block };
    }
};

// if exp then block {elseif exp then block} [else block] end
pub const IfStat = struct {
    exps: []Exp,
    blocks: []Block,

    pub fn init(exps: []Exp, blocks: []Block) IfStat {
        return .{ .exps = exps, .blocks = blocks };
    }
};

// while exp do block end
pub const WhileStat = struct {
    exp: Exp,
    block: Block,

    pub fn init(exp: Exp, block: Block) WhileStat {
        return .{ .exp = exp, .block = block };
    }
};

// repeat block until exp
pub const RepeatStat = struct {
    block: Block,
    exp: Exp,

    pub fn init(block: Block, exp: Exp) RepeatStat {
        return .{ .block = block, .exp = exp };
    }
};

// for Name '=' exp ',' exp [',' exp] do block end
pub const ForNumStat = struct {
    line_of_for: usize,
    line_of_do: usize,
    var_name: string,
    init_exp: Exp,
    limit_exp: Exp,
    step_exp: Exp,
    block: Block,

    pub fn init(line_of_for: usize, line_of_do: usize, var_name: string, init_exp: Exp, limit_exp: Exp, step_exp: Exp, block: Block) ForNumStat {
        return .{ .line_of_for = line_of_for, .line_of_do = line_of_do, .var_name = var_name, .init_exp = init_exp, .limit_exp = limit_exp, .step_exp = step_exp, .block = block };
    }
};

// for namelist in explist do block end
// namelist ::= Name {',' Name}
// explist ::= exp {',' exp}
pub const ForInStat = struct {
    line_of_do: usize,
    name_list: []string,
    exp_list: []Exp,
    block: Block,

    pub fn init(line_of_do: usize, name_list: []string, exp_list: []Exp, block: Block) ForInStat {
        return .{ .line_of_do = line_of_do, .name_list = name_list, .exp_list = exp_list, .block = block };
    }
};

// varlist '=' explist
// varlist ::= var {',' var}
// var ::=  Name | prefixexp '[' exp ']' | prefixexp '.' Name
pub const AssignStat = struct {
    last_line: usize,
    var_list: []Exp,
    exp_list: []Exp,

    pub fn init(last_line: usize, var_list: []Exp, exp_list: []Exp) AssignStat {
        return .{ .last_line = last_line, .var_list = var_list, .exp_list = exp_list };
    }
};

// local namelist ['=' explist]
// namelist ::= Name {',' Name}
// explist ::= exp {',' exp}
pub const LocalVarDeclStat = struct {
    last_line: usize,
    name_list: []string,
    exp_list: ?[]Exp,

    pub fn init(last_line: usize, name_list: []string, exp_list: ?[]Exp) LocalVarDeclStat {
        return .{ .last_line = last_line, .name_list = name_list, .exp_list = exp_list };
    }
};

// local function Name funcbody
pub const LocalFuncDefStat = struct {
    name: string,
    exp: *FuncDefExp,

    pub fn init(name: string, exp: *FuncDefExp) LocalFuncDefStat {
        return .{ .name = name, .exp = exp };
    }
};
