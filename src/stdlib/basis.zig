const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const StatePkg = @import("../state/root.zig");
const LuaState = StatePkg.LuaState;

pub fn baseFuncImpl(ls: *LuaState) LuaError!i32 {
    _ = ls;
    return LuaError.Panic;
}
