const std = @import("std");
const math = std.math;

const api = @import("api");
const LuaType = api.LuaType;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const binchunk = @import("binchunk");
const LuaTable = @import("api").LuaTable;
const LuaValueNSP = @import("api").LuaValueNSP;
const LuaValue = LuaValueNSP.LuaValue;
const convertToBoolean = LuaValueNSP.convertToBoolean;
const convertToInteger = LuaValueNSP.convertToInteger;
const convertToFloat = LuaValueNSP.convertToFloat;
const number = @import("number");
const typeof = @import("api").LuaValueNSP.typeOf;

const api_arith = @import("api_arith.zig");
const operators = api_arith.operators;
const _arith = api_arith._arith;
const api_compare = @import("api_compare.zig");
const _eq = api_compare._eq;
const _lt = api_compare._lt;
const _le = api_compare._le;
const LuaStack = @import("lua_stack.zig").LuaStack;

const string = []const u8;
pub const LuaState = struct {
    stack: LuaStack,
    proto: ?*binchunk.Prototype,
    _pc: i32,
    allocator: std.mem.Allocator,

    pub fn init0(allocator: std.mem.Allocator) !LuaState {
        const stack = try LuaStack.init(@intCast(20), allocator);
        return .{
            .stack = stack,
            .allocator = allocator,
            .proto = null,
            ._pc = 0,
        };
    }

    pub fn init(allocator: std.mem.Allocator, stack_size: i32, proto: *binchunk.Prototype) !LuaState {
        const stack = try LuaStack.init(@intCast(stack_size), allocator);
        return .{
            .stack = stack,
            .allocator = allocator,
            .proto = proto,
            ._pc = 0,
        };
    }

    pub fn deinit(self: *LuaState) void {
        self.stack.deinit();
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
    pub fn toInteger(self: *LuaState, idx: i32) bool {
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
    pub fn pop(self: *LuaState, n: usize) void {
        for (0..n) |_| {
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
        return self._pc;
    }

    pub fn addPC(self: *LuaState, n: i32) void {
        self._pc += n;
    }

    pub fn fetch(self: *LuaState) u32 {
        const i = self.proto.?.code[@as(usize, @intCast(self.pc()))];
        self._pc += 1;
        return i;
    }

    pub fn getConst(self: *LuaState, idx: i32) void {
        const c = self.proto.?.constants[@as(usize, @intCast(idx))];
        self.stack.push(c.clone(self.allocator));
    }

    pub fn getRK(self: *LuaState, rk: i32) void {
        if (rk > 0xFF) { // constant
            self.getConst(rk & 0xFF);
        } else { // register
            self.pushValue(rk + 1);
        }
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
};
