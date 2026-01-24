const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A) := R(B)
pub fn move(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.copy(b, a);
}

// pc+=sBx; if (A) close all upvalues >= R(A - 1)
pub fn jmp(i: Instruction, vm: *LuaVM) void {
    const a, const sBx = i.AsBx();

    vm.addPC(sBx);
    if (a != 0) {
        @panic("todo: jmp!");
    }
}
