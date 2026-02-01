const LuaError = @import("../api/root.zig").Api.LuaError;
const InstCall = @import("inst_call.zig");
const self = InstCall.self;
const call = InstCall.call;
const tailCall = InstCall.tailCall;
const _return = InstCall._return;
const closure = InstCall.closure;
const vararg = InstCall.vararg;
const tForCall = InstCall.tForCall;
const InstFor = @import("inst_for.zig");
const forPrep = InstFor.forPrep;
const forLoop = InstFor.forLoop;
const tForLoop = InstFor.tForLoop;
const InstLoad = @import("inst_load.zig");
const loadNil = InstLoad.loadNil;
const loadBool = InstLoad.loadBool;
const loadK = InstLoad.loadK;
const loadKx = InstLoad.loadKx;
const InstMisc = @import("inst_misc.zig");
const move = InstMisc.move;
const jmp = InstMisc.jmp;
const InstOperators = @import("inst_operators.zig");
const add = InstOperators.add;
const sub = InstOperators.sub;
const mul = InstOperators.mul;
const mod = InstOperators.mod;
const pow = InstOperators.pow;
const div = InstOperators.div;
const idiv = InstOperators.idiv;
const band = InstOperators.band;
const bor = InstOperators.bor;
const bxor = InstOperators.bxor;
const shl = InstOperators.shl;
const shr = InstOperators.shr;
const unm = InstOperators.unm;
const bnot = InstOperators.bnot;
const eq = InstOperators.eq;
const lt = InstOperators.lt;
const le = InstOperators.le;
const not = InstOperators.not;
const @"test" = InstOperators.@"test";
const testSet = InstOperators.testSet;
const length = InstOperators.length;
const concat = InstOperators.concat;
const Instruction = @import("instruction.zig").Instruction;
const InstTable = @import("inst_table.zig");
const newTable = InstTable.newTable;
const getTable = InstTable.getTable;
const setTable = InstTable.setTable;
const setList = InstTable.setList;
const InstUpvalue = @import("inst_upvalue.zig");
const getUpval = InstUpvalue.getUpval;
const setUpval = InstUpvalue.setUpval;
const getTabUp = InstUpvalue.getTabUp;
const setTabUp = InstUpvalue.setTabUp;
const LuaVM = @import("lua_vm.zig").LuaVM;

// inst functions
const byte = u8;
const string = []const u8;
// basic instruction format
pub const OpMode = enum {
    IABC, // [  B:9  ][  C:9  ][ A:8  ][OP:6]
    IABx, // [      Bx:18     ][ A:8  ][OP:6]
    IAsBx, // [     sBx:18     ][ A:8  ][OP:6]
    IAx, // [           Ax:26        ][OP:6]
};

pub const OpArgMask = enum {
    OpArgN, // argument is not used
    OpArgU, // argument is used
    OpArgR, // argument is a register or a jump offset
    OpArgK, // argument is a constant or register/constant
};

pub const OpCode = enum {
    OP_MOVE,
    OP_LOADK,
    OP_LOADKX,
    OP_LOADBOOL,
    OP_LOADNIL,
    OP_GETUPVAL,
    OP_GETTABUP,
    OP_GETTABLE,
    OP_SETTABUP,
    OP_SETUPVAL,
    OP_SETTABLE,
    OP_NEWTABLE,
    OP_SELF,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_MOD,
    OP_POW,
    OP_DIV,
    OP_IDIV,
    OP_BAND,
    OP_BOR,
    OP_BXOR,
    OP_SHL,
    OP_SHR,
    OP_UNM,
    OP_BNOT,
    OP_NOT,
    OP_LEN,
    OP_CONCAT,
    OP_JMP,
    OP_EQ,
    OP_LT,
    OP_LE,
    OP_TEST,
    OP_TESTSET,
    OP_CALL,
    OP_TAILCALL,
    OP_RETURN,
    OP_FORLOOP,
    OP_FORPREP,
    OP_TFORCALL,
    OP_TFORLOOP,
    OP_SETLIST,
    OP_CLOSURE,
    OP_VARARG,
    OP_EXTRAARG,
};

const OpCodeAction = *const fn (i: Instruction, vm: *LuaVM) LuaError!void;

const OpCodeStruct = struct {
    test_flag: byte, // operator is a test (next instruction must be a jump)
    set_a_flag: byte, // instruction set register A
    arg_b_mode: OpArgMask, // B arg mode
    arg_c_mode: OpArgMask, // C arg mode
    op_mode: OpMode, // op mode
    name: string,
    action: ?OpCodeAction,
};

fn opcode(t: byte, a: byte, b: OpArgMask, c: OpArgMask, mode: OpMode, name: string, action: ?OpCodeAction) OpCodeStruct {
    return OpCodeStruct{
        .test_flag = t,
        .set_a_flag = a,
        .arg_b_mode = b,
        .arg_c_mode = c,
        .op_mode = mode,
        .name = name,
        .action = action,
    };
}

pub const opcodes = [_]OpCodeStruct{
    //        T    A     B           C        mode       name
    opcode(0, 1, .OpArgR, .OpArgN, .IABC, "MOVE    ", move), // R(A) := R(B)
    opcode(0, 1, .OpArgK, .OpArgN, .IABx, "LOADK   ", loadK), // R(A) := Kst(Bx)
    opcode(0, 1, .OpArgN, .OpArgN, .IABx, "LOADKX  ", loadKx), // R(A) := Kst(extra arg)
    opcode(0, 1, .OpArgU, .OpArgU, .IABC, "LOADBOOL", loadBool), // R(A) := (bool)B; if (C) pc++
    opcode(0, 1, .OpArgU, .OpArgN, .IABC, "LOADNIL ", loadNil), // R(A), R(A+1), ..., R(A+B) := nil
    opcode(0, 1, .OpArgU, .OpArgN, .IABC, "GETUPVAL", getUpval), // R(A) := UpValue[B]
    opcode(0, 1, .OpArgU, .OpArgK, .IABC, "GETTABUP", getTabUp), // R(A) := UpValue[B][RK(C)]
    opcode(0, 1, .OpArgR, .OpArgK, .IABC, "GETTABLE", getTable), // R(A) := R(B)[RK(C)]
    opcode(0, 0, .OpArgK, .OpArgK, .IABC, "SETTABUP", setTabUp), // UpValue[A][RK(B)] := RK(C)
    opcode(0, 0, .OpArgU, .OpArgN, .IABC, "SETUPVAL", setUpval), // UpValue[B] := R(A)
    opcode(0, 0, .OpArgK, .OpArgK, .IABC, "SETTABLE", setTable), // R(A)[RK(B)] := RK(C)
    opcode(0, 1, .OpArgU, .OpArgU, .IABC, "NEWTABLE", newTable), // R(A) := {} (size = B,C)
    opcode(0, 1, .OpArgR, .OpArgK, .IABC, "SELF    ", self), // R(A+1) := R(B); R(A) := R(B)[RK(C)]
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "ADD     ", add), // R(A) := RK(B) + RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "SUB     ", sub), // R(A) := RK(B) - RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "MUL     ", mul), // R(A) := RK(B) * RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "MOD     ", mod), // R(A) := RK(B) % RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "POW     ", pow), // R(A) := RK(B) ^ RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "DIV     ", div), // R(A) := RK(B) / RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "IDIV    ", idiv), // R(A) := RK(B) // RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "BAND    ", band), // R(A) := RK(B) & RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "BOR     ", bor), // R(A) := RK(B) | RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "BXOR    ", bxor), // R(A) := RK(B) ~ RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "SHL     ", shl), // R(A) := RK(B) << RK(C)
    opcode(0, 1, .OpArgK, .OpArgK, .IABC, "SHR     ", shr), // R(A) := RK(B) >> RK(C)
    opcode(0, 1, .OpArgR, .OpArgN, .IABC, "UNM     ", unm), // R(A) := -R(B)
    opcode(0, 1, .OpArgR, .OpArgN, .IABC, "BNOT    ", bnot), // R(A) := ~R(B)
    opcode(0, 1, .OpArgR, .OpArgN, .IABC, "NOT     ", not), // R(A) := not R(B)
    opcode(0, 1, .OpArgR, .OpArgN, .IABC, "LEN     ", length), // R(A) := length of R(B)
    opcode(0, 1, .OpArgR, .OpArgR, .IABC, "CONCAT  ", concat), // R(A) := R(B).. ... ..R(C)
    opcode(0, 0, .OpArgR, .OpArgN, .IAsBx, "JMP     ", jmp), // pc+=sBx; if (A) close all upvalues >= R(A - 1)
    opcode(1, 0, .OpArgK, .OpArgK, .IABC, "EQ      ", eq), // if ((RK(B) == RK(C)) ~= A) then pc++
    opcode(1, 0, .OpArgK, .OpArgK, .IABC, "LT      ", lt), // if ((RK(B) <  RK(C)) ~= A) then pc++
    opcode(1, 0, .OpArgK, .OpArgK, .IABC, "LE      ", le), // if ((RK(B) <= RK(C)) ~= A) then pc++
    opcode(1, 0, .OpArgN, .OpArgU, .IABC, "TEST    ", @"test"), // if not (R(A) <=> C) then pc++
    opcode(1, 1, .OpArgR, .OpArgU, .IABC, "TESTSET ", testSet), // if (R(B) <=> C) then R(A) := R(B) else pc++
    opcode(0, 1, .OpArgU, .OpArgU, .IABC, "CALL    ", call), // R(A), ... ,R(A+C-2) := R(A)(R(A+1), ... ,R(A+B-1))
    opcode(0, 1, .OpArgU, .OpArgU, .IABC, "TAILCALL", tailCall), // return R(A)(R(A+1), ... ,R(A+B-1))
    opcode(0, 0, .OpArgU, .OpArgN, .IABC, "RETURN  ", _return), // return R(A), ... ,R(A+B-2)
    opcode(0, 1, .OpArgR, .OpArgN, .IAsBx, "FORLOOP ", forLoop), // R(A)+=R(A+2); if R(A) <?= R(A+1) then { pc+=sBx; R(A+3)=R(A) }
    opcode(0, 1, .OpArgR, .OpArgN, .IAsBx, "FORPREP ", forPrep), // R(A)-=R(A+2); pc+=sBx
    opcode(0, 0, .OpArgN, .OpArgU, .IABC, "TFORCALL", tForCall), // R(A+3), ... ,R(A+2+C) := R(A)(R(A+1), R(A+2));
    opcode(0, 1, .OpArgR, .OpArgN, .IAsBx, "TFORLOOP", tForLoop), // if R(A+1) ~= nil then { R(A)=R(A+1); pc += sBx }
    opcode(0, 0, .OpArgU, .OpArgU, .IABC, "SETLIST ", setList), // R(A)[(C-1)*FPF+i] := R(A+i), 1 <= i <= B
    opcode(0, 1, .OpArgU, .OpArgN, .IABx, "CLOSURE ", closure), // R(A) := closure(KPROTO[Bx])
    opcode(0, 1, .OpArgU, .OpArgN, .IABC, "VARARG  ", vararg), // R(A), R(A+1), ..., R(A+B-2) = vararg
    opcode(0, 0, .OpArgU, .OpArgU, .IAx, "EXTRAARG", null), // extra (larger) argument for previous opcode
};
