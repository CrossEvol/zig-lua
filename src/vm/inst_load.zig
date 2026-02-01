const LuaError = @import("../api/root.zig").Api.LuaError;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A), R(A+1), ..., R(A+B) := nil
pub fn loadNil(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const b, const c = i.ABC();
    _ = c;
    a += 1;

    try vm.pushNil();
    for (@as(usize, @intCast(a))..@as(usize, @intCast(a + b))) |j| {
        try vm.copy(-1, @as(i32, @intCast(j)));
    }
    try vm.pop(1);
}

// R(A) := (bool)B; if (C) pc++
pub fn loadBool(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const b, const c = i.ABC();
    a += 1;

    try vm.pushBoolean(b != 0);
    try vm.replace(a);

    if (c != 0) {
        vm.addPC(1);
    }
}

// R(A) := Kst(Bx)
pub fn loadK(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const bx = i.ABx();
    a += 1;

    try vm.getConst(bx);
    try vm.replace(a);
}

// R(A) := Kst(extra arg)
pub fn loadKx(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const bx = i.ABx();
    _ = bx;
    a += 1;

    const ax = Instruction.of(vm.fetch()).Ax();

    // vm.checkStack(1);
    try vm.getConst(ax);
    try vm.replace(a);
}
