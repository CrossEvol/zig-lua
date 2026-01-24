const fpb = @import("fpb.zig");
const fbToInt = fpb.fbToInt;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// number of list items to accumulate before a SETLIST instruction
const LFIELDS_PER_FLUSH = 50;

// R(A) := {} (size = B,C)
pub fn newTable(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    a += 1;

    vm.createTable(fbToInt(b), fbToInt(c));
    vm.replace(a);
}

// R(A) := R(B)[RK(C)]
pub fn getTable(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    vm.getRK(c);
    _ = vm.getTable(b);
    vm.replace(a);
}

// R(A)[RK(B)] := RK(C)
pub fn setTable(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    a += 1;

    vm.getRK(b);
    vm.getRK(c);
    vm.setTable(a);
}

// R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
pub fn setList(i: Instruction, vm: *LuaVM) void {
    var a, const b, var c = i.ABC();
    a += 1;

    if (c > 0) {
        c = c - 1;
    } else {
        c = Instruction.of(vm.fetch()).Ax();
    }

    _ = vm.checkStack(1);
    var idx = @as(i64, @intCast(c * LFIELDS_PER_FLUSH));
    for (1..@as(usize, @intCast(b + 1))) |j| {
        idx += 1;
        vm.pushValue(a + @as(i32, @intCast(j)));
        vm.setI(a, idx);
    }
}
