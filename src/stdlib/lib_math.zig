const std = @import("std");
const math = std.math;

const LuaError = @import("../api/root.zig").LuaError;
const ApiPKg = @import("../api/root.zig");
const number = @import("../number/root.zig");
const default_zig_function_impl = @import("../state/root.zig").default_zig_function_impl;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;
const ZigFunction = StatePkg.ZigFunction;

var mathLib = std.StaticStringMap(?ZigFunction).initComptime(
    .{
        .{ "random", mathRandom },
        .{ "randomseed", mathRandomSeed },
        .{ "max", mathMax },
        .{ "min", mathMin },
        .{ "exp", mathExp },
        .{ "log", mathLog },
        .{ "deg", mathDeg },
        .{ "rad", mathRad },
        .{ "sin", mathSin },
        .{ "cos", mathCos },
        .{ "tan", mathTan },
        .{ "asin", mathAsin },
        .{ "acos", mathAcos },
        .{ "atan", mathAtan },
        .{ "ceil", mathCeil },
        .{ "floor", mathFloor },
        .{ "fmod", mathFmod },
        .{ "modf", mathModf },
        .{ "abs", mathAbs },
        .{ "sqrt", mathSqrt },
        .{ "ult", mathUlt },
        .{ "tointeger", mathToInt },
        .{ "type", mathType },
        // placeholders
        .{ "pi", default_zig_function_impl }, // null
        .{ "huge", default_zig_function_impl }, // null
        .{ "maxinteger", default_zig_function_impl }, // null
        .{ "mininteger", default_zig_function_impl }, // null
    },
);

pub fn openMathLib(ls: *LuaState) LuaError!i32 {
    try ls.newLib(mathLib);
    try ls.pushNumber(math.pi);
    try ls.setField(-2, "pi");
    try ls.pushNumber(math.inf(f64));
    try ls.setField(-2, "huge");
    try ls.pushInteger(math.maxInt(i64));
    try ls.setField(-2, "maxinteger");
    try ls.pushInteger(math.minInt(i64));
    try ls.setField(-2, "mininteger");
    return 1;
}

// pseudo-random numbers

// math.random ([m [, n]])
// http://www.lua.org/manual/5.3/manual.html#pdf-math.random
// lua-5.3.4/src/lmathlib.c#math_random()
pub fn mathRandom(ls: *LuaState) LuaError!i32 {
    var low: i64 = undefined;
    var up: i64 = undefined;
    switch (ls.getTop()) { // check number of arguments
        0 => { // no arguments
            try ls.pushNumber(ls.rand.float64()); // Number between 0 and 1
            return 1;
        },
        1 => { // only upper limit
            low = 1;
            up = try ls.checkInteger(1);
        },
        2 => { // lower and upper limits
            low = try ls.checkInteger(1);
            up = try ls.checkInteger(2);
        },
        else => {
            return ls.error2("wrong number of arguments", .{});
        },
    }

    // random integer in the interval [low, up]
    try ls.argCheck(low <= up, 1, "interval is empty");
    try ls.argCheck(low >= 0 or up <= math.maxInt(i64) + low, 1, "interval too large");
    if (up - low == math.maxInt(i64)) {
        try ls.pushInteger(low + ls.rand.int63());
    } else {
        try ls.pushInteger(low + ls.rand.int63n(up - low + 1));
    }
    return 1;
}

// math.randomseed (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.randomseed
// lua-5.3.4/src/lmathlib.c#math_randomseed()
pub fn mathRandomSeed(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    ls.rand.seed(@as(u64, @bitCast(@as(i64, @intFromFloat(x)))));
    return 0;
}

// max & min

// math.max (x, ···)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.max
// lua-5.3.4/src/lmathlib.c#math_max()
pub fn mathMax(ls: *LuaState) LuaError!i32 {
    const n = ls.getTop(); // number of arguments
    try ls.argCheck(n >= 1, 1, "value expected");

    var i_max: i32 = 1; // index of current maximum value

    var i: i32 = 2;
    while (i <= n) : (i += 1) {
        if (try ls.compare(i_max, i, .lua_op_lt)) {
            i_max = i;
        }
    }

    try ls.pushValue(i_max);
    return 1;
}

// math.min (x, ···)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.min
// lua-5.3.4/src/lmathlib.c#math_min()
pub fn mathMin(ls: *LuaState) LuaError!i32 {
    const n = ls.getTop(); // number of arguments
    try ls.argCheck(n >= 1, 1, "value expected");

    var i_min: i32 = 1; // index of current minimum value

    var i: i32 = 2;
    while (i <= n) : (i += 1) {
        if (try ls.compare(i, i_min, .lua_op_lt)) {
            i_min = i;
        }
    }

    try ls.pushValue(i_min);
    return 1;
}

// exponentiation and logarithms

// math.exp (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.exp
// lua-5.3.4/src/lmathlib.c#math_exp()
pub fn mathExp(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.exp(x));
    return 1;
}

// math.log (x [, base])
// http://www.lua.org/manual/5.3/manual.html#pdf-math.log
// lua-5.3.4/src/lmathlib.c#math_log()
pub fn mathLog(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    var res: f64 = undefined;

    if (ls.isNoneOrNil(2)) {
        res = math.log(f64, math.e, x);
    } else {
        const base = ls.toNumber(2);
        if (base == 2) {
            res = math.log2(x);
        } else if (base == 10) {
            res = math.log10(x);
        } else {
            res = math.log(f64, math.e, x) / math.log(f64, math.e, base);
        }
    }

    try ls.pushNumber(res);
    return 1;
}

// trigonometric functions

// math.deg (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.deg
// lua-5.3.4/src/lmathlib.c#math_deg()
pub fn mathDeg(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(x * 180 / math.pi);
    return 1;
}

// math.rad (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.rad
// lua-5.3.4/src/lmathlib.c#math_rad()
pub fn mathRad(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(x * math.pi / 180);
    return 1;
}

// math.sin (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.sin
// lua-5.3.4/src/lmathlib.c#math_sin()
pub fn mathSin(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.sin(x));
    return 1;
}

// math.cos (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.cos
// lua-5.3.4/src/lmathlib.c#math_cos()
pub fn mathCos(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.cos(x));
    return 1;
}

// math.tan (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.tan
// lua-5.3.4/src/lmathlib.c#math_tan()
pub fn mathTan(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.tan(x));
    return 1;
}

// math.asin (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.asin
// lua-5.3.4/src/lmathlib.c#math_asin()
pub fn mathAsin(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.asin(x));
    return 1;
}

// math.acos (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.acos
// lua-5.3.4/src/lmathlib.c#math_acos()
pub fn mathAcos(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.acos(x));
    return 1;
}

// math.atan (y [, x])
// http://www.lua.org/manual/5.3/manual.html#pdf-math.atan
// lua-5.3.4/src/lmathlib.c#math_atan()
pub fn mathAtan(ls: *LuaState) LuaError!i32 {
    const y = try ls.checkNumber(1);
    const x = try ls.optNumber(2, 1.0);
    try ls.pushNumber(math.atan2(y, x));
    return 1;
}

// rounding functions

// math.ceil (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.ceil
// lua-5.3.4/src/lmathlib.c#math_ceil()
pub fn mathCeil(ls: *LuaState) LuaError!i32 {
    if (ls.isInteger(1)) {
        try ls.setTop(1); // integer is its own ceil
    } else {
        const x = try ls.checkNumber(1);
        try _pushNumInt(ls, math.ceil(x));
    }
    return 1;
}

// math.floor (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.floor
// lua-5.3.4/src/lmathlib.c#math_floor()
pub fn mathFloor(ls: *LuaState) LuaError!i32 {
    if (ls.isInteger(1)) {
        try ls.setTop(1); // integer is its own floor
    } else {
        const x = try ls.checkNumber(1);
        try _pushNumInt(ls, math.floor(x));
    }
    return 1;
}

// others

// math.fmod (x, y)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.fmod
// lua-5.3.4/src/lmathlib.c#math_fmod()
pub fn mathFmod(ls: *LuaState) LuaError!i32 {
    if (ls.isInteger(1) and ls.isInteger(2)) {
        const d = ls.toInteger(2);
        if (@as(u64, @bitCast(d)) + 1 <= 1) { // special cases: -1 or 0
            try ls.argCheck(d != 0, 2, "zero");
            try ls.pushInteger(0); // avoid overflow with 0x80000... / -1
        } else {
            try ls.pushInteger(@rem(ls.toInteger(1), d));
        }
    } else {
        const x = try ls.checkNumber(1);
        const y = try ls.checkNumber(2);
        try ls.pushNumber(x - math.trunc(x / y) * y);
    }
    return 1;
}

// math.modf (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.modf
// lua-5.3.4/src/lmathlib.c#math_modf()
pub fn mathModf(ls: *LuaState) LuaError!i32 {
    if (ls.isInteger(1)) {
        try ls.setTop(1); // number is its own integer part
        try ls.pushNumber(0); // no fractional part
    } else {
        const x = try ls.checkNumber(1);
        const modf = math.modf(x);
        const i = modf.ipart;
        const f = modf.fpart;
        try _pushNumInt(ls, i);
        if (math.isInf(x)) {
            try ls.pushNumber(0);
        } else {
            try ls.pushNumber(f);
        }
    }
    return 2;
}

// math.abs (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.abs
// lua-5.3.4/src/lmathlib.c#math_abs()
pub fn mathAbs(ls: *LuaState) LuaError!i32 {
    if (ls.isInteger(1)) {
        const x = ls.toInteger(1);
        if (x < 0) {
            try ls.pushInteger(-x);
        }
    } else {
        const x = try ls.checkNumber(1);
        try ls.pushNumber(@abs(x));
    }
    return 1;
}

// math.sqrt (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.sqrt
// lua-5.3.4/src/lmathlib.c#math_sqrt()
pub fn mathSqrt(ls: *LuaState) LuaError!i32 {
    const x = try ls.checkNumber(1);
    try ls.pushNumber(math.sqrt(x));
    return 1;
}

// math.ult (m, n)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.ult
// lua-5.3.4/src/lmathlib.c#math_ult()
pub fn mathUlt(ls: *LuaState) LuaError!i32 {
    const m = try ls.checkInteger(1);
    const n = try ls.checkInteger(2);
    try ls.pushBoolean(@as(u64, @bitCast(m)) < @as(u64, @bitCast(n)));
    return 1;
}

// math.tointeger (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.tointeger
// lua-5.3.4/src/lmathlib.c#math_toint()
pub fn mathToInt(ls: *LuaState) LuaError!i32 {
    const i, const ok = ls.toIntegerX(1);
    if (ok) {
        try ls.pushInteger(i);
    } else {
        try ls.checkAny(1);
        try ls.pushNil(); // value is not convertible to integer
    }
    return 1;
}

// math.type (x)
// http://www.lua.org/manual/5.3/manual.html#pdf-math.type
// lua-5.3.4/src/lmathlib.c#math_type()
pub fn mathType(ls: *LuaState) LuaError!i32 {
    if (ls.Type(1) == .lua_t_number) {
        if (ls.isInteger(1)) {
            try ls.pushString("integer");
        } else {
            try ls.pushString("float");
        }
    } else {
        try ls.checkAny(1);
        try ls.pushNil();
    }
    return 1;
}

fn _pushNumInt(ls: *LuaState, d: f64) !void {
    const i, const ok = number.FloatToInteger(d); // does 'd' fit in an integer?
    if (ok) {
        try ls.pushInteger(i); // result is integer
    } else {
        try ls.pushNumber(d); // result is float
    }
}
