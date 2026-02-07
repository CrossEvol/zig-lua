const std = @import("std");

const LuaValue = @import("../../state/root.zig").state.LuaValue;
const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const VarargExp = ExpPkg.VarargExp;
const FuncDefExp = ExpPkg.FuncDefExp;
const TableConstructorExp = ExpPkg.TableConstructorExp;
const UnopExp = ExpPkg.UnopExp;
const BinopExp = ExpPkg.BinopExp;
const ConcatExp = ExpPkg.ConcatExp;
const StringExp = ExpPkg.StringExp;
const NameExp = ExpPkg.NameExp;
const TableAccessExp = ExpPkg.TableAccessExp;
const FuncCallExp = ExpPkg.FuncCallExp;
const CompilerError = @import("../compiler.zig").CompilerError;
const cgBlock = @import("cg_block.zig").cgBlock;
const ExpHelper = @import("exp_helper.zig");
const isVarargOrFuncCall = ExpHelper.isVarargOrFuncCall;
const lastLineOf = ExpHelper.lastLineOf;
const FuncInfo = @import("func_info.zig").FuncInfo;

const ARG_CONST = 1;
const ARG_REG = 2;
const ARG_UPVAL = 4;

const ArgKind = enum(u8) {
    arg_const = ARG_CONST, // const index
    arg_reg = ARG_REG, // register index
    arg_upval = ARG_UPVAL, // upvalue index
    arg_rk = ARG_REG | ARG_CONST,
    arg_ru = ARG_REG | ARG_UPVAL,
    arg_ruk = ARG_REG | ARG_UPVAL | ARG_CONST,
};

pub fn cgExp(fi: *FuncInfo, node: ?Exp, a: i32, n: i32) CompilerError!void {
    if (node) |e| {
        return switch (e) {
            .nil_exp => |exp| try fi.emitLoadNil(exp.line, a, n),
            .false_exp => |exp| try fi.emitLoadBool(exp.line, a, 0, 0),
            .true_exp => |exp| try fi.emitLoadBool(exp.line, a, 1, 0),
            .integer_exp => |exp| try fi.emitLoadK(exp.line, a, .{ .int64 = exp.val }),
            .float_exp => |exp| try fi.emitLoadK(exp.line, a, .{ .float64 = exp.val }),
            .string_exp => |exp| try fi.emitLoadK(exp.line, a, LuaValue.newString(fi.allocator, exp.str)),
            .parens_exp => |exp| try cgExp(fi, exp.exp, a, 1),
            .vararg_exp => |exp| try cgVarargExp(fi, exp, a, n),
            .func_def_exp => |exp| cgFuncDefExp(fi, exp, a),
            .table_constructor_exp => |exp| try cgTableConstructorExp(fi, exp, a),
            .unop_exp => |exp| try cgUnopExp(fi, exp, a),
            .binop_exp => |exp| try cgBinopExp(fi, exp, a),
            .concat_exp => |exp| try cgConcatExp(fi, exp, a),
            .name_exp => |exp| try cgNameExp(fi, exp, a),
            .table_access_exp => |exp| try cgTableAccessExp(fi, exp, a),
            .func_call_exp => |exp| try cgFuncCallExp(fi, exp, a, n),
        };
    }
    return;
}

pub fn cgVarargExp(fi: *FuncInfo, node: VarargExp, a: i32, n: i32) !void {
    if (!fi.is_vararg) {
        std.debug.print("cannot use '...' outside a vararg function", .{});
        return CompilerError.ICompilerError;
    }
    try fi.emitVararg(node.line, a, n);
}

// f[a] := function(args) body end
pub fn cgFuncDefExp(fi: *FuncInfo, node: *FuncDefExp, a: i32) !void {
    var sub_fi = try fi.allocator.create(FuncInfo);
    sub_fi = try FuncInfo.init(fi.allocator, fi, node);
    try fi.sub_funcs.append(fi.allocator, sub_fi);

    if (node.par_list) |params| {
        for (params) |param| {
            _ = try sub_fi.addLocVar(param, 0);
        }
    }

    try cgBlock(sub_fi, node.block);
    try sub_fi.exitScope(sub_fi.PC() + 2);
    try sub_fi.emitReturn(node.last_line, 0, 0);

    const bx = @as(i32, @intCast(fi.sub_funcs.items.len - 1));
    try fi.emitClosure(node.last_line, a, bx);
}

pub fn cgTableConstructorExp(fi: *FuncInfo, node: *TableConstructorExp, a: i32) !void {
    var n_arr: i32 = 0;
    for (node.key_exps) |key_exp| {
        if (key_exp == null) {
            n_arr += 1;
        }
    }
    const n_exps = node.key_exps.len;
    const mult_ret = n_exps > 0 and isVarargOrFuncCall(node.val_exps[n_exps - 1]);

    try fi.emitNewTable(node.line, a, @intCast(n_arr), @as(i32, @intCast(n_exps)) - n_arr);

    var arr_idx: i32 = 0;
    for (0.., node.key_exps) |i, key_exp| {
        const val_exp = node.val_exps[i];

        if (key_exp == null) {
            arr_idx += 1;
            const tmp = try fi.allocReg();
            if (i == n_exps - 1 and mult_ret) {
                try cgExp(fi, val_exp, tmp, -1);
            } else {
                try cgExp(fi, val_exp, tmp, 1);
            }

            if (@mod(arr_idx, 50) == 0 or arr_idx == n_arr) { // LFIELDS_PER_FLUSH
                var n = @mod(arr_idx, 50);
                if (n == 0) {
                    n = 50;
                }
                try fi.freeRegs(n);
                const line = lastLineOf(val_exp);
                const c = @divFloor(arr_idx - 1, 50) + 1; // todo: c > 0xFF
                if (i == n_exps - 1 and mult_ret) {
                    try fi.emitSetList(line, a, 0, c);
                } else {
                    try fi.emitSetList(line, a, n, c);
                }
            }

            continue;
        }

        const b = try fi.allocReg();
        try cgExp(fi, key_exp, b, 1);
        const c = try fi.allocReg();
        try cgExp(fi, val_exp, c, 1);
        try fi.freeRegs(2);

        const line = lastLineOf(val_exp);
        try fi.emitSetTable(line, a, b, c);
    }
}

// r[a] := op exp
pub fn cgUnopExp(fi: *FuncInfo, node: *UnopExp, a: i32) !void {
    const old_regs = fi.used_regs;
    const b, const kindB = try expToOpArg(fi, node.exp, .arg_reg);
    _ = kindB;
    try fi.emitUnaryOp(node.line, node.op, a, b);
    fi.used_regs = old_regs;
}

// r[a] := exp1 op exp2
pub fn cgBinopExp(fi: *FuncInfo, node: *BinopExp, a: i32) !void {
    switch (node.op) {
        .token_op_and, .token_op_or => {
            const old_regs = fi.used_regs;

            var b, var kindB = try expToOpArg(fi, node.exp1, .arg_reg);
            fi.used_regs = old_regs;
            if (node.op == .token_op_and) {
                try fi.emitTestSet(node.line, a, b, 0);
            } else {
                try fi.emitTestSet(node.line, a, b, 1);
            }
            const pc_of_jmp = try fi.emitJmp(node.line, 0, 0);

            b, kindB = try expToOpArg(fi, node.exp2, .arg_reg);
            fi.used_regs = old_regs;
            try fi.emitMove(node.line, a, b);
            fi.fixSbx(pc_of_jmp, fi.PC() - pc_of_jmp);
        },
        else => {
            const old_regs = fi.used_regs;
            const b, const kindB = try expToOpArg(fi, node.exp1, .arg_rk);
            _ = kindB;
            const c, const kindC = try expToOpArg(fi, node.exp2, .arg_rk);
            _ = kindC;
            try fi.emitBinaryOp(node.line, node.op, a, b, c);
            fi.used_regs = old_regs;
        },
    }
}

// r[a] := exp1 .. exp2
pub fn cgConcatExp(fi: *FuncInfo, node: ConcatExp, a0: i32) !void {
    var a = a0;
    for (node.exps) |sub_exp| {
        a = try fi.allocReg();
        try cgExp(fi, sub_exp, a, 1);
    }

    const c = fi.used_regs - 1;
    const b = c - @as(i32, @intCast(node.exps.len)) + 1;
    try fi.freeRegs(c - b + 1);
    try fi.emitABC(node.line, .OP_CONCAT, a, b, c);
}

// r[a] := name
pub fn cgNameExp(fi: *FuncInfo, node: NameExp, a: i32) !void {
    const r = fi.slotOfLocVar(node.name);
    if (r >= 0) {
        try fi.emitMove(node.line, a, r);
        return;
    }

    const idx = try fi.indexOfUpval(node.name);
    if (idx >= 0) {
        try fi.emitGetUpval(node.line, a, idx);
        return;
    }

    // x => _ENV['x']
    const ta_exp = try fi.allocator.create(TableAccessExp);
    ta_exp.* = TableAccessExp.init(
        node.line,
        .{ .name_exp = NameExp.init(node.line, "_ENV") },
        .{ .string_exp = StringExp.init(node.line, node.name) },
    );
    try cgTableAccessExp(fi, ta_exp, a);
}

// r[a] := prefix[key]
pub fn cgTableAccessExp(fi: *FuncInfo, node: *TableAccessExp, a: i32) !void {
    const old_regs = fi.used_regs;
    const b, const kindB = try expToOpArg(fi, node.prefix_exp, .arg_ru);
    const c, const kindC = try expToOpArg(fi, node.key_exp, .arg_rk);
    _ = kindC;
    fi.used_regs = old_regs;

    if (kindB == .arg_upval) {
        try fi.emitGetTabUp(node.last_line, a, b, c);
    } else {
        try fi.emitGetTable(node.last_line, a, b, c);
    }
}

// r[a] := f(args)
pub fn cgFuncCallExp(fi: *FuncInfo, node: *FuncCallExp, a: i32, n: i32) !void {
    const n_args = try prepFuncCall(fi, node, a);
    try fi.emitCall(node.line, a, n_args, n);
}

// return f(args)
pub fn cgTailCallExp(fi: *FuncInfo, node: *FuncCallExp, a: i32) !void {
    const n_args = try prepFuncCall(fi, node, a);
    try fi.emitTailCall(node.line, a, n_args);
}

pub fn prepFuncCall(fi: *FuncInfo, node: *FuncCallExp, a: i32) !i32 {
    var n_args = @as(i32, @intCast(node.args.len));
    var last_arg_is_vararg_or_funccall = false;

    try cgExp(fi, node.prefix_exp, a, 1);
    if (node.name_exp) |name_exp| {
        _ = try fi.allocReg();
        const c, const k = try expToOpArg(fi, .{ .string_exp = name_exp }, .arg_rk);
        try fi.emitSelf(node.line, a, a, c);
        if (k == .arg_reg) {
            try fi.freeRegs(1);
        }
    }
    for (0.., node.args) |i, arg| {
        const tmp = try fi.allocReg();
        if (i == n_args - 1 and isVarargOrFuncCall(arg)) {
            last_arg_is_vararg_or_funccall = true;
            try cgExp(fi, arg, tmp, -1);
        } else {
            try cgExp(fi, arg, tmp, 1);
        }
    }
    try fi.freeRegs(n_args);

    if (node.name_exp) |_| {
        try fi.freeReg();
        n_args += 1;
    }
    if (last_arg_is_vararg_or_funccall) {
        n_args = -1;
    }
    return n_args;
}

/// -> ( arg : i32, argKind : i32 )
pub fn expToOpArg(fi: *FuncInfo, node: Exp, arg_kinds: ArgKind) !struct { i32, ArgKind } {
    if ((@intFromEnum(arg_kinds) & @intFromEnum(ArgKind.arg_const)) > 0) {
        var idx: i32 = -1;
        switch (node) {
            .nil_exp => {
                idx = try fi.indexOfConstant(.{ .nil = {} });
            },
            .false_exp => {
                idx = try fi.indexOfConstant(.{ .bool = false });
            },
            .true_exp => {
                idx = try fi.indexOfConstant(.{ .bool = true });
            },
            .integer_exp => |x| {
                idx = try fi.indexOfConstant(.{ .int64 = x.val });
            },
            .float_exp => |x| {
                idx = try fi.indexOfConstant(.{ .float64 = x.val });
            },
            .string_exp => |x| {
                const string_constant = LuaValue.newString(fi.allocator, x.str);
                idx = try fi.indexOfConstant(string_constant);
            },
            else => {},
        }
        if (idx >= 0 and idx <= 0xFF) {
            return .{ 0x100 + idx, .arg_const };
        }
    }

    switch (node) {
        .name_exp => |name_exp| {
            if ((@intFromEnum(arg_kinds) & @intFromEnum(ArgKind.arg_reg)) > 0) {
                const r = fi.slotOfLocVar(name_exp.name);
                if (r >= 0) {
                    return .{ r, .arg_reg };
                }
            }
            if ((@intFromEnum(arg_kinds) & @intFromEnum(ArgKind.arg_upval)) > 0) {
                const idx = try fi.indexOfUpval(name_exp.name);
                if (idx >= 0) {
                    return .{ idx, .arg_upval };
                }
            }
        },
        else => {},
    }

    const a = try fi.allocReg();
    try cgExp(fi, node, a, 1);
    return .{ a, .arg_reg };
}
