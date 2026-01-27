const instruction = @import("instruction.zig");
const opcodes = @import("opcodes.zig");

pub const vm = struct {
    pub const Instruction = instruction.Instruction;
    pub const LuaVM = @import("lua_vm.zig").LuaVM;
    pub const OpCode = opcodes.OpCode;
};
