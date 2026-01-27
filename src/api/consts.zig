pub const LUA_MINSTACK = 20;
const LUAI_MAXSTACK = 1000000;
pub const LUA_REGISTRYINDEX = -LUAI_MAXSTACK - 1000;
pub const LUA_RIDX_GLOBALS = 2;

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

pub const ArithOp = enum {
    lua_op_add, // +
    lua_op_sub, // -
    lua_op_mul, // *
    lua_op_mod, // %
    lua_op_pow, // ^
    lua_op_div, // /
    lua_op_idiv, // //
    lua_op_band, // &
    lua_op_bor, // |
    lua_op_bxor, // ~
    lua_op_shl, // <<
    lua_op_shr, // >>
    lua_op_unm, // -
    lua_op_bnot, // ~
};

pub const CompareOp = enum {
    lua_op_eq, // ==
    lua_op_lt, // <
    lua_op_le, // <=
};
