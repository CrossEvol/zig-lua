pub const LuaType = enum(i8) {
    lua_t_none = -1,
    lua_t_nil = 0,
    lua_t_boolean,
    lua_t_light_userdata,
    lua_t_number,
    lua_t_string,
    lua_t_table,
    lua_t_function,
    lua_t_userdata,
    lua_t_thread,
};
