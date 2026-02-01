const consts = @import("consts.zig");

pub const Api = struct {
    pub const LuaType = consts.LuaType;
    pub const ArithOp = consts.ArithOp;
    pub const LuaError = consts.LuaError;
    pub const CompareOp = consts.CompareOp;
    pub const ThreadStatus = consts.ThreadStatus;
    pub const LUA_MINSTACK = consts.LUA_MINSTACK;
    pub const LUA_REGISTRYINDEX = consts.LUA_REGISTRYINDEX;
    pub const LUA_RIDX_GLOBALS = consts.LUA_RIDX_GLOBALS;
    pub const luaUpvalueIndex = consts.luaUpvalueIndex;
};
