const std = @import("std");

const LuaValue = @import("../../state/root.zig").state.LuaValue;
const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const StatPkg = @import("../ast/stat.zig");
const Stat = StatPkg.Stat;
const LocalFuncDefStat = StatPkg.LocalFuncDefStat;
const FuncCallStat = StatPkg.FuncCallStat;
const BreakStat = StatPkg.BreakStat;
const DoStat = StatPkg.DoStat;
const WhileStat = StatPkg.WhileStat;
const RepeatStat = StatPkg.RepeatStat;
const IfStat = StatPkg.IfStat;
const ForNumStat = StatPkg.ForNumStat;
const ForInStat = StatPkg.ForInStat;
const LocalVarDeclStat = StatPkg.LocalVarDeclStat;
const AssignStat = StatPkg.AssignStat;
const CompilerError = @import("../compiler.zig").CompilerError;
const cgBlock = @import("cg_block.zig").cgBlock;
const CgExp = @import("cg_exp.zig");
const cgExp = CgExp.cgExp;
const cgFuncDefExp = CgExp.cgFuncDefExp;
const cgFuncCallExp = CgExp.cgFuncCallExp;
const expToOpArg = CgExp.expToOpArg;
const ExpHelper = @import("exp_helper.zig");
const isVarargOrFuncCall = ExpHelper.isVarargOrFuncCall;
const lineOf = ExpHelper.lineOf;
const lastLineOf = ExpHelper.lastLineOf;
const removeTailNils = ExpHelper.removeTailNils;
const FuncInfo = @import("func_info.zig").FuncInfo;

const string = []const u8;
pub fn cgStat(fi: *FuncInfo, node: Stat) !void {
    switch (node) {
        .func_call_stat => |stat| try cgFuncCallStat(fi, stat),
        .break_stat => |stat| try cgBreakStat(fi, stat),
        .do_stat => |stat| try cgDoStat(fi, stat),
        .while_stat => |stat| try cgWhileStat(fi, stat),
        .repeat_stat => |stat| try cgRepeatStat(fi, stat),
        .if_stat => |stat| try cgIfStat(fi, stat),
        .for_num_stat => |stat| try cgForNumStat(fi, stat),
        .for_in_stat => |stat| try cgForInStat(fi, stat),
        .assign_stat => |stat| try cgAssignStat(fi, stat),
        .local_var_decl_stat => |stat| try cgLocalVarDeclStat(fi, stat),
        .local_func_def_stat => |stat| try cgLocalFuncDefStat(fi, stat),
        .label_stat, .goto_stat => {
            std.debug.print("label and goto statements are not supported!", .{});
            return CompilerError.ICompilerError;
        },
        else => {},
    }
}

pub fn cgLocalFuncDefStat(fi: *FuncInfo, node: LocalFuncDefStat) !void {
    const r = try fi.addLocVar(node.name, fi.PC() + 2);
    try cgFuncDefExp(fi, node.exp, r);
}

pub fn cgFuncCallStat(fi: *FuncInfo, node: *FuncCallStat) !void {
    const r = try fi.allocReg();
    try cgFuncCallExp(fi, node, r, 0);
    try fi.freeReg();
}

pub fn cgBreakStat(fi: *FuncInfo, node: BreakStat) !void {
    const pc = try fi.emitJmp(node.line, 0, 0);
    try fi.addBreakJmp(pc);
}

pub fn cgDoStat(fi: *FuncInfo, node: DoStat) !void {
    try fi.enterScope(false);
    try cgBlock(fi, node.block);
    try fi.closeOpenUpvals(node.block.last_line);
    try fi.exitScope(fi.PC() + 1);
}

///
///       ______________
///      /  false? jmp  |
///     /               |
///
/// while exp do block end <-'
///
///     ^           \
///     |___________/
///          jmp
///
pub fn cgWhileStat(fi: *FuncInfo, node: *WhileStat) !void {
    const pc_before_exp = fi.PC();

    const old_regs = fi.used_regs;
    const a, const kindA = try expToOpArg(fi, node.exp, .arg_reg);
    _ = kindA;
    fi.used_regs = old_regs;

    const line = lastLineOf(node.exp);
    try fi.emitTest(line, a, 0);
    const pc_jmp_to_end = try fi.emitJmp(line, 0, 0);

    try fi.enterScope(true);
    try cgBlock(fi, node.block);
    try fi.closeOpenUpvals(node.block.last_line);
    _ = try fi.emitJmp(node.block.last_line, 0, pc_before_exp - fi.PC() - 1);
    try fi.exitScope(fi.PC());

    fi.fixSbx(pc_jmp_to_end, fi.PC() - pc_jmp_to_end);
}

///
///      ______________
///     |  false? jmp  |
///     V              /
///
/// repeat block until exp
///
pub fn cgRepeatStat(fi: *FuncInfo, node: *RepeatStat) !void {
    try fi.enterScope(true);

    const pc_before_block = fi.PC();
    try cgBlock(fi, node.block);

    const old_regs = fi.used_regs;
    const a, const kindA = try expToOpArg(fi, node.exp, .arg_reg);
    _ = kindA;
    fi.used_regs = old_regs;

    const line = lastLineOf(node.exp);
    try fi.emitTest(line, a, 0);
    _ = try fi.emitJmp(line, try fi.getJmpArgA(), pc_before_block - fi.PC() - 1);
    try fi.closeOpenUpvals(line);

    try fi.exitScope(fi.PC() + 1);
}

///
///       _________________       _________________       _____________
///      / false? jmp      |     / false? jmp      |     / false? jmp  |
///     /                  V    /                  V    /              V
///
/// if exp1 then block1 elseif exp2 then block2 elseif true then block3 end <-.
///
///     \                       \                       \      |
///      \_______________________\_______________________\_____|
///      jmp                     jmp                     jmp
///
pub fn cgIfStat(fi: *FuncInfo, node: IfStat) !void {
    const pc_jmp_to_ends = try fi.allocator.alloc(i32, node.exps.len);
    var pc_jmp_to_next_exp: i32 = -1;

    for (0.., node.exps) |i, exp| {
        if (pc_jmp_to_next_exp >= 0) {
            fi.fixSbx(pc_jmp_to_next_exp, fi.PC() - pc_jmp_to_next_exp);
        }

        const old_regs = fi.used_regs;
        const a, const kindA = try expToOpArg(fi, exp, .arg_reg);
        _ = kindA;
        fi.used_regs = old_regs;

        const line = lastLineOf(exp);
        try fi.emitTest(line, a, 0);
        pc_jmp_to_next_exp = try fi.emitJmp(line, 0, 0);

        const block = node.blocks[i];
        try fi.enterScope(false);
        try cgBlock(fi, block);
        try fi.closeOpenUpvals(block.last_line);
        try fi.exitScope(fi.PC() + 1);

        if (i < node.exps.len - 1) {
            pc_jmp_to_ends[i] = try fi.emitJmp(block.last_line, 0, 0);
        } else {
            pc_jmp_to_ends[i] = pc_jmp_to_next_exp;
        }
    }

    for (pc_jmp_to_ends) |pc| {
        fi.fixSbx(pc, fi.PC() - pc);
    }
}

pub fn cgForNumStat(fi: *FuncInfo, node: *ForNumStat) !void {
    const for_index_var = "(for index)";
    const for_limit_var = "(for limit)";
    const for_step_var = "(for step)";

    try fi.enterScope(true);

    const name_list = try fi.allocator.alloc(string, 3);
    name_list[0] = for_index_var;
    name_list[1] = for_limit_var;
    name_list[2] = for_step_var;
    const exp_list = try fi.allocator.alloc(Exp, 3);
    exp_list[0] = node.init_exp;
    exp_list[1] = node.limit_exp;
    exp_list[2] = node.step_exp;
    try cgLocalVarDeclStat(fi, LocalVarDeclStat.init(0, name_list, exp_list));
    _ = try fi.addLocVar(node.var_name, fi.PC() + 2);

    const a = fi.used_regs - 4;
    const pc_for_prep = try fi.emitForPrep(node.line_of_do, a, 0);
    try cgBlock(fi, node.block);
    try fi.closeOpenUpvals(node.block.last_line);
    const pc_for_loop = try fi.emitForLoop(node.line_of_for, a, 0);

    fi.fixSbx(pc_for_prep, pc_for_loop - pc_for_prep - 1);
    fi.fixSbx(pc_for_loop, pc_for_prep - pc_for_loop);

    try fi.exitScope(fi.PC());
    fi.fixEndPC(for_index_var, 1);
    fi.fixEndPC(for_limit_var, 1);
    fi.fixEndPC(for_step_var, 1);
}

pub fn cgForInStat(fi: *FuncInfo, node: *ForInStat) !void {
    const for_generator_var = "(for generator)";
    const for_state_var = "(for state)";
    const for_control_var = "(for control)";

    try fi.enterScope(true);

    const name_list = try fi.allocator.alloc(string, 3);
    name_list[0] = for_generator_var;
    name_list[1] = for_state_var;
    name_list[2] = for_control_var;
    try cgLocalVarDeclStat(fi, LocalVarDeclStat.init(0, name_list, node.exp_list));
    for (node.name_list) |name| {
        _ = try fi.addLocVar(name, fi.PC() + 2);
    }

    const pc_jmp_to_tfc = try fi.emitJmp(node.line_of_do, 0, 0);
    try cgBlock(fi, node.block);
    try fi.closeOpenUpvals(node.block.last_line);
    fi.fixSbx(pc_jmp_to_tfc, fi.PC() - pc_jmp_to_tfc);

    const line = lineOf(node.exp_list[0]);
    const r_generator = fi.slotOfLocVar(for_generator_var);
    try fi.emitTForCall(line, r_generator, @intCast(node.name_list.len));
    _ = try fi.emitTForLoop(line, r_generator + 2, pc_jmp_to_tfc - fi.PC() - 1);

    try fi.exitScope(fi.PC() - 1);
    fi.fixEndPC(for_generator_var, 2);
    fi.fixEndPC(for_state_var, 2);
    fi.fixEndPC(for_control_var, 2);
}

pub fn cgLocalVarDeclStat(fi: *FuncInfo, node: LocalVarDeclStat) !void {
    const exps = removeTailNils(node.exp_list);
    const n_exps = exps.len;
    const n_names = node.name_list.len;

    const old_regs = fi.used_regs;
    if (n_exps == n_names) {
        for (exps) |exp| {
            const a = try fi.allocReg();
            try cgExp(fi, exp, a, 1);
        }
    } else if (n_exps > n_names) {
        for (0.., exps) |i, exp| {
            const a = try fi.allocReg();
            if (i == n_exps - 1 and isVarargOrFuncCall(exp)) {
                try cgExp(fi, exp, a, 0);
            } else {
                try cgExp(fi, exp, a, 1);
            }
        }
    } else { // nNames > nExps
        var mult_ret = false;
        for (0.., exps) |i, exp| {
            const a = try fi.allocReg();
            if (i == n_exps - 1 and isVarargOrFuncCall(exp)) {
                mult_ret = true;
                const n = @as(i32, @intCast(n_names - n_exps + 1));
                try cgExp(fi, exp, a, n);
                _ = try fi.allocRegs(n - 1);
            } else {
                try cgExp(fi, exp, a, 1);
            }
        }
        if (!mult_ret) {
            const n = @as(i32, @intCast(n_names - n_exps));
            const a = try fi.allocRegs(n);
            try fi.emitLoadNil(node.last_line, a, n);
        }
    }

    fi.used_regs = old_regs;
    const start_pc = fi.PC() + 1;
    for (node.name_list) |name| {
        _ = try fi.addLocVar(name, start_pc);
    }
}

pub fn cgAssignStat(fi: *FuncInfo, node: AssignStat) !void {
    const exps = removeTailNils(node.exp_list);
    const n_exps = exps.len;
    const n_vars = node.var_list.len;

    const t_regs = try fi.allocator.alloc(i32, n_vars);
    const k_regs = try fi.allocator.alloc(i32, n_vars);
    const v_regs = try fi.allocator.alloc(i32, n_vars);
    const old_regs = fi.used_regs;

    for (0.., node.var_list) |i, exp| {
        switch (exp) {
            .table_access_exp => |ta_exp| {
                t_regs[i] = try fi.allocReg();
                try cgExp(fi, ta_exp.prefix_exp, t_regs[i], 1);
                k_regs[i] = try fi.allocReg();
                try cgExp(fi, ta_exp.key_exp, k_regs[i], 1);
            },
            .name_exp => |name_exp| {
                const name = name_exp.name;
                if (fi.slotOfLocVar(name) < 0 and (try fi.indexOfUpval(name)) < 0) {
                    // global var
                    k_regs[i] = -1;
                    const k = LuaValue.newString(fi.allocator, name);
                    if ((try fi.indexOfConstant(k)) > 0xFF) {
                        k_regs[i] = try fi.allocReg();
                    }
                }
            },
            else => {},
        }
    }
    for (0..n_vars) |i| {
        v_regs[i] = fi.used_regs + @as(i32, @intCast(i));
    }

    if (n_exps >= n_vars) {
        for (0.., exps) |i, exp| {
            const a = try fi.allocReg();
            if (i >= n_vars and i == n_exps - 1 and isVarargOrFuncCall(exp)) {
                try cgExp(fi, exp, a, 0);
            } else {
                try cgExp(fi, exp, a, 1);
            }
        }
    } else { // nVars > nExps
        var mult_ret = false;
        for (0.., exps) |i, exp| {
            const a = try fi.allocReg();
            if (i == n_exps - 1 and isVarargOrFuncCall(exp)) {
                mult_ret = true;
                const n = @as(i32, @intCast(n_vars - n_exps + 1));
                try cgExp(fi, exp, a, n);
                _ = try fi.allocRegs(n - 1);
            } else {
                try cgExp(fi, exp, a, 1);
            }
        }
        if (!mult_ret) {
            const n = @as(i32, @intCast(n_vars - n_exps));
            const a = try fi.allocRegs(n);
            try fi.emitLoadNil(node.last_line, a, n);
        }
    }

    const last_line = node.last_line;
    for (0.., node.var_list) |i, exp| {
        switch (exp) {
            .name_exp => |name_exp| {
                const var_name = name_exp.name;
                var a = fi.slotOfLocVar(var_name);
                if (a >= 0) {
                    try fi.emitMove(last_line, a, v_regs[i]);
                } else {
                    var b = try fi.indexOfUpval(var_name);
                    if (b >= 0) {
                        try fi.emitSetUpval(last_line, v_regs[i], b);
                    } else {
                        a = fi.slotOfLocVar("_ENV");
                        if (a >= 0) {
                            if (k_regs[i] < 0) {
                                const string_constant = LuaValue.newString(fi.allocator, var_name);
                                b = 0x100 + (try fi.indexOfConstant(string_constant));
                                try fi.emitSetTable(last_line, a, b, v_regs[i]);
                            } else {
                                try fi.emitSetTable(last_line, a, k_regs[i], v_regs[i]);
                            }
                        } else { // global var
                            a = try fi.indexOfUpval("_ENV");
                            if (k_regs[i] < 0) {
                                const string_constant = LuaValue.newString(fi.allocator, var_name);
                                b = 0x100 + (try fi.indexOfConstant(string_constant));
                                try fi.emitSetTabUp(last_line, a, b, v_regs[i]);
                            } else {
                                try fi.emitSetTabUp(last_line, a, k_regs[i], v_regs[i]);
                            }
                        }
                    }
                }
            },
            else => {
                try fi.emitSetTable(last_line, t_regs[i], k_regs[i], v_regs[i]);
            },
        }
    }

    fi.used_regs = old_regs;
}
