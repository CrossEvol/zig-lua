const ArithOp = @import("api").ArithOp;
const CompareOp = @import("api").CompareOp;
const LuaType = @import("api").LuaType;

const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// arith
pub fn add(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_add);
} // +
pub fn sub(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_sub);
} // -
pub fn mul(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_mul);
} // *
pub fn mod(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_mod);
} // %
pub fn pow(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_pow);
} // ^
pub fn div(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_div);
} // /
pub fn idiv(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_idiv);
} // //
pub fn band(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_band);
} // &
pub fn bor(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_bor);
} // |
pub fn bxor(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_bxor);
} // ~
pub fn shl(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_shl);
} // <<
pub fn shr(i: Instruction, vm: *LuaVM) void {
    _binaryArith(i, vm, ArithOp.lua_op_shr);
} // >>
pub fn unm(i: Instruction, vm: *LuaVM) void {
    _unaryArith(i, vm, ArithOp.lua_op_unm);
} // -
pub fn bnot(i: Instruction, vm: *LuaVM) void {
    _unaryArith(i, vm, ArithOp.lua_op_bnot);
} // ~

// R(A) := RK(B) op RK(C)
pub fn _binaryArith(i: Instruction, vm: *LuaVM, op: ArithOp) void {
    var a, const b, const c = i.ABC();
    a += 1;

    vm.getRK(b);
    vm.getRK(c);
    vm.arith(op);
    vm.replace(a);
}

// R(A) := op R(B)
pub fn _unaryArith(i: Instruction, vm: *LuaVM, op: ArithOp) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.pushValue(b);
    vm.arith(op);
    vm.replace(a);
}

// compare
pub fn eq(i: Instruction, vm: *LuaVM) void {
    _compare(i, vm, CompareOp.lua_op_eq); // ==
}
pub fn lt(i: Instruction, vm: *LuaVM) void {
    _compare(i, vm, CompareOp.lua_op_lt); // <
}
pub fn le(i: Instruction, vm: *LuaVM) void {
    _compare(i, vm, CompareOp.lua_op_le); // <=
}

// if ((RK(B) op RK(C)) ~= A) then pc++
pub fn _compare(i: Instruction, vm: *LuaVM, op: CompareOp) void {
    const a, const b, const c = i.ABC();

    vm.getRK(b);
    vm.getRK(c);
    if (vm.compare(-2, -1, op) != (a != 0)) {
        vm.addPC(1);
    }
    vm.pop(2);
}

// logical

// R(A) := not R(B)
pub fn not(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.pushBoolean(!vm.toBoolean(b));
    vm.replace(a);
}

// if not (R(A) <=> C) then pc++
pub fn @"test"(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    _ = b;
    a += 1;

    if (vm.toBoolean(a) != (c != 0)) {
        vm.addPC(1);
    }
}

// if (R(B) <=> C) then R(A) := R(B) else pc++
pub fn testSet(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    if (vm.toBoolean(b) == (c != 0)) {
        vm.copy(b, a);
    } else {
        vm.addPC(1);
    }
}

// len & concat

// R(A) := length of R(B)
pub fn length(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    _ = c;
    a += 1;
    b += 1;

    vm.len(b);
    vm.replace(a);
}

// R(A) := R(B).. ... ..R(C)
pub fn concat(i: Instruction, vm: *LuaVM) void {
    var a, var b, var c = i.ABC();
    a += 1;
    b += 1;
    c += 1;

    const n = c - b + 1;
    _ = vm.checkStack(n);
    for (@as(usize, @intCast(b))..@as(usize, @intCast(c + 1))) |j| {
        vm.pushValue(@intCast(j));
    }
    vm.concat(n);
    vm.replace(a);
}
