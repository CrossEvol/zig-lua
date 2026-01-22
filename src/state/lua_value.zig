const std = @import("std");

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
