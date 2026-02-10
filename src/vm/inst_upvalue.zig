const luaUpvalueIndex = @import("../api/root.zig").luaUpvalueIndex;
const LuaError = @import("../api/root.zig").LuaError;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A) := UpValue[B]
pub fn getUpval(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    try vm.copy(luaUpvalueIndex(b), a);
}

// UpValue[B] := R(A)
pub fn setUpval(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    try vm.copy(a, luaUpvalueIndex(b));
}

// R(A) := UpValue[B][RK(C)]
pub fn getTabUp(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    try vm.getRK(c);
    _ = try vm.getTable(luaUpvalueIndex(b));
    try vm.replace(a);
}

// UpValue[A][RK(B)] := RK(C)
pub fn setTabUp(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const b, const c = i.ABC();
    a += 1;

    try vm.getRK(b);
    try vm.getRK(c);
    try vm.setTable(luaUpvalueIndex(a));
}
