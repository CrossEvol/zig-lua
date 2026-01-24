const std = @import("std");

const number = @import("number");

const LuaType = @import("consts.zig").LuaType;

const string = []const u8;

pub const LuaValue = union(enum) {
    nil: void,
    bool: bool,
    int64: i64,
    float64: f64,
    string: string,
    lua_table: void,
    closure: void,
    lua_state: void,

    pub fn deinit(self: *LuaValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }

    pub fn clone(self: LuaValue, allocator: std.mem.Allocator) LuaValue {
        return switch (self) {
            .string => |s| .{ .string = allocator.dupe(u8, s) catch @panic("clone allocation failed") },
            else => self,
        };
    }
};

pub fn typeOf(val: LuaValue) LuaType {
    return switch (val) {
        .nil => LuaType.lua_t_nil,
        .bool => LuaType.lua_t_boolean,
        .int64, .float64 => LuaType.lua_t_number,
        .string => LuaType.lua_t_string,
        else => @panic("todo!"),
    };
}

pub fn convertToBoolean(val: LuaValue) bool {
    return switch (val) {
        .nil => false,
        .bool => |x| x,
        else => true,
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToFloat(val: LuaValue) struct { f64, bool } {
    return switch (val) {
        .int64 => |x| .{ @floatFromInt(x), true },
        .float64 => |x| .{ x, true },
        .string => |x| number.parseFloat(x),
        else => .{ 0, false },
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToInteger(val: LuaValue) struct { i64, bool } {
    return switch (val) {
        .int64 => |x| .{ x, true },
        .float64 => |x| number.FloatToInteger(x),
        .string => |x| _stringToInteger(x),
        else => .{ 0, false },
    };
}

fn _stringToInteger(s: string) struct { i64, bool } {
    const i, var ok = number.parseInteger(s);
    if (ok) {
        return .{ i, true };
    }
    const f, ok = number.parseFloat(s);
    if (ok) {
        return number.FloatToInteger(f);
    }
    return .{ 0, false };
}
