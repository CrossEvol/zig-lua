const luaUpvalueIndex = @import("../api/root.zig").Api.luaUpvalueIndex;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A) := UpValue[B]
pub fn getUpval(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.copy(luaUpvalueIndex(b), a);
}

// UpValue[B] := R(A)
pub fn setUpval(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.copy(a, luaUpvalueIndex(b));
}

// R(A) := UpValue[B][RK(C)]
pub fn getTabUp(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    vm.getRK(c);
    _ = vm.getTable(luaUpvalueIndex(b));
    vm.replace(a);
}

// UpValue[A][RK(B)] := RK(C)
pub fn setTabUp(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    a += 1;

    vm.getRK(b);
    vm.getRK(c);
    vm.setTable(luaUpvalueIndex(a));
}
