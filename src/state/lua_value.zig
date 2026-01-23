const std = @import("std");

const LuaType = @import("api").LuaType;

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
