const Instruction = @import("instruction.zig").Instruction;
const LuaVM = @import("lua_vm.zig").LuaVM;

// R(A+1) := R(B); R(A) := R(B)[RK(C)]
pub fn self(i: Instruction, vm: *LuaVM) void {
    var a, var b, const c = i.ABC();
    a += 1;
    b += 1;

    vm.copy(b, a + 1);
    vm.getRK(c);
    _ = vm.getTable(b);
    vm.replace(a);
}

// R(A) := closure(KPROTO[Bx])
pub fn closure(i: Instruction, vm: *LuaVM) void {
    var a, const bx = i.ABx();
    a += 1;

    vm.loadProto(bx);
    vm.replace(a);
}

// R(A), R(A+1), ..., R(A+B-2) = vararg
pub fn vararg(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    _ = c;
    a += 1;

    if (b != 1) { // b==0 or b>1
        vm.loadVararg(b - 1);
        _popResults(a, b, vm);
    }
}

// R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2));
pub fn tForCall(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    _ = b;
    a += 1;

    _ = _pushFuncAndArgs(a, 3, vm);
    vm.call(2, c);
    _popResults(a + 3, c + 1, vm);
}

// return R(A)(R(A+1), ... ,R(A+B-1))
pub fn tailCall(i: Instruction, vm: *LuaVM) void {
    var a, const b, var c = i.ABC();
    a += 1;

    // todo: optimize tail call!
    c = 0;
    const n_args = _pushFuncAndArgs(a, b, vm);
    vm.call(n_args, c - 1);
    _popResults(a, c, vm);
}

// R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
pub fn call(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    a += 1;

    // println(":::"+ vm.StackToString())
    const n_args = _pushFuncAndArgs(a, b, vm);
    vm.call(n_args, c - 1);
    _popResults(a, c, vm);
}

// return R(A), ... ,R(A+B-2)
pub fn _return(i: Instruction, vm: *LuaVM) void {
    var a, const b, const c = i.ABC();
    _ = c;
    a += 1;

    // Close upvalues before returning
    vm.closeUpvalues(1);

    if (b == 1) {
        // no return values
        return;
    } else if (b > 1) {
        _ = vm.checkStack(b - 1);
        for (@as(usize, @intCast(a))..@as(usize, @intCast(a + b - 1))) |j| {
            vm.pushValue(@as(i32, @intCast(j)));
        }
    } else {
        _fixStack(a, vm);
    }
}

fn _pushFuncAndArgs(a: i32, b: i32, vm: *LuaVM) i32 {
    if (b >= 1) {
        _ = vm.checkStack(b);
        for (@as(usize, @intCast(a))..@as(usize, @intCast(a + b))) |i| {
            vm.pushValue(@as(i32, @intCast(i)));
        }
        return b - 1;
    } else {
        _fixStack(a, vm);
        return @as(i32, @intCast(vm.getTop())) - vm.registerCount() - 1;
    }
}

fn _fixStack(a: i32, vm: *LuaVM) void {
    const x = @as(i32, @intCast(vm.toInteger(-1)));
    vm.pop(1);

    _ = vm.checkStack(x - a);
    for (@as(usize, @intCast(a))..@as(usize, @intCast(x))) |i| {
        vm.pushValue(@as(i32, @intCast(i)));
    }
    vm.rotate(vm.registerCount() + 1, x - a);
}

fn _popResults(a: i32, c: i32, vm: *LuaVM) void {
    if (c == 1) {
        // no results
        return;
    } else if (c > 1) {
        var i = a + c - 2;
        while (i >= a) : (i -= 1) {
            vm.replace(i);
        }
    } else {
        // leave results on stack
        _ = vm.checkStack(1);
        vm.pushInteger(@as(i64, @intCast(a)));
    }
}
