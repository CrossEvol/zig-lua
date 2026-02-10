const std = @import("std");

const StatePkg = @import("../../state/root.zig");
const LuaValue = StatePkg.LuaValue;
const LuaValueContext = StatePkg.LuaValueContext;
const VmPkg = @import("../../vm/root.zig");
const intToFb = VmPkg.intToFb;
const fbToInt = VmPkg.fbToInt;
const OpCode = VmPkg.OpCode;
const MAXARG_sBx = VmPkg.MAXARG_sBx;
const AstPkg = @import("../ast/root.zig");
const FuncDefExp = AstPkg.FuncDefExp;
const CompilerError = @import("../compiler.zig").CompilerError;
const TokenPkg = @import("../lexer/root.zig");
const TokenKind = TokenPkg.TokenKind;
const TOKEN_OP_SUB = TokenPkg.TOKEN_OP_SUB;
const TOKEN_OP_BXOR = TokenPkg.TOKEN_OP_BXOR;
const TOKEN_OP_BNOT = TokenPkg.TOKEN_OP_BNOT;
const TOKEN_OP_UNM = TokenPkg.TOKEN_OP_UNM;

const string = []const u8;

const arithAndBitwiseBinops = std.enums.EnumMap(TokenKind, OpCode).init(.{
    .token_op_add = .OP_ADD,
    .token_op_minus = .OP_SUB, // TOKEN_OP_SUB
    .token_op_mul = .OP_MUL,
    .token_op_mod = .OP_MOD,
    .token_op_pow = .OP_POW,
    .token_op_div = .OP_DIV,
    .token_op_idiv = .OP_IDIV,
    .token_op_band = .OP_BAND,
    .token_op_bor = .OP_BOR,
    .token_op_wave = .OP_BXOR, // TOKEN_OP_BXOR
    .token_op_shl = .OP_SHL,
    .token_op_shr = .OP_SHR,
});

pub const UpvalInfo = struct {
    loc_var_slot: i32,
    upval_index: i32,
    index: i32,

    pub fn init(loc_var_slot: i32, upval_index: i32, index: i32) UpvalInfo {
        return .{
            .loc_var_slot = loc_var_slot,
            .upval_index = upval_index,
            .index = index,
        };
    }
};

pub const LocalVarInfo = struct {
    prev: ?*LocalVarInfo,
    name: string,
    scope_lv: i32,
    slot: i32,
    start_pc: i32,
    end_pc: i32,
    captured: bool,

    pub fn init(
        name: string,
        prev: ?*LocalVarInfo,
        scope_lv: i32,
        slot: i32,
        start_pc: i32,
        end_pc: i32,
        captured: bool,
    ) LocalVarInfo {
        return .{
            .name = name,
            .prev = prev,
            .scope_lv = scope_lv,
            .slot = slot,
            .start_pc = start_pc,
            .end_pc = end_pc,
            .captured = captured,
        };
    }
};

pub const FuncInfo = struct {
    allocator: std.mem.Allocator,
    parent: ?*FuncInfo,
    sub_funcs: std.ArrayList(*FuncInfo),
    used_regs: i32,
    max_regs: i32,
    scope_lv: i32,
    loc_vars: std.ArrayList(*LocalVarInfo),
    loc_names: std.StringHashMap(*LocalVarInfo),
    upvalues: std.StringHashMap(UpvalInfo),
    constants: std.HashMap(
        LuaValue,
        i32,
        LuaValueContext,
        std.hash_map.default_max_load_percentage,
    ),
    breaks: std.ArrayList(?std.ArrayList(i32)),
    insts: std.ArrayList(u32),
    line_nums: std.ArrayList(u32),
    line: i32,
    last_line: i32,
    num_params: i32,
    is_vararg: bool,

    pub fn init(allocator: std.mem.Allocator, parent: ?*FuncInfo, fd: *FuncDefExp) !*FuncInfo {
        const sub_funcs = try std.ArrayList(*FuncInfo).initCapacity(allocator, 8);
        const loc_vars = try std.ArrayList(*LocalVarInfo).initCapacity(allocator, 8);
        const loc_names = std.StringHashMap(*LocalVarInfo).init(allocator);
        const upvalues = std.StringHashMap(UpvalInfo).init(allocator);
        const constants = std.HashMap(
            LuaValue,
            i32,
            LuaValueContext,
            std.hash_map.default_max_load_percentage,
        ).init(allocator);
        const breaks = try std.ArrayList(?std.ArrayList(i32)).initCapacity(allocator, 8);
        const insts = try std.ArrayList(u32).initCapacity(allocator, 8);
        const line_nums = try std.ArrayList(u32).initCapacity(allocator, 8);

        const func_info = try allocator.create(FuncInfo);
        func_info.* = .{
            .allocator = allocator,
            .parent = parent,
            .sub_funcs = sub_funcs,
            .used_regs = 0,
            .max_regs = 0,
            .scope_lv = 0,
            .loc_vars = loc_vars,
            .loc_names = loc_names,
            .upvalues = upvalues,
            .constants = constants,
            .breaks = breaks,
            .insts = insts,
            .line_nums = line_nums,
            .line = @as(i32, @intCast(fd.line)),
            .last_line = @as(i32, @intCast(fd.last_line)),
            .num_params = @as(i32, @intCast(if (fd.par_list) |list| list.len else 0)),
            .is_vararg = fd.is_vararg,
        };
        return func_info;
    }

    pub fn deinit(self: *FuncInfo, allocator: std.mem.Allocator) void {
        self.sub_funcs.deinit(allocator);
        self.loc_vars.deinit(allocator);
        self.loc_names.deinit();
        self.upvalues.deinit();
        self.constants.deinit();
        self.breaks.deinit(allocator);
        self.insts.deinit(allocator);
        self.line_nums.deinit(allocator);
    }

    // constants

    pub fn indexOfConstant(self: *FuncInfo, k: LuaValue) !i32 {
        if (self.constants.get(k)) |idx| {
            return idx;
        }

        const idx = @as(i32, @intCast(self.constants.count()));
        try self.constants.put(k, idx);
        return idx;
    }

    // registers

    pub fn allocReg(self: *FuncInfo) !i32 {
        self.used_regs += 1;
        if (self.used_regs >= 255) {
            std.debug.print("function or expression needs too many registers", .{});
            return CompilerError.ICompilerError;
        }
        if (self.used_regs > self.max_regs) {
            self.max_regs = self.used_regs;
        }
        return self.used_regs - 1;
    }

    pub fn freeReg(self: *FuncInfo) !void {
        if (self.used_regs <= 0) {
            std.debug.print("usedRegs <= 0 !", .{});
            return CompilerError.ICompilerError;
        }
        self.used_regs -= 1;
    }

    pub fn allocRegs(self: *FuncInfo, n: i32) !i32 {
        if (n <= 0) {
            std.debug.print("n <= 0 !", .{});
            return CompilerError.ICompilerError;
        }
        for (0..@as(usize, @intCast(n))) |_| {
            _ = try self.allocReg();
        }
        return self.used_regs - n;
    }

    pub fn freeRegs(self: *FuncInfo, n: i32) !void {
        if (n < 0) {
            std.debug.print("n < 0 !", .{});
            return CompilerError.ICompilerError;
        }
        for (0..@as(usize, @intCast(n))) |_| {
            try self.freeReg();
        }
    }

    // lexical scope

    pub fn enterScope(self: *FuncInfo, breakable: bool) !void {
        self.scope_lv += 1;
        if (breakable) {
            try self.breaks.append(self.allocator, try std.ArrayList(i32).initCapacity(self.allocator, 8));
        } else {
            try self.breaks.append(self.allocator, null);
        }
    }

    pub fn exitScope(self: *FuncInfo, end_pc: i32) !void {
        const pending_break_jmps = self.breaks.pop();

        const a = try self.getJmpArgA();
        if (pending_break_jmps) |break_jmps| {
            if (break_jmps) |jmps| {
                for (jmps.items) |pc| {
                    const sBx = self.PC() - pc;
                    const i = ((sBx + MAXARG_sBx) << 14) | (a << 6) | @as(i32, @intFromEnum(OpCode.OP_JMP));
                    self.insts.items[@as(usize, @intCast(pc))] = @as(u32, @intCast(i));
                }
            }
        }

        self.scope_lv -= 1;
        var iter = self.loc_names.valueIterator();
        while (iter.next()) |loc_var| {
            if (loc_var.*.scope_lv > self.scope_lv) { // out of scope
                loc_var.*.end_pc = end_pc;
                try self.removeLocVar(loc_var.*);
            }
        }
    }

    pub fn removeLocVar(self: *FuncInfo, loc_var: *LocalVarInfo) !void {
        try self.freeReg();
        if (loc_var.prev == null) {
            _ = self.loc_names.remove(loc_var.name);
        } else if (loc_var.prev.?.scope_lv == loc_var.*.scope_lv) {
            try self.removeLocVar(loc_var.*.prev.?);
        } else {
            try self.loc_names.put(loc_var.name, loc_var.prev.?);
        }
    }

    pub fn addLocVar(self: *FuncInfo, name: string, star_pc: i32) !i32 {
        const new_var = try self.allocator.create(LocalVarInfo);
        new_var.* = LocalVarInfo.init(
            name,
            self.loc_names.get(name),
            self.scope_lv,
            try self.allocReg(),
            star_pc,
            0,
            false,
        );

        try self.loc_vars.append(self.allocator, new_var);
        try self.loc_names.put(name, new_var);
        return new_var.slot;
    }
    pub fn slotOfLocVar(self: *FuncInfo, name: string) i32 {
        if (self.loc_names.get(name)) |loc_var| {
            return loc_var.*.slot;
        }
        return -1;
    }

    pub fn addBreakJmp(self: *FuncInfo, pc: i32) !void {
        var i = self.scope_lv;
        while (i >= 0) : (i -= 1) {
            const idx = @as(usize, @intCast(i));
            if (self.breaks.items[idx]) |_| { // breakable
                try self.breaks.items[idx].?.append(self.allocator, pc);
                return;
            }
        }

        std.debug.print("<break> at line ? not inside a loop!", .{});
        return CompilerError.ICompilerError;
    }

    // upvalues

    pub fn indexOfUpval(self: *FuncInfo, name: string) !i32 {
        if (self.upvalues.get(name)) |upval| {
            return upval.index;
        }
        if (self.parent) |parent| {
            if (parent.loc_names.get(name)) |loc_var| {
                const idx = @as(i32, @intCast(self.upvalues.count()));
                try self.upvalues.put(name, UpvalInfo.init(loc_var.slot, -1, idx));
                loc_var.captured = true;
                return idx;
            }
            const uv_idx = try parent.indexOfUpval(name);
            if (uv_idx >= 0) {
                const idx = @as(i32, @intCast(self.upvalues.count()));
                try self.upvalues.put(name, UpvalInfo.init(-1, uv_idx, idx));
                return idx;
            }
        }
        return -1;
    }

    pub fn closeOpenUpvals(self: *FuncInfo, line: i32) !void {
        const a = try self.getJmpArgA();
        if (a > 0) {
            _ = try self.emitJmp(line, a, 0);
        }
    }

    pub fn getJmpArgA(self: *FuncInfo) !i32 {
        var has_captured_loc_vars = false;
        var min_slot_of_loc_vars = self.max_regs;
        var iter = self.loc_names.valueIterator();
        while (iter.next()) |loc_var| {
            if (loc_var.*.scope_lv == self.scope_lv) {
                var v: ?*LocalVarInfo = loc_var.*;
                while (v != null and v.?.scope_lv == self.scope_lv) : (v = v.?.prev) {
                    if (v.?.captured) {
                        has_captured_loc_vars = true;
                    }
                    if (v.?.slot < min_slot_of_loc_vars and v.?.name[0] != '(') {
                        min_slot_of_loc_vars = v.?.slot;
                    }
                }
            }
        }

        if (has_captured_loc_vars) {
            return min_slot_of_loc_vars + 1;
        } else {
            return 0;
        }
    }

    // code

    pub fn PC(self: *FuncInfo) i32 {
        return @intCast(self.insts.items.len - 1);
    }

    pub fn fixSbx(self: *FuncInfo, pc: i32, sBx: i32) void {
        var i = self.insts.items[@as(usize, @intCast(pc))];
        i = (i << 18) >> 18; // clear sBx
        i = i | (@as(u32, @intCast(sBx + MAXARG_sBx)) << 14); // reset sBx
        self.insts.items[@as(usize, @intCast(pc))] = i;
    }

    pub fn fixEndPC(self: *FuncInfo, name: string, delta: i32) void {
        var i = self.loc_vars.items.len - 1;
        while (i >= 0) : (i -= 1) {
            const loc_var = self.loc_vars.items[i];
            if (std.mem.eql(u8, loc_var.name, name)) {
                loc_var.end_pc += delta;
                return;
            }
        }
    }

    pub fn emitABC(self: *FuncInfo, line: i32, opcode: OpCode, a: i32, b: i32, c: i32) !void {
        const i = (b << 23) | (c << 14) | (a << 6) | @as(i32, @intFromEnum(opcode));
        try self.insts.append(self.allocator, @as(u32, @bitCast(i)));
        try self.line_nums.append(self.allocator, @as(u32, @intCast(line)));
    }

    pub fn emitABx(self: *FuncInfo, line: i32, opcode: OpCode, a: i32, bx: i32) !void {
        const i = (bx << 14) | (a << 6) | @as(i32, @intFromEnum(opcode));
        try self.insts.append(self.allocator, @as(u32, @bitCast(i)));
        try self.line_nums.append(self.allocator, @as(u32, @intCast(line)));
    }
    pub fn emitAsBx(self: *FuncInfo, line: i32, opcode: OpCode, a: i32, b: i32) !void {
        const i = (b + MAXARG_sBx << 14) | (a << 6) | @as(i32, @intFromEnum(opcode));
        try self.insts.append(self.allocator, @as(u32, @bitCast(i)));
        try self.line_nums.append(self.allocator, @as(u32, @intCast(line)));
    }

    pub fn emitAx(self: *FuncInfo, line: i32, opcode: OpCode, ax: i32) !void {
        const i = (ax << 6) | @as(i32, @intFromEnum(opcode));
        try self.insts.append(self.allocator, @as(u32, @bitCast(i)));
        try self.line_nums.append(self.allocator, @as(u32, @intCast(line)));
    }

    // r[a] = r[b]
    pub fn emitMove(self: *FuncInfo, line: i32, a: i32, b: i32) !void {
        try self.emitABC(line, .OP_MOVE, a, b, 0);
    }

    // r[a], r[a+1], ..., r[a+b] = nil
    pub fn emitLoadNil(self: *FuncInfo, line: i32, a: i32, n: i32) !void {
        try self.emitABC(line, .OP_LOADNIL, a, n - 1, 0);
    }

    // r[a] = (bool)b; if (c) pc++
    pub fn emitLoadBool(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_LOADBOOL, a, b, c);
    }

    // r[a] = kst[bx]
    pub fn emitLoadK(self: *FuncInfo, line: i32, a: i32, k: LuaValue) !void {
        const idx = try self.indexOfConstant(k);
        if (idx < (1 << 18)) {
            try self.emitABx(line, .OP_LOADK, a, idx);
        } else {
            try self.emitABx(line, .OP_LOADKX, a, 0);
            try self.emitAx(line, .OP_EXTRAARG, idx);
        }
    }

    // r[a], r[a+1], ..., r[a+b-2] = vararg
    pub fn emitVararg(self: *FuncInfo, line: i32, a: i32, n: i32) !void {
        try self.emitABC(line, .OP_VARARG, a, n + 1, 0);
    }

    // r[a] = emitClosure(proto[bx])
    pub fn emitClosure(self: *FuncInfo, line: i32, a: i32, bx: i32) !void {
        try self.emitABx(line, .OP_CLOSURE, a, bx);
    }

    // r[a] = {}
    pub fn emitNewTable(self: *FuncInfo, line: i32, a: i32, nArr: i32, nRec: i32) !void {
        try self.emitABC(line, .OP_NEWTABLE, a, intToFb(nArr), intToFb(nRec));
    }

    // r[a][(c-1)*FPF+i] := r[a+i], 1 <= i <= b
    pub fn emitSetList(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_SETLIST, a, b, c);
    }

    // r[a] := r[b][rk(c)]
    pub fn emitGetTable(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_GETTABLE, a, b, c);
    }

    // r[a][rk(b)] = rk(c)
    pub fn emitSetTable(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_SETTABLE, a, b, c);
    }

    // r[a] = upval[b]
    pub fn emitGetUpval(self: *FuncInfo, line: i32, a: i32, b: i32) !void {
        try self.emitABC(line, .OP_GETUPVAL, a, b, 0);
    }

    // upval[b] = r[a]
    pub fn emitSetUpval(self: *FuncInfo, line: i32, a: i32, b: i32) !void {
        try self.emitABC(line, .OP_SETUPVAL, a, b, 0);
    }

    // r[a] = upval[b][rk(c)]
    pub fn emitGetTabUp(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_GETTABUP, a, b, c);
    }

    // upval[a][rk(b)] = rk(c)
    pub fn emitSetTabUp(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_SETTABUP, a, b, c);
    }

    // r[a], ..., r[a+c-2] = r[a](r[a+1], ..., r[a+b-1])
    pub fn emitCall(self: *FuncInfo, line: i32, a: i32, nArgs: i32, nRet: i32) !void {
        try self.emitABC(line, .OP_CALL, a, nArgs + 1, nRet + 1);
    }

    // return r[a](r[a+1], ... ,r[a+b-1])
    pub fn emitTailCall(self: *FuncInfo, line: i32, a: i32, nArgs: i32) !void {
        try self.emitABC(line, .OP_TAILCALL, a, nArgs + 1, 0);
    }

    // return r[a], ... ,r[a+b-2]
    pub fn emitReturn(self: *FuncInfo, line: i32, a: i32, n: i32) !void {
        try self.emitABC(line, .OP_RETURN, a, n + 1, 0);
    }

    // r[a+1] := r[b]; r[a] := r[b][rk(c)]
    pub fn emitSelf(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_SELF, a, b, c);
    }

    // pc+=sBx; if (a) close all upvalues >= r[a - 1]
    pub fn emitJmp(self: *FuncInfo, line: i32, a: i32, sBx: i32) !i32 {
        try self.emitAsBx(line, .OP_JMP, a, sBx);
        return @intCast(self.insts.items.len - 1);
    }

    // if not (r[a] <=> c) then pc++
    pub fn emitTest(self: *FuncInfo, line: i32, a: i32, c: i32) !void {
        try self.emitABC(line, .OP_TEST, a, 0, c);
    }

    // if (r[b] <=> c) then r[a] := r[b] else pc++
    pub fn emitTestSet(self: *FuncInfo, line: i32, a: i32, b: i32, c: i32) !void {
        try self.emitABC(line, .OP_TESTSET, a, b, c);
    }

    pub fn emitForPrep(self: *FuncInfo, line: i32, a: i32, sBx: i32) !i32 {
        try self.emitAsBx(line, .OP_FORPREP, a, sBx);
        return @intCast(self.insts.items.len - 1);
    }

    pub fn emitForLoop(self: *FuncInfo, line: i32, a: i32, sBx: i32) !i32 {
        try self.emitAsBx(line, .OP_FORLOOP, a, sBx);
        return @intCast(self.insts.items.len - 1);
    }

    pub fn emitTForCall(self: *FuncInfo, line: i32, a: i32, c: i32) !void {
        try self.emitABC(line, .OP_TFORCALL, a, 0, c);
    }

    pub fn emitTForLoop(self: *FuncInfo, line: i32, a: i32, sBx: i32) !void {
        try self.emitAsBx(line, .OP_TFORLOOP, a, sBx);
    }

    // r[a] = op r[b]
    pub fn emitUnaryOp(self: *FuncInfo, line: i32, op: TokenKind, a: i32, b: i32) !void {
        switch (op) {
            .token_op_not => try self.emitABC(line, .OP_NOT, a, b, 0),
            TOKEN_OP_BNOT => try self.emitABC(line, .OP_BNOT, a, b, 0),
            .token_op_len => try self.emitABC(line, .OP_LEN, a, b, 0),
            TOKEN_OP_UNM => try self.emitABC(line, .OP_UNM, a, b, 0),
            else => {},
        }
    }

    // r[a] = rk[b] op rk[c]
    // arith & bitwise & relational
    pub fn emitBinaryOp(self: *FuncInfo, line: i32, op: TokenKind, a: i32, b: i32, c: i32) !void {
        if (arithAndBitwiseBinops.get(op)) |opcode| {
            try self.emitABC(line, opcode, a, b, c);
        } else {
            switch (op) {
                .token_op_eq => try self.emitABC(line, .OP_EQ, 1, b, c),
                .token_op_ne => try self.emitABC(line, .OP_EQ, 0, b, c),
                .token_op_lt => try self.emitABC(line, .OP_LT, 1, b, c),
                .token_op_gt => try self.emitABC(line, .OP_LT, 1, c, b),
                .token_op_le => try self.emitABC(line, .OP_LE, 1, b, c),
                .token_op_ge => try self.emitABC(line, .OP_LE, 1, c, b),
                else => {},
            }
            _ = try self.emitJmp(line, 0, 1);
            try self.emitLoadBool(line, a, 0, 1);
            try self.emitLoadBool(line, a, 1, 0);
        }
    }
};
