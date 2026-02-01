const LuaError = @import("../api/root.zig").Api.LuaError;
const LuaVM = @import("lua_vm.zig").LuaVM;
const OpArgMask = @import("opcodes.zig").OpArgMask;
const opcodes = @import("opcodes.zig").opcodes;
const OpMode = @import("opcodes.zig").OpMode;

const MAXARG_Bx = (1 << 18) - 1; // 262143
const MAXARG_sBx: i32 = @intCast(MAXARG_Bx >> 1); // 131071
const int = i32;
const byte = u8;
const string = []const u8;

// 31       22       13       5    0
//
//     +-------+^------+-^-----+-^-----
//     |b=9bits |c=9bits |a=8bits|op=6|
//     +-------+^------+-^-----+-^-----
//     |    bx=18bits    |a=8bits|op=6|
//     +-------+^------+-^-----+-^-----
//     |   sbx=18bits    |a=8bits|op=6|
//     +-------+^------+-^-----+-^-----
//     |    ax=26bits            |op=6|
//     +-------+^------+-^-----+-^-----
//
// 31      23      15       7      0

pub const Instruction = packed struct(u32) {
    op: u6,
    a: u8,
    u: packed union {
        cb: packed struct {
            c: u9,
            b: u9,
        },
        bx: u18,
    },

    pub fn of(u: u32) Instruction {
        const inst = @as(Instruction, @bitCast(u));
        return inst;
    }

    pub fn Opcode(self: Instruction) int {
        return @intCast(self.op);
    }

    pub fn ABC(self: Instruction) struct { int, int, int } {
        return .{
            @intCast(self.a),
            @intCast(self.u.cb.b),
            @intCast(self.u.cb.c),
        };
    }

    pub fn ABx(self: Instruction) struct { int, int } {
        return .{
            @intCast(self.a),
            @intCast(self.u.bx),
        };
    }

    pub fn AsBx(self: Instruction) struct { int, int } {
        const a, const bx = self.ABx();
        return .{
            a,
            bx - MAXARG_sBx,
        };
    }

    pub fn Ax(self: Instruction) int {
        const raw: u32 = @bitCast(self);
        return @intCast(raw >> 6);
    }

    pub fn opName(self: Instruction) string {
        const op_index: usize = @intCast(self.Opcode());
        return opcodes[op_index].name;
    }

    pub fn opMode(self: Instruction) OpMode {
        const op_index: usize = @intCast(self.Opcode());
        return opcodes[op_index].op_mode;
    }

    pub fn bMode(self: Instruction) OpArgMask {
        const op_index: usize = @intCast(self.Opcode());
        return opcodes[op_index].arg_b_mode;
    }

    pub fn cMode(self: Instruction) OpArgMask {
        const op_index: usize = @intCast(self.Opcode());
        return opcodes[op_index].arg_c_mode;
    }

    pub fn execute(self: Instruction, vm: *LuaVM) LuaError!void {
        const action = opcodes[@intCast(self.Opcode())].action;
        if (action) |f| {
            try f(self, vm);
        } else {
            @panic(self.opName());
        }
    }
};
