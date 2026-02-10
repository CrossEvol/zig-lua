const std = @import("std");

const number = @import("../../number/root.zig");
const AstPkg = @import("../ast/root.zig");
const Exp = AstPkg.Exp;
const BinopExp = AstPkg.BinopExp;
const IntegerExp = AstPkg.IntegerExp;
const FloatExp = AstPkg.FloatExp;
const UnopExp = AstPkg.UnopExp;
const NilExp = AstPkg.NilExp;
const TrueExp = AstPkg.TrueExp;
const FalseExp = AstPkg.FalseExp;
const StringExp = AstPkg.StringExp;
const VarargExp = AstPkg.VarargExp;
const FuncCallExp = AstPkg.FuncCallExp;
const TokenPkg = @import("../lexer/root.zig");
const TOKEN_OP_UNM = TokenPkg.TOKEN_OP_UNM;
const TOKEN_OP_SUB = TokenPkg.TOKEN_OP_SUB;
const TOKEN_OP_BXOR = TokenPkg.TOKEN_OP_BXOR;
const TOKEN_OP_BNOT = TokenPkg.TOKEN_OP_BNOT;

pub fn optimizeLogicalOr(exp: *BinopExp) Exp {
    if (isTrue(exp.exp1)) {
        return exp.exp1; // true or x => true
    }
    if (isFalse(exp.exp1) and !isVarargOrFuncCall(exp.exp2)) {
        return exp.exp2; // false or x => x
    }
    return .{ .binop_exp = exp };
}

pub fn optimizeLogicalAnd(exp: *BinopExp) Exp {
    if (isFalse(exp.exp1)) {
        return exp.exp1; // false and x => false
    }
    if (isTrue(exp.exp1) and !isVarargOrFuncCall(exp.exp2)) {
        return exp.exp2; // true and x => x
    }
    return .{ .binop_exp = exp };
}

pub fn optimizeBitwiseBinaryOp(exp: *BinopExp) Exp {
    const i, var ok = castToInt(exp.exp1);
    if (ok) {
        const j, ok = castToInt(exp.exp2);
        if (ok) {
            return switch (exp.op) {
                .token_op_band => .{ .integer_exp = IntegerExp.init(exp.line, i & j) },
                .token_op_bor => .{ .integer_exp = IntegerExp.init(exp.line, i | j) },
                TOKEN_OP_BXOR => .{ .integer_exp = IntegerExp.init(exp.line, i ^ j) }, // TOKEN_OP_BXOR
                .token_op_shl => .{ .integer_exp = IntegerExp.init(exp.line, number.ShiftLeft(i, j)) },
                .token_op_shr => .{ .integer_exp = IntegerExp.init(exp.line, number.ShiftRight(i, j)) },
                else => .{ .binop_exp = exp },
            };
        }
    }
    return .{ .binop_exp = exp };
}

pub fn optimizeArithBinaryOp(exp: *BinopExp) Exp {
    var ok = exp.exp1.isIntegerExp();
    if (ok) {
        const x = exp.exp1.asIntegerExp();
        ok = exp.exp2.isIntegerExp();
        if (ok) {
            const y = exp.exp2.asIntegerExp();
            switch (exp.op) {
                .token_op_add => {
                    return .{ .integer_exp = IntegerExp.init(exp.line, x.val + y.val) };
                },
                TOKEN_OP_SUB => { // TOKEN_OP_SUB
                    return .{ .integer_exp = IntegerExp.init(exp.line, x.val - y.val) };
                },
                .token_op_mul => {
                    return .{ .integer_exp = IntegerExp.init(exp.line, x.val * y.val) };
                },
                .token_op_idiv => {
                    if (y.val != 0) {
                        return .{ .integer_exp = IntegerExp.init(exp.line, number.IFloorDiv(x.val, y.val)) };
                    }
                },
                .token_op_mod => {
                    if (y.val != 0) {
                        return .{ .integer_exp = IntegerExp.init(exp.line, number.IMod(x.val, y.val)) };
                    }
                },
                else => {},
            }
        }
    }
    const f, ok = castToFloat(exp.exp1);
    if (ok) {
        const g, ok = castToFloat(exp.exp2);
        if (ok) {
            switch (exp.op) {
                .token_op_add => {
                    return .{ .float_exp = FloatExp.init(exp.line, f + g) };
                },
                TOKEN_OP_SUB => {
                    return .{ .float_exp = FloatExp.init(exp.line, f - g) };
                },
                .token_op_mul => {
                    return .{ .float_exp = FloatExp.init(exp.line, f * g) };
                },
                .token_op_div => {
                    return .{ .float_exp = FloatExp.init(exp.line, f / g) };
                },
                .token_op_idiv => {
                    return .{ .float_exp = FloatExp.init(exp.line, number.FFloorDiv(f, g)) };
                },
                .token_op_mod => {
                    return .{ .float_exp = FloatExp.init(exp.line, number.FMod(f, g)) };
                },
                .token_op_pow => {
                    return .{ .float_exp = FloatExp.init(exp.line, std.math.pow(f64, f, g)) };
                },
                else => {},
            }
        }
    }
    return .{ .binop_exp = exp };
}

pub fn optimizePow(exp: Exp) Exp {
    switch (exp) {
        .binop_exp => |binop| {
            if (binop.op == .token_op_pow) {
                binop.exp2 = optimizePow(binop.exp2);
            }
            return optimizeArithBinaryOp(binop);
        },
        else => {},
    }
    return exp;
}

pub fn optimizeUnaryOp(exp: *UnopExp) Exp {
    return switch (exp.op) {
        TOKEN_OP_UNM => optimizeUnm(exp),
        .token_op_not => optimizeNot(exp),
        TOKEN_OP_BNOT => optimizeBnot(exp),
        else => .{ .unop_exp = exp },
    };
}

pub fn optimizeUnm(exp: *UnopExp) Exp {
    switch (exp.exp) { // number?
        .integer_exp => |x| {
            return .{ .integer_exp = IntegerExp.init(x.line, -x.val) };
        },
        .float_exp => |x| {
            if (x.val != 0) {
                return .{ .float_exp = FloatExp.init(x.line, -x.val) };
            }
        },
        else => {},
    }
    return .{ .unop_exp = exp };
}

pub fn optimizeNot(exp: *UnopExp) Exp {
    return switch (exp.exp) {
        .nil_exp, .false_exp => .{ .true_exp = TrueExp.init(exp.line) }, // false
        .true_exp, .integer_exp, .float_exp, .string_exp => .{ .false_exp = FalseExp.init(exp.line) }, // true
        else => .{ .unop_exp = exp },
    };
}

pub fn optimizeBnot(exp: *UnopExp) Exp {
    switch (exp.exp) { // number?
        .integer_exp => |x| {
            return .{ .integer_exp = IntegerExp.init(x.line, ~x.val) };
        },
        .float_exp => |x| {
            const i, const ok = number.FloatToInteger(x.val);
            if (ok) {
                return .{ .integer_exp = IntegerExp.init(x.line, ~i) };
            }
        },
        else => {},
    }
    return .{ .unop_exp = exp };
}

fn isFalse(exp: Exp) bool {
    return switch (exp) {
        .false_exp, .nil_exp => true,
        else => false,
    };
}

fn isTrue(exp: Exp) bool {
    return switch (exp) {
        .true_exp, .integer_exp, .float_exp, .string_exp => true,
        else => false,
    };
}

fn isVarargOrFuncCall(exp: Exp) bool {
    return switch (exp) {
        .vararg_exp, .func_call_exp => true,
        else => false,
    };
}

fn castToInt(exp: Exp) struct { i64, bool } {
    return switch (exp) {
        .integer_exp => |x| .{ x.val, true },
        .float_exp => |x| number.FloatToInteger(x.val),
        else => .{ 0, false },
    };
}

fn castToFloat(exp: Exp) struct { f64, bool } {
    return switch (exp) {
        .integer_exp => |x| .{ @as(f64, @floatFromInt(x.val)), true },
        .float_exp => |x| .{ x.val, true },
        else => .{ 0, false },
    };
}
