const ExpPkg = @import("../ast/exp.zig");
const Exp = ExpPkg.Exp;
const NilExp = ExpPkg.NilExp;
const TrueExp = ExpPkg.TrueExp;
const FalseExp = ExpPkg.FalseExp;
const IntegerExp = ExpPkg.IntegerExp;
const FloatExp = ExpPkg.FloatExp;
const StringExp = ExpPkg.StringExp;
const VarargExp = ExpPkg.VarargExp;
const NameExp = ExpPkg.NameExp;
const FuncDefExp = ExpPkg.FuncDefExp;
const FuncCallExp = ExpPkg.FuncCallExp;
const TableConstructorExp = ExpPkg.TableConstructorExp;
const TableAccessExp = ExpPkg.TableAccessExp;
const ConcatExp = ExpPkg.ConcatExp;
const BinopExp = ExpPkg.BinopExp;
const UnopExp = ExpPkg.UnopExp;

pub fn isVarargOrFuncCall(exp: ?Exp) bool {
    if (exp) |e| {
        return switch (e) {
            .vararg_exp, .func_call_exp => true,
            else => false,
        };
    }
    return false;
}

pub fn removeTailNils(exps0: ?[]Exp) []Exp {
    if (exps0) |exps| {
        if (exps.len > 0) {
            var n: usize = exps.len - 1;
            while (n >= 0) {
                switch (exps[n]) {
                    .nil_exp => {},
                    else => {
                        return exps[0 .. n + 1];
                    },
                }
                if (n > 0) {
                    n -= 1;
                }
            }
        }
    }
    return &.{};
}

pub fn lineOf(exp: ?Exp) i32 {
    if (exp) |e| {
        return switch (e) {
            .nil_exp => |x| x.line,
            .true_exp => |x| x.line,
            .false_exp => |x| x.line,
            .integer_exp => |x| x.line,
            .float_exp => |x| x.line,
            .string_exp => |x| x.line,
            .vararg_exp => |x| x.line,
            .name_exp => |x| x.line,
            .func_def_exp => |x| x.line,
            .func_call_exp => |x| x.line,
            .table_constructor_exp => |x| x.line,
            .unop_exp => |x| x.line,
            .table_access_exp => |x| lineOf(x.prefix_exp),
            .concat_exp => |x| lineOf(x.exps[0]),
            .binop_exp => |x| lineOf(x.exp1),
            else => @panic("unreachable!"),
        };
    }
    @panic("unreachable!");
}

pub fn lastLineOf(exp: ?Exp) i32 {
    if (exp) |e| {
        return switch (e) {
            .nil_exp => |x| x.line,
            .true_exp => |x| x.line,
            .false_exp => |x| x.line,
            .integer_exp => |x| x.line,
            .float_exp => |x| x.line,
            .string_exp => |x| x.line,
            .vararg_exp => |x| x.line,
            .name_exp => |x| x.line,
            .func_def_exp => |x| x.last_line,
            .func_call_exp => |x| x.last_line,
            .table_constructor_exp => |x| x.last_line,
            .table_access_exp => |x| x.last_line,
            .concat_exp => |x| lastLineOf(x.exps[x.exps.len - 1]),
            .binop_exp => |x| lastLineOf(x.exp2),
            .unop_exp => |x| lastLineOf(x.exp),
            else => @panic("unreachable!"),
        };
    }
    @panic("unreachable!");
}
