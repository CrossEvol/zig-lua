const std = @import("std");
const math = std.math;

pub fn FloatToInteger(f: f64) struct { i64, bool } {
    const i: i64 = @intFromFloat(f);
    const exact = @as(f64, @floatFromInt(i)) == f;
    return .{ i, exact };
}

// a % b == a - ((a // b) * b)
pub fn IMod(a: i64, b: i64) i64 {
    return a - IFloorDiv(a, b) * b;
}

// a % b == a - ((a // b) * b)
pub fn FMod(a: f64, b: f64) f64 {
    if (a > 0 and math.isPositiveInf(b) or a < 0 and math.isNegativeInf(b)) {
        return a;
    }
    if (a > 0 and math.isNegativeInf(b) or a < 0 and math.isPositiveInf(b)) {
        return b;
    }
    return a - math.floor(a / b) * b;
}

pub fn IFloorDiv(a: i64, b: i64) i64 {
    if (a > 0 and b > 0 or a < 0 and b < 0 or @rem(a, b) == 0) {
        return @divTrunc(a, b);
    } else {
        return @divTrunc(a, b) - 1;
    }
}

pub fn FFloorDiv(a: f64, b: f64) f64 {
    return math.floor(a / b);
}

pub fn ShiftLeft(a: i64, n: i64) i64 {
    if (n >= 0) {
        return a << @intCast(n);
    } else {
        return ShiftRight(a, -n);
    }
}

pub fn ShiftRight(a: i64, n: i64) i64 {
    if (n >= 0) {
        return @bitCast(@as(u64, @bitCast(a)) >> @intCast(n));
    } else {
        return ShiftLeft(a, -n);
    }
}
