const std = @import("std");
const math = std.math;

const api = @import("api");
const LuaType = api.LuaType;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const api_arith = @import("state");
const operators = api_arith.operators;
const _arith = api_arith._arith;
const api_compare = @import("state");
const _eq = api_compare._eq;
const _lt = api_compare._lt;
const _le = api_compare._le;
const binchunkMod = @import("binchunk");
const Closure = binchunkMod.Closure;
const LuaTable = binchunkMod.LuaTable;
const LuaValueNSP = binchunkMod.LuaValueNSP;
const binchunk = binchunkMod.binchunk;
const LuaValue = LuaValueNSP.LuaValue;
const convertToBoolean = LuaValueNSP.convertToBoolean;
const convertToInteger = LuaValueNSP.convertToInteger;
const convertToFloat = LuaValueNSP.convertToFloat;
const typeof = binchunkMod.LuaValueNSP.typeOf;
const LuaStack = @import("lua_stack.zig").LuaStack;
const number = @import("number");

const Instruction = @import("instruction.zig").Instruction;
const OpCode = @import("opcodes.zig").OpCode;
const vm = @import("lua_vm.zig");
const LuaVM = vm.LuaVM;

const string = []const u8;
pub const LuaState = struct {
    stack: *LuaStack,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !LuaState {
        const stack = allocator.create(LuaStack) catch @panic("allocation failed");
        stack.* = try LuaStack.init(@intCast(20), allocator);
        return .{
            .stack = stack,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LuaState) void {
        self.stack.deinit();
        self.allocator.destroy(self.stack);
    }

    /// **************************  api_access  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_typename
    pub fn typeName(_: *LuaState, tp: LuaType) string {
        return switch (tp) {
            .lua_t_none => "no value",
            .lua_t_nil => "nil",
            .lua_t_boolean => "boolean",
            .lua_t_number => "number",
            .lua_t_string => "string",
            .lua_t_table => "table",
            .lua_t_function => "function",
            .lua_t_thread => "thread",
            else => "userdata",
        };
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_type
    pub fn Type(self: *LuaState, idx: i32) LuaType {
        if (self.stack.isValid(idx)) {
            const val = self.stack.get(idx);
            return typeof(val);
        }
        return .lua_t_none;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnone
    pub fn isNone(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_none;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnil
    pub fn isNil(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_nil;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnoneornil
    pub fn isNoneOrNil(self: *LuaState, idx: i32) bool {
        const t = self.Type(idx);
        return t == .lua_t_nil or t == .lua_t_none;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isboolean
    pub fn isBoolean(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_boolean;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_istable
    pub fn isTable(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_table;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isfunction
    pub fn isFunction(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_function;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isthread
    pub fn isThread(self: *LuaState, idx: i32) bool {
        return self.Type(idx) == .lua_t_thread;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isstring
    pub fn isString(self: *LuaState, idx: i32) bool {
        const t = self.Type(idx);
        return t == .lua_t_string or t == .lua_t_number;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnumber
    pub fn isNumber(self: *LuaState, idx: i32) bool {
        const val, const ok = self.toNumberX(idx);
        _ = val;
        return ok;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isinteger
    pub fn isInteger(self: *LuaState, idx: i32) bool {
        const val = self.stack.get(idx);
        return switch (val) {
            .int64 => |_| true,
            else => false,
        };
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_toboolean
    pub fn toBoolean(self: *LuaState, idx: i32) bool {
        const val = self.stack.get(idx);
        return convertToBoolean(val);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tointeger
    pub fn toInteger(self: *LuaState, idx: i32) i64 {
        const i, const ok = self.toIntegerX(idx);
        _ = ok;
        return i;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tointegerx
    pub fn toIntegerX(self: *LuaState, idx: i32) struct { i64, bool } {
        const val = self.stack.get(idx);
        return convertToInteger(val);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tonumber
    pub fn toNumber(self: *LuaState, idx: i32) f64 {
        const n, const ok = self.toNumberX(idx);
        _ = ok;
        return n;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tonumberx
    pub fn toNumberX(self: *LuaState, idx: i32) struct { f64, bool } {
        const val = self.stack.get(idx);
        return convertToFloat(val);
    }

    // [-0, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_tostring
    pub fn toString(self: *LuaState, idx: i32) string {
        const s, const ok = self.toStringX(idx);
        _ = ok;
        return s;
    }

    pub fn toStringX(self: *LuaState, idx: i32) struct { string, bool } {
        const val = self.stack.get(idx);
        switch (val) {
            .string => |x| return .{ x, true },
            .int64 => |x| {
                const s = std.fmt.allocPrint(self.allocator, "{d}", .{x}) catch @panic("allocation failed");
                self.stack.set(idx, .{ .string = s });
                return .{ s, true };
            },
            .float64 => |x| {
                const s = std.fmt.allocPrint(self.allocator, "{d}", .{x}) catch @panic("allocation failed");
                self.stack.set(idx, .{ .string = s });
                return .{ s, true };
            },
            else => return .{ "", false },
        }
    }

    /// **************************  api_stack  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettop
    pub fn getTop(self: *LuaState) usize {
        return self.stack.top;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_absindex
    pub fn absIndex(self: *LuaState, idx: i32) usize {
        return self.stack.absIndex(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_checkstack
    pub fn checkStack(self: *LuaState, n: i32) bool {
        self.stack.check(n);
        return true;
    }

    // [-n, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pop
    pub fn pop(self: *LuaState, n: i32) void {
        for (0..@as(usize, @intCast(n))) |_| {
            var val = self.stack.pop();
            val.deinit(self.allocator);
        }
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_copy
    pub fn copy(self: *LuaState, from_idx: i32, to_idx: i32) void {
        const val = self.stack.get(from_idx);
        self.stack.set(to_idx, val.clone(self.allocator));
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushvalue
    pub fn pushValue(self: *LuaState, idx: i32) void {
        const val = self.stack.get(idx);
        self.stack.push(val.clone(self.allocator));
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_replace
    pub fn replace(self: *LuaState, idx: i32) void {
        const val = self.stack.pop();
        self.stack.set(idx, val);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_insert
    pub fn insert(self: *LuaState, idx: i32) void {
        self.rotate(idx, 1);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_remove
    pub fn remove(self: *LuaState, idx: i32) void {
        self.rotate(idx, -1);
        _ = self.pop(1);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rotate
    pub fn rotate(self: *LuaState, idx: i32, n: i32) void {
        const t: i32 = @as(i32, @intCast(self.stack.top)) - 1; // end of stack segment being rotated
        const p: i32 = @intCast(self.stack.absIndex(idx) - 1); // start of segment
        const m = if (n > 0) t - n else p - n - 1; // end of prefix
        self.stack.reverse(p, m); // reverse the prefix with length 'n'
        self.stack.reverse(m + 1, t); // reverse the suffix
        self.stack.reverse(p, t); // reverse the entire segment
    }

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_settop
    pub fn setTop(self: *LuaState, idx: i32) void {
        const new_top = self.stack.absIndex(idx);
        if (new_top < 0) {
            @panic("stack underflow!");
        }

        const n = @as(i32, @intCast(self.stack.top)) - @as(i32, @intCast(new_top));
        if (n > 0) {
            var i: i32 = 0;
            while (i < n) : (i += 1) {
                var val = self.stack.pop();
                val.deinit(self.allocator);
            }
        } else if (n < 0) {
            var i: i32 = 0;
            while (i > n) : (i -= 1) {
                self.stack.push(.{ .nil = {} });
            }
        }
    }

    /// **************************  api_push  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnil
    pub fn pushNil(self: *LuaState) void {
        self.stack.push(.{ .nil = {} });
    }
    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushboolean
    pub fn pushBoolean(self: *LuaState, b: bool) void {
        self.stack.push(.{ .bool = b });
    }
    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushinteger
    pub fn pushInteger(self: *LuaState, n: i64) void {
        self.stack.push(.{ .int64 = n });
    }
    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnumber
    pub fn pushNumber(self: *LuaState, n: f64) void {
        self.stack.push(.{ .float64 = n });
    }
    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushstring
    pub fn pushString(self: *LuaState, s: string) void {
        const dupe = self.allocator.dupe(u8, s) catch @panic("allocation failed");
        self.stack.push(.{ .string = dupe });
    }

    /// **************************  api_arith  **************************

    // [-(2|1), +1, e]
    // http://www.lua.org/manual/5.3/manual.html#l
    pub fn arith(self: *LuaState, op: ArithOp) void {
        var b = self.stack.pop();
        defer b.deinit(self.allocator);
        var a = if (op != .lua_op_unm and op != .lua_op_bnot) self.stack.pop() else b;
        defer if (op != .lua_op_unm and op != .lua_op_bnot) a.deinit(self.allocator);

        const operator = operators[@intFromEnum(op)];
        const result = _arith(a, b, operator);
        if (result != .nil) {
            self.stack.push(result);
        } else {
            @panic("arithmetic error!");
        }
    }

    /// **************************  api_compare  **************************

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn compare(self: *LuaState, idx1: i32, idx2: i32, op: CompareOp) bool {
        if (!self.stack.isValid(idx1) or !self.stack.isValid(idx2)) {
            return false;
        }

        const a = self.stack.get(idx1);
        const b = self.stack.get(idx2);
        return switch (op) {
            .lua_op_eq => _eq(a, b),
            .lua_op_lt => _lt(a, b),
            .lua_op_le => _le(a, b),
            // else => @panic("invalid compare op!"),
        };
    }

    /// **************************  api_misc  **************************

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_len
    pub fn len(self: *LuaState, idx: i32) void {
        const val = self.stack.get(idx);
        switch (val) {
            .string => |s| {
                self.stack.push(.{ .int64 = @intCast(s.len) });
            },
            .lua_table => |t| {
                self.stack.push(.{ .int64 = @intCast(t.len()) });
            },
            else => @panic("length error!"),
        }
    }

    // [-n, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(self: *LuaState, n: i32) void {
        if (n == 0) {
            self.stack.push(.{ .string = "" });
        } else if (n >= 2) {
            for (1..@as(usize, @intCast(n))) |_| {
                if (self.isString(-1) and self.isString(-2)) {
                    const s2 = self.toString(-1);
                    const s1 = self.toString(-2);
                    var lv2 = self.stack.pop();
                    var lv1 = self.stack.pop();
                    const s = std.mem.concat(self.allocator, u8, &.{ s1, s2 }) catch @panic("allocation for concatenation failed");
                    lv2.deinit(self.allocator);
                    lv1.deinit(self.allocator);
                    self.stack.push(.{ .string = s });
                    continue;
                }

                @panic("concatenation error!");
            }
        }
        // n == 1, do nothing   w
    }

    /// **************************  api_vm  **************************

    // api_vm
    pub fn pc(self: *LuaState) i32 {
        return self.stack.pc;
    }

    pub fn addPC(self: *LuaState, n: i32) void {
        self.stack.pc += n;
    }

    pub fn fetch(self: *LuaState) u32 {
        const i = self.stack.closure.?.proto.code[@as(usize, @intCast(self.stack.pc))];
        self.stack.pc += 1;
        return i;
    }

    pub fn getConst(self: *LuaState, idx: i32) void {
        const c = self.stack.closure.?.proto.constants[@as(usize, @intCast(idx))];
        self.stack.push(c.clone(self.allocator));
    }

    pub fn getRK(self: *LuaState, rk: i32) void {
        if (rk > 0xFF) { // constant
            self.getConst(rk & 0xFF);
        } else { // register
            self.pushValue(rk + 1);
        }
    }

    pub fn registerCount(self: *LuaState) i32 {
        return @intCast(self.stack.closure.?.proto.max_stack_size);
    }

    pub fn loadVararg(self: *LuaState, n0: i32) void {
        const n: i32 = if (n0 < 0)
            if (self.stack.varargs) |varargs| @as(i32, @intCast(varargs.len)) else 0
        else
            n0;

        self.stack.check(n);
        if (self.stack.varargs) |varargs| {
            self.stack.pushN(varargs, n);
        } else {
            // No varargs available, push nils
            for (0..@as(usize, @intCast(n))) |_| {
                self.stack.push(.{ .nil = {} });
            }
        }
    }

    pub fn loadProto(self: *LuaState, idx: i32) void {
        const proto = self.stack.closure.?.proto.protos[@as(usize, @intCast(idx))];
        const closure = self.allocator.create(Closure) catch @panic("allocation failed");
        closure.* = Closure.init(proto);
        self.stack.push(.{ .closure = closure });
    }

    /// **************************  api_get  **************************

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_newtable
    pub fn newTable(self: *LuaState) void {
        self.createTable(0, 0);
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_createtable
    pub fn createTable(self: *LuaState, n_arr: i32, n_rec: i32) void {
        const t = self.allocator.create(LuaTable) catch @panic("allocation failed!");
        t.* = LuaTable.init(self.allocator, n_arr, n_rec);
        self.stack.push(.{ .lua_table = t });
    }

    // [-1, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettable
    pub fn getTable(self: *LuaState, idx: i32) LuaType {
        const t = self.stack.get(idx);
        var k = self.stack.pop();
        defer k.deinit(self.allocator);
        return self._getTable(t, k);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getfield
    pub fn getField(self: *LuaState, idx: i32, k: string) LuaType {
        const t = self.stack.get(idx);
        return self._getTable(t, .{ .string = k });
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_geti
    pub fn getI(self: *LuaState, idx: i32, i: i64) LuaType {
        const t = self.stack.get(idx);
        return self._getTable(t, .{ .int64 = i });
    }

    // push(t[k])
    fn _getTable(self: *LuaState, t: LuaValue, k: LuaValue) LuaType {
        if (std.meta.activeTag(t) == .lua_table) {
            const v = t.lua_table.get(k);
            self.stack.push(v.clone(self.allocator));
            return typeof(v);
        }

        @panic("not a table!");
    }

    /// **************************  api_set  **************************

    // [-2, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_settable
    pub fn setTable(self: *LuaState, idx: i32) void {
        const t = self.stack.get(idx);
        var v = self.stack.pop();
        defer v.deinit(self.allocator);
        var k = self.stack.pop();
        defer k.deinit(self.allocator);
        self._setTable(t, k, v);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setfield
    pub fn setField(self: *LuaState, idx: i32, k: string) void {
        const t = self.stack.get(idx);
        var v = self.stack.pop();
        defer v.deinit(self.allocator);
        var key = LuaValue{ .string = self.allocator.dupe(u8, k) catch @panic("allocation failed") };
        defer key.deinit(self.allocator);
        self._setTable(t, key, v);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_seti
    pub fn setI(self: *LuaState, idx: i32, i: i64) void {
        const t = self.stack.get(idx);
        var v = self.stack.pop();
        defer v.deinit(self.allocator);
        self._setTable(t, .{ .int64 = i }, v);
    }

    // t[k]=v
    fn _setTable(_: *LuaState, t: LuaValue, k: LuaValue, v: LuaValue) void {
        if (std.meta.activeTag(t) == .lua_table) {
            t.lua_table.put(k, v);
            return;
        }

        @panic("not a table!");
    }

    /// **************************  api_closure  **************************

    // api_closure
    pub fn setClosure(self: *LuaState, proto: *binchunkMod.Prototype) void {
        const closure = self.allocator.create(Closure) catch @panic("allocation failed");
        closure.* = Closure.init(proto);
        self.stack.closure = closure;
    }

    pub fn unsetClosure(self: *LuaState) void {
        if (self.stack.closure) |c| {
            c.*.release(self.allocator);
        }
    }

    /// **************************  api_call  **************************

    // api_call
    pub fn pushLuaStack(self: *LuaState, stack: *LuaStack) void {
        stack.prev = self.stack;
        self.stack = stack;
    }

    pub fn popLuaStack(self: *LuaState) void {
        var stack = self.stack;
        self.stack = stack.prev.?;
        stack.deinit();
        self.allocator.destroy(stack);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_load
    pub fn load(self: *LuaState, chunk: []u8, chunk_name: string, mode: string) i32 {
        _ = chunk_name;
        _ = mode;

        const proto = binchunk.undump(chunk);
        const c = self.allocator.create(Closure) catch @panic("allocation failed");
        c.* = Closure.init(proto);
        self.stack.push(.{ .closure = c });

        return 0;
    }

    // [-(nargs+1), +nresults, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_call
    pub fn call(self: *LuaState, n_args: i32, n_results: i32) void {
        const val = self.stack.get(-(n_args + 1));
        switch (val) {
            .closure => |c| {
                std.debug.print("call {s}<{d},{d}>\n", .{
                    c.proto.source,
                    c.proto.line_defined,
                    c.proto.last_line_defined,
                });
                self.callLuaClosure(n_args, n_results, c);
            },
            else => {
                @panic("not function!");
            },
        }
    }

    fn callLuaClosure(self: *LuaState, n_args: i32, n_results: i32, c: *Closure) void {
        const n_registers = @as(usize, @intCast(c.proto.max_stack_size));
        const n_params = @as(i32, @intCast(c.proto.num_params));
        const is_vararg = c.proto.is_vararg == 1;

        // create new lua stack
        const new_stack = self.allocator.create(LuaStack) catch @panic("allocation failed");
        new_stack.* = LuaStack.init(n_registers + 20, self.allocator) catch @panic("allocation failed");
        new_stack.closure = c;

        // pass args, pop func
        const func_and_args = self.stack.popN(n_args + 1);
        defer self.allocator.free(func_and_args);

        new_stack.pushN(func_and_args[1..], n_params);
        new_stack.top = n_registers;
        if (n_args > n_params and is_vararg) {
            new_stack.varargs = func_and_args[@as(usize, @intCast(n_params + 1))..];
        }

        // run closure
        self.pushLuaStack(new_stack);
        self.runLuaClosure();

        // get results before popping the stack
        var results: ?[]LuaValue = null;
        if (n_results != 0) {
            const stack_top = @as(i32, @intCast(new_stack.top));
            const registers = @as(i32, @intCast(n_registers));
            const results_count = if (stack_top > registers) stack_top - registers else 0;

            if (results_count > 0) {
                results = new_stack.popN(results_count);
            }
        }

        self.popLuaStack();

        // return results
        if (results) |res| {
            const n = if (n_results < 0) @as(i32, @intCast(res.len)) else n_results;
            self.stack.check(n);
            self.stack.pushN(res, n_results);
            if (n_results >= 0 and res.len > @as(usize, @intCast(n_results))) {
                for (res[@as(usize, @intCast(n_results))..]) |*v| {
                    v.deinit(self.allocator);
                }
            }
            self.allocator.free(res);
        }

        // Deinit the closure that was popped from the stack
        func_and_args[0].deinit(self.allocator);
    }

    fn runLuaClosure(self: *LuaState) void {
        var lua_vm_wrapper = LuaVM.of(self);
        const lua_vm = &lua_vm_wrapper;
        outer: while (true) {
            const inst = Instruction.of(lua_vm.fetch());
            inst.execute(lua_vm);
            if (inst.Opcode() == @intFromEnum(OpCode.OP_RETURN)) {
                break :outer;
            }
        }
    }
};
