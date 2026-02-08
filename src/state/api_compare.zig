const std = @import("std");

const LuaError = @import("../api/root.zig").Api.LuaError;
const binchunk = @import("../binchunk/root.zig").binchunk;
const callMetamethod = @import("lua_value.zig").callMetamethod;
const convertToBoolean = @import("lua_value.zig").convertToBoolean;
const LuaState = @import("lua_state.zig").LuaState;
const LuaValue = @import("lua_value.zig").LuaValue;

pub fn _eq(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) LuaError!bool {
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
        .obj => |obj| switch (obj.kind) {
            .string => |_| switch (b) {
                .obj => |b_obj| switch (b_obj.kind) {
                    .string => |_| a.asStr().hash() == b.asStr().hash(),
                    else => false,
                },
                else => false,
            },
            .lua_table => |_| {
                const x = a.asTable();
                var ok = b.isTable();
                const y = if (ok) b.asTable() else undefined;
                if (ok and x != y and ls != null) {
                    const result, ok = try callMetamethod(allocator, a, b, "__eq", ls.?);
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

pub fn _lt(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) LuaError!bool {
    return switch (a) {
        .int64 => |x| switch (b) {
            .int64 => |y| x < y,
            .float64 => |y| @as(f64, @floatFromInt(x)) < y,
            else => {
                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            },
        },
        .float64 => |x| switch (b) {
            .float64 => |y| x < y,
            .int64 => |y| x < @as(f64, @floatFromInt(y)),
            else => {
                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            },
        },
        .obj => |obj| switch (obj.kind) {
            .string => |_| switch (b) {
                .obj => |b_obj| switch (b_obj.kind) {
                    .string => |_| std.mem.lessThan(u8, a.asStr().data(), b.asStr().data()),
                    else => {
                        try ls.?.pushString("comparison error!");
                        return LuaError.Panic;
                    },
                },
                else => {
                    try ls.?.pushString("comparison error!");
                    return LuaError.Panic;
                },
            },
            else => {
                const result, const ok = try callMetamethod(allocator, a, b, "__lt", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                } else {
                    try ls.?.pushString("comparison error!");
                    return LuaError.Panic;
                }
            },
        },
        else => {
            const result, const ok = try callMetamethod(allocator, a, b, "__lt", ls.?);
            if (ok) {
                return convertToBoolean(result);
            } else {
                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            }
        },
    };
}

pub fn _le(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, ls: ?*LuaState) LuaError!bool {
    return switch (a) {
        .int64 => |x| switch (b) {
            .int64 => |y| x <= y,
            .float64 => |y| @as(f64, @floatFromInt(x)) <= y,
            else => {
                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            },
        },
        .float64 => |x| switch (b) {
            .float64 => |y| x <= y,
            .int64 => |y| x <= @as(f64, @floatFromInt(y)),
            else => {
                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            },
        },
        .obj => |obj| switch (obj.kind) {
            .string => |_| switch (b) {
                .obj => |b_obj| switch (b_obj.kind) {
                    .string => |_| std.mem.order(u8, a.asStr().data(), b.asStr().data()) != .gt,
                    else => {
                        try ls.?.pushString("comparison error!");
                        return LuaError.Panic;
                    },
                },
                else => {
                    try ls.?.pushString("comparison error!");
                    return LuaError.Panic;
                },
            },
            else => {
                var result, var ok = try callMetamethod(allocator, a, b, "__le", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                }
                result, ok = try callMetamethod(allocator, b, a, "__lt", ls.?);
                if (ok) {
                    return convertToBoolean(result);
                }

                try ls.?.pushString("comparison error!");
                return LuaError.Panic;
            },
        },
        else => {
            try ls.?.pushString("comparison error!");
            return LuaError.Panic;
        },
    };
}
