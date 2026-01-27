const api = @import("../api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaType = api.LuaType;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A)-=R(A+2); pc+=sBx
pub fn forPrep(i: Instruction, vm: *LuaVM) void {
    var a, const sBx = i.AsBx();
    a += 1;
    if (vm.Type(a) == .lua_t_string) {
        vm.pushNumber(vm.toNumber(a));
        vm.replace(a);
    }
    if (vm.Type(a + 1) == .lua_t_string) {
        vm.pushNumber(vm.toNumber(a + 1));
        vm.replace(a + 1);
    }
    if (vm.Type(a + 2) == .lua_t_string) {
        vm.pushNumber(vm.toNumber(a + 2));
        vm.replace(a + 2);
    }
    vm.pushValue(a);
    vm.pushValue(a + 2);
    vm.arith(ArithOp.lua_op_sub);
    vm.replace(a);
    vm.addPC(sBx);
}

// R(A)+=R(A+2);
//
// if R(A) <?= R(A+1) then {
//   pc+=sBx; R(A+3)=R(A)
// }
pub fn forLoop(i: Instruction, vm: *LuaVM) void {
    var a, const sBx = i.AsBx();
    a += 1;

    // R(A)+=R(A+2);
    vm.pushValue(a + 2);
    vm.pushValue(a);
    vm.arith(ArithOp.lua_op_add);
    vm.replace(a);

    const is_positive_step = vm.toNumber(a + 2) >= 0;
    if (is_positive_step and vm.compare(a, a + 1, CompareOp.lua_op_le) or !is_positive_step and vm.compare(a + 1, a, CompareOp.lua_op_le)) {
        // pc+=sBx; R(A+3)=R(A)
        vm.addPC(sBx);
        vm.copy(a, a + 3);
    }
}
