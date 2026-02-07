const fpb = @import("fpb.zig");
const instruction = @import("instruction.zig");
const opcodes = @import("opcodes.zig");

pub const vm = struct {
    pub const Instruction = instruction.Instruction;
    pub const LuaVM = @import("lua_vm.zig").LuaVM;
    pub const OpCode = opcodes.OpCode;
    pub const MAXARG_sBx = instruction.MAXARG_sBx;
    pub const intToFb = fpb.intToFb;
    pub const fbToInt = fpb.fbToInt;
};
