const LuaError = @import("../api/root.zig").LuaError;
const fpb = @import("fpb.zig");
const fbToInt = fpb.fbToInt;
const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// number of list items to accumulate before a SETLIST instruction
const LFIELDS_PER_FLUSH = 50;

// R(A) := {} (size = B,C)
pub fn newTable(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const b, const c = i.ABC();
    a += 1;

    try vm.createTable(fbToInt(b), fbToInt(c));
    try vm.replace(a);
}

// R(A) := R(B)[RK(C)]
pub fn getTable(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    try vm.getRK(c);
    _ = try vm.getTable(b);
    try vm.replace(a);
}

// R(A)[RK(B)] := RK(C)
pub fn setTable(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, const b, const c = i.ABC();
    a += 1;

    try vm.getRK(b);
    try vm.getRK(c);
    try vm.setTable(a);
}

// R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
pub fn setList(i: Instruction, vm: *LuaVM) LuaError!void {
    var a, var b, var c = i.ABC();
    a += 1;

    if (c > 0) {
        c = c - 1;
    } else {
        c = Instruction.of(vm.fetch()).Ax();
    }

    const b_is_zero = b == 0;
    if (b_is_zero) {
        b = @as(i32, @intCast(vm.toInteger(-1))) - a - 1;
        try vm.pop(1);
    }

    _ = vm.checkStack(1);
    var idx = @as(i64, @intCast(c * LFIELDS_PER_FLUSH));
    for (1..@as(usize, @intCast(b + 1))) |j| {
        idx += 1;
        try vm.pushValue(a + @as(i32, @intCast(j)));
        try vm.setI(a, idx);
    }

    if (b_is_zero) {
        const start = @as(usize, @intCast(vm.registerCount() + 1));
        const end = @as(usize, @intCast(vm.getTop() + 1));
        for (start..end) |j| {
            idx += 1;
            try vm.pushValue(@as(i32, @intCast(j)));
            try vm.setI(a, idx);
        }

        // clear stack
        try vm.setTop(vm.registerCount());
    }
}
