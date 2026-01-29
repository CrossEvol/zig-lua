const std = @import("std");
const math = std.math;

const binchunk = @import("../binchunk/root.zig").binchunk;
const number = @import("../number//root.zig").number;
pub const Closure = @import("closure.zig").Closure;
const convertToFloat = @import("lua_value.zig").convertToFloat;
const convertToInteger = @import("lua_value.zig").convertToInteger;
pub const LuaTable = @import("lua_table.zig").LuaTable;
pub const LuaValue = @import("lua_value.zig").LuaValue;

const IntegerFunc = *const fn (a: i64, b: i64) i64;
const FloatFunc = *const fn (a: f64, b: f64) f64;

const Operator = struct {
    int_func: ?IntegerFunc,
    float_func: ?FloatFunc,
};

fn iadd(a: i64, b: i64) i64 {
    return a +% b;
}
fn fadd(a: f64, b: f64) f64 {
    return a + b;
}
fn isub(a: i64, b: i64) i64 {
    return a -% b;
}
fn fsub(a: f64, b: f64) f64 {
    return a - b;
}
fn imul(a: i64, b: i64) i64 {
    return a *% b;
}
fn fmul(a: f64, b: f64) f64 {
    return a * b;
}
fn imod(a: i64, b: i64) i64 {
    return number.IMod(a, b);
}
fn fmod(a: f64, b: f64) f64 {
    return number.FMod(a, b);
}
fn fpow(a: f64, b: f64) f64 {
    return math.pow(f64, a, b);
}
fn fdiv(a: f64, b: f64) f64 {
    return a / b;
}
fn iidiv(a: i64, b: i64) i64 {
    return number.IFloorDiv(a, b);
}
fn fidiv(a: f64, b: f64) f64 {
    return number.FFloorDiv(a, b);
}
fn band(a: i64, b: i64) i64 {
    return a & b;
}
fn bor(a: i64, b: i64) i64 {
    return a | b;
}
fn bxor(a: i64, b: i64) i64 {
    return a ^ b;
}
fn shl(a: i64, b: i64) i64 {
    return number.ShiftLeft(a, b);
}
fn shr(a: i64, b: i64) i64 {
    return number.ShiftRight(a, b);
}
fn iunm(a: i64, _: i64) i64 {
    return -%a;
}
fn funm(a: f64, _: f64) f64 {
    return -a;
}
fn bnot(a: i64, _: i64) i64 {
    return ~a;
}

fn operator(i: ?IntegerFunc, f: ?FloatFunc) Operator {
    return .{ .int_func = i, .float_func = f };
}

pub const operators = [_]Operator{
    operator(iadd, fadd),
    operator(isub, fsub),
    operator(imul, fmul),
    operator(imod, fmod),
    operator(null, fpow),
    operator(null, fdiv),
    operator(iidiv, fidiv),
    operator(band, null),
    operator(bor, null),
    operator(bxor, null),
    operator(shl, null),
    operator(shr, null),
    operator(iunm, funm),
    operator(bnot, null),
};

pub fn _arith(a: LuaValue, b: LuaValue, op: Operator) LuaValue {
    if (op.float_func == null) { // bitwise
        const x, var ok = convertToInteger(a);
        if (ok) {
            const y, ok = convertToInteger(b);
            if (ok) {
                return .{ .int64 = op.int_func.?(x, y) };
            }
        }
    } else { // arith
        if (op.int_func != null) { // add,sub,mul,mod,idiv,unm
            if (a == .int64 and b == .int64) {
                return .{ .int64 = op.int_func.?(a.int64, b.int64) };
            }
        }
        const x, var ok = convertToFloat(a);
        if (ok) {
            const y, ok = convertToFloat(b);
            if (ok) {
                return .{ .float64 = op.float_func.?(x, y) };
            }
        }
    }
    return LuaValue.LUA_NIL;
}
