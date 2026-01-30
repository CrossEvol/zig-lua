const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const callMetamethod = @import("lua_value.zig").callMetamethod;
const convertToBoolean = @import("lua_value.zig").convertToBoolean;
const LuaState = @import("lua_state.zig").LuaState;
const LuaValue = @import("lua_value.zig").LuaValue;

pub fn _eq(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) bool {
    return switch (a) {
        .nil => b == .nil,
        .bool => |x| switch (b) {
            .bool => |y| x == y,
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
        .obj => |obj| switch (obj.*.as) {
            .string => |x| switch (b) {
                .obj => |b_obj| switch (b_obj.*.as) {
                    .string => |y| x.hash() == y.hash(),
                    else => false,
                },
                else => false,
            },
            .lua_table => |x| {
                var ok = b.isTable();
                const y = b.asTable();
                if (ok and x != y and ls != null) {
                    const result, ok = callMetamethod(allocator, a, b, "__eq", ls.?);
                    if (ok) {
                        return convertToBoolean(result);
                    }
                }

                return std.meta.eql(a, b);
            },
            else => std.meta.eql(a, b),
        },
    };
}

pub fn _lt(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) bool {
    return switch (a) {
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
        .obj => |obj| switch (obj.*.as) {
            .string => |x| switch (b) {
                .obj => |b_obj| switch (b_obj.*.as) {
                    .string => |y| std.mem.lessThan(u8, x.data(), y.data()),
                    else => @panic("comparison error!"),
                },
                else => @panic("comparison error!"),
            },
            else => {
                const result, const ok = callMetamethod(allocator, a, b, "__lt", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                } else {
                    @panic("comparison error!");
                }
            },
        },
        else => {
            const result, const ok = callMetamethod(allocator, a, b, "__lt", ls.?);
            if (ok) {
                return convertToBoolean(result);
            } else {
                @panic("comparison error!");
            }
        },
    };
}

pub fn _le(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) bool {
    return switch (a) {
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
        .obj => |obj| switch (obj.*.as) {
            .string => |x| switch (b) {
                .obj => |b_obj| switch (b_obj.*.as) {
                    .string => |y| std.mem.order(u8, x.data(), y.data()) != .gt,
                    else => @panic("comparison error!"),
                },
                else => @panic("comparison error!"),
            },
            else => {
                var result, var ok = callMetamethod(allocator, a, b, "__le", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                }
                result, ok = callMetamethod(allocator, b, a, "__lt", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                }
                @panic("comparison error!");
            },
        },
        else => @panic("comparison error!"),
    };
}
