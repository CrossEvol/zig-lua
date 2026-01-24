const instruction = @import("instruction.zig");
pub const Instruction = instruction.Instruction;
pub const LuaVM = @import("lua_vm.zig").LuaVM;
const opcodes = @import("opcodes.zig");
pub const OpCode = opcodes.OpCode;
