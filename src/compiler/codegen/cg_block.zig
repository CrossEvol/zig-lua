const AstPkg = @import("../ast/root.zig");
const Exp = AstPkg.Exp;
const NameExp = AstPkg.NameExp;
const FuncCallExp = AstPkg.FuncCallExp;
const Block = AstPkg.Block;
const CompilerError = @import("../compiler.zig").CompilerError;
const CgExp = @import("cg_exp.zig");
const cgTailCallExp = CgExp.cgTailCallExp;
const cgExp = CgExp.cgExp;
const CgStat = @import("cg_stat.zig");
const cgStat = CgStat.cgStat;
const ExpHelper = @import("exp_helper.zig");
const isVarargOrFuncCall = ExpHelper.isVarargOrFuncCall;
const FuncInfo = @import("func_info.zig").FuncInfo;

pub fn cgBlock(fi: *FuncInfo, node: Block) CompilerError!void {
    for (node.stats) |stat| {
        try cgStat(fi, stat);
    }
    if (node.ret_exps) |ret_exps| {
        try cgRetStat(fi, ret_exps, node.last_line);
    }
}

pub fn cgRetStat(fi: *FuncInfo, exps: []Exp, last_line: i32) !void {
    const n_exps = exps.len;
    if (n_exps == 0) {
        try fi.emitReturn(last_line, 0, 0);
        return;
    }

    if (n_exps == 1) {
        switch (exps[0]) {
            .name_exp => |name_exp| {
                const r = fi.slotOfLocVar(name_exp.name);
                if (r >= 0) {
                    try fi.emitReturn(last_line, r, 1);
                    return;
                }
            },
            .func_call_exp => |fc_exp| {
                const r = try fi.allocReg();
                try cgTailCallExp(fi, fc_exp, r);
                try fi.freeReg();
                try fi.emitReturn(last_line, r, -1);
                return;
            },
            else => {},
        }
    }

    const mult_ret = isVarargOrFuncCall(exps[n_exps - 1]);
    for (0.., exps) |i, exp| {
        const r = try fi.allocReg();
        if (i == n_exps - 1 and mult_ret) {
            try cgExp(fi, exp, r, -1);
        } else {
            try cgExp(fi, exp, r, 1);
        }
    }
    try fi.freeRegs(@as(i32, @intCast(n_exps)));

    const a = fi.used_regs;
    if (mult_ret) {
        try fi.emitReturn(last_line, a, -1);
    } else {
        try fi.emitReturn(last_line, a, @as(i32, @intCast(n_exps)));
    }
}
