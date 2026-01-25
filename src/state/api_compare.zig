const std = @import("std");

const LuaValue = @import("binchunk").LuaValueNSP.LuaValue;

pub fn _eq(a: LuaValue, b: LuaValue) bool {
    return switch (a) {
        .nil => b == .nil,
        .bool => |x| switch (b) {
            .bool => |y| x == y,
            else => false,
        },
        .string => |x| switch (b) {
            .string => |y| std.mem.eql(u8, x, y),
            else => false,
        },
        .int64 => |x| switch (b) {
            .int64 => |y| x == y,
            .float64 => |y| @as(f64, @floatFromInt(x)) == y,
            else => false,
        },
        .float64 => |x| switch (b) {
            .float64 => |y| x == y,
            .int64 => |y| x == @as(f64, @floatFromInt(y)),
            else => false,
        },
        else => std.meta.eql(a, b),
    };
}

pub fn _lt(a: LuaValue, b: LuaValue) bool {
    return switch (a) {
        .string => |x| switch (b) {
            .string => |y| std.mem.lessThan(u8, x, y),
            else => @panic("comparison error!"),
        },
        .int64 => |x| switch (b) {
            .int64 => |y| x < y,
            .float64 => |y| @as(f64, @floatFromInt(x)) < y,
            else => @panic("comparison error!"),
        },
        .float64 => |x| switch (b) {
            .float64 => |y| x < y,
            .int64 => |y| x < @as(f64, @floatFromInt(y)),
            else => @panic("comparison error!"),
        },
        else => @panic("comparison error!"),
    };
}

pub fn _le(a: LuaValue, b: LuaValue) bool {
    return switch (a) {
        .string => |x| switch (b) {
            .string => |y| std.mem.order(u8, x, y) != .gt,
            else => @panic("comparison error!"),
        },
        .int64 => |x| switch (b) {
            .int64 => |y| x <= y,
            .float64 => |y| @as(f64, @floatFromInt(x)) <= y,
            else => @panic("comparison error!"),
        },
        .float64 => |x| switch (b) {
            .float64 => |y| x <= y,
            .int64 => |y| x <= @as(f64, @floatFromInt(y)),
            else => @panic("comparison error!"),
        },
        else => @panic("comparison error!"),
    };
}
