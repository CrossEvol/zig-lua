const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A) := UpValue[B][RK(C)]
pub fn getTabUp(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    _ = b;
    a += 1;

    vm.pushGlobalTable();
    vm.getRK(c);
    _ = vm.getTable(-2);
    vm.replace(a);
    vm.pop(1);
}
