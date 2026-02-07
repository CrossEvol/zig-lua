const api_arith = @import("api_arith.zig");
const api_compare = @import("api_compare.zig");

pub const state = struct {
    pub const operators = api_arith.operators;
    pub const _arith = api_arith._arith;
    pub const _eq = api_compare._eq;
    pub const _lt = api_compare._lt;
    pub const _le = api_compare._le;
    pub const LuaState = @import("lua_state.zig").LuaState;
    pub const LuaValue = @import("lua_value.zig").LuaValue;
    pub const LuaValueContext = @import("lua_table.zig").LuaValueContext;
};
