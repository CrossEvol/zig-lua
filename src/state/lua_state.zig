const std = @import("std");
const math = std.math;

const api = @import("../api/root.zig").Api;
const ThreadStatus = api.ThreadStatus;
const LuaType = api.LuaType;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LUA_RIDX_GLOBALS = api.LUA_RIDX_GLOBALS;
const LUA_MINSTACK = api.LUA_MINSTACK;
const LuaError = @import("../api/root.zig").Api.LuaError;
const binchunk = @import("../binchunk/root.zig").binchunk;
const number = @import("../number/root.zig").number;
const state = @import("../state/root.zig").state;
const operators = state.operators;
const _arith = state._arith;
const _eq = state._eq;
const _lt = state._lt;
const _le = state._le;
const vm = @import("../vm/root.zig").vm;
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;
const Instruction = vm.Instruction;
const callMetamethod = @import("lua_value.zig").callMetamethod;
const Closure = @import("closure.zig").Closure;
const convertToBoolean = @import("lua_value.zig").convertToBoolean;
const convertToFloat = @import("lua_value.zig").convertToFloat;
const convertToInteger = @import("lua_value.zig").convertToInteger;
const GC = @import("gc.zig").GC;
const getMetafield = @import("lua_value.zig").getMetafield;
const getMetatable = @import("lua_value.zig").getMetatable;
const LuaStack = @import("lua_stack.zig").LuaStack;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;
const setMetatable = @import("lua_value.zig").setMetatable;
const typeof = @import("lua_value.zig").typeOf;
const UpValue = @import("closure.zig").UpValue;
const ZigFunction = @import("closure.zig").ZigFunction;

const string = []const u8;

pub const LuaState = struct {
    registry: *LuaTable, // borrow from gc
    stack: ?*LuaStack, // own by self? TODO:

    // memory management
    allocator: std.mem.Allocator,
    gc: *GC,

    pub fn init(allocator: std.mem.Allocator, gc: *GC) !LuaState {
        var lv_table = gc.createLVTable(0, 0);
        const registry = lv_table.asTable();
        const env = gc.createLVTable(0, 0);
        registry.put(.{ .int64 = LUA_RIDX_GLOBALS }, env);

        var ls: LuaState = .{
            .registry = registry,
            .stack = null,
            .allocator = allocator,
            .gc = gc,
        };

        const stack = allocator.create(LuaStack) catch @panic("allocation failed");
        stack.* = try LuaStack.init(allocator, @intCast(LUA_MINSTACK), &ls);
        ls.pushLuaStack(stack);

        return ls;
    }

    pub fn deinit(self: *LuaState) void {
        if (self.stack) |s| {
            s.deinit();
            self.allocator.destroy(s);
        }
    }

    pub fn mark(self: *const LuaState) void {
        self.registry.asObj().markObject();
        if (self.stack) |stack| {
            stack.mark();
        }
    }

    pub fn pushLuaStack(self: *LuaState, stack: *LuaStack) void {
        stack.prev = self.stack;
        self.stack = stack;
    }

    pub fn popLuaStack(self: *LuaState) void {
        const lua_stack = self.stack;

        if (lua_stack) |stack| {
            self.stack = stack.prev.?;
            stack.prev = null;
            stack.deinit(); // TODO: LuaStack不由 GC 管理
            self.allocator.destroy(stack);
        }
    }

    /// **************************  api_access  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawlen
    pub fn rawLen(self: *LuaState, idx: i32) LuaError!usize {
        if (self.stack) |stack| {
            const val = stack.get(idx);
            return switch (val) {
                .obj => |obj| switch (obj.kind) {
                    .string => |_| val.asStr().len(),
                    .lua_table => |_| val.asTable().len(),
                    else => 0,
                },
                else => 0,
            };
        }

        // @panic("rawLen failed");
        self.pushString("rawLen failed");
        return LuaError.Panic;
    }

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
        if (self.stack.?.isValid(idx)) {
            const val = self.stack.?.get(idx);
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
        const val = self.stack.?.get(idx);
        return switch (val) {
            .int64 => |_| true,
            else => false,
        };
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_iscfunction
    pub fn isZigFunction(self: *LuaState, idx: i32) bool {
        const val = self.stack.?.get(idx);
        switch (val) {
            .obj => |obj| switch (obj.kind) {
                .closure => |_| val.asClosure().zig_func != null,
                else => false,
            },
            else => false,
        }
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_toboolean
    pub fn toBoolean(self: *LuaState, idx: i32) bool {
        const val = self.stack.?.get(idx);
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
        const val = self.stack.?.get(idx);
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
        const val = self.stack.?.get(idx);
        return convertToFloat(val);
    }

    // [-0, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_tostring
    pub fn toString(self: *LuaState, idx: i32) LuaError!*LuaString {
        const s, const ok = try self.toStringX(idx);
        _ = ok;
        return s;
    }

    pub fn toStringX(self: *LuaState, idx: i32) LuaError!struct { *LuaString, bool } {
        const val = self.stack.?.get(idx);
        switch (val) {
            .int64 => |x| {
                const s = std.fmt.allocPrint(self.allocator, "{d}", .{x}) catch @panic("allocation failed");
                defer self.allocator.free(s);
                var lv_str = self.gc.createLVString(s);
                try self.stack.?.set(idx, lv_str);
                return .{ lv_str.asStr(), true };
            },
            .float64 => |x| {
                const s = std.fmt.allocPrint(self.allocator, "{d}", .{x}) catch @panic("allocation failed");
                defer self.allocator.free(s);
                var lv_str = self.gc.createLVString(s);
                try self.stack.?.set(idx, lv_str);
                return .{ lv_str.asStr(), true };
            },
            .obj => |obj| switch (obj.kind) {
                .string => |_| return .{ val.asStr(), true },
                else => {
                    var lv_str = self.gc.createLVString("");
                    return .{ lv_str.asStr(), false };
                },
            },
            else => {
                var lv_str = self.gc.createLVString("");
                return .{ lv_str.asStr(), false };
            },
        }
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tocfunction
    pub fn toZigFunction(self: *LuaState, idx: i32) ?ZigFunction {
        const val = self.stack.?.get(idx);
        switch (val) {
            .obj => |obj| switch (obj.kind) {
                .closure => |_| val.asClosure().zig_func,
                else => null,
            },
            else => null,
        }
    }

    /// **************************  api_stack  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettop
    pub fn getTop(self: *LuaState) usize {
        return self.stack.?.top;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_absindex
    pub fn absIndex(self: *LuaState, idx: i32) usize {
        return self.stack.?.absIndex(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_checkstack
    pub fn checkStack(self: *LuaState, n: i32) bool {
        self.stack.?.check(n);
        return true; // never fails
    }

    // [-n, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pop
    pub fn pop(self: *LuaState, n: i32) LuaError!void {
        for (0..@as(usize, @intCast(n))) |_| {
            _ = try self.stack.?.pop();
        }
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_copy
    pub fn copy(self: *LuaState, from_idx: i32, to_idx: i32) LuaError!void {
        const val = self.stack.?.get(from_idx);
        try self.stack.?.set(to_idx, val);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushvalue
    pub fn pushValue(self: *LuaState, idx: i32) LuaError!void {
        const val = self.stack.?.get(idx);
        try self.stack.?.push(val);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_replace
    pub fn replace(self: *LuaState, idx: i32) LuaError!void {
        const val = try self.stack.?.pop();
        try self.stack.?.set(idx, val);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_insert
    pub fn insert(self: *LuaState, idx: i32) void {
        self.rotate(idx, 1);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_remove
    pub fn remove(self: *LuaState, idx: i32) LuaError!void {
        self.rotate(idx, -1);
        _ = try self.pop(1);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rotate
    pub fn rotate(self: *LuaState, idx: i32, n: i32) void {
        const t: i32 = @as(i32, @intCast(self.stack.?.top)) - 1; // end of stack segment being rotated
        const p: i32 = @intCast(self.stack.?.absIndex(idx) - 1); // start of segment
        const m = if (n > 0) t - n else p - n - 1; // end of prefix
        self.stack.?.reverse(p, m); // reverse the prefix with length 'n'
        self.stack.?.reverse(m + 1, t); // reverse the suffix
        self.stack.?.reverse(p, t); // reverse the entire segment
    }

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_settop
    pub fn setTop(self: *LuaState, idx: i32) LuaError!void {
        const new_top = self.stack.?.absIndex(idx);
        if (new_top < 0) {
            // @panic("stack underflow!");
            self.pushString("stack underflow!");
            return LuaError.Panic;
        }

        const n = @as(i32, @intCast(self.stack.?.top)) - @as(i32, @intCast(new_top));
        if (n > 0) {
            var i: i32 = 0;
            while (i < n) : (i += 1) {
                _ = try self.stack.?.pop();
            }
        } else if (n < 0) {
            var i: i32 = 0;
            while (i > n) : (i -= 1) {
                try self.stack.?.push(LuaValue.LUA_NIL);
            }
        }
    }

    /// **************************  api_push  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnil
    pub fn pushNil(self: *LuaState) LuaError!void {
        try self.stack.?.push(LuaValue.LUA_NIL);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushboolean
    pub fn pushBoolean(self: *LuaState, b: bool) LuaError!void {
        try self.stack.?.push(.{ .bool = b });
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushinteger
    pub fn pushInteger(self: *LuaState, n: i64) LuaError!void {
        try self.stack.?.push(.{ .int64 = n });
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnumber
    pub fn pushNumber(self: *LuaState, n: f64) LuaError!void {
        try self.stack.?.push(.{ .float64 = n });
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushstring
    pub fn pushString(self: *LuaState, s: string) LuaError!void {
        const lv_str = self.gc.createLVString(s);
        try self.stack.?.push(lv_str);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushcfunction
    pub fn pushZigFunction(self: *LuaState, f: ZigFunction) LuaError!void {
        const lv_closure = self.gc.createLVZigClosure(f, 0);
        try self.stack.?.push(lv_closure);
    }

    // [-n, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushcclosure
    pub fn pushZigClosure(self: *LuaState, f: ZigFunction, n: i32) LuaError!void {
        const lv_closure = self.gc.createLVZigClosure(f, n);
        const closure = lv_closure.asClosure();
        var i = n;
        while (i > 0) : (i -= 1) {
            const val = try self.stack.?.pop();
            const val_ref = &val;
            closure.upvals[@as(usize, @intCast(i - 1))] = self.gc.createClosedObjUpValue(val_ref);
        }
        try self.stack.?.push(lv_closure);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushglobaltable
    pub fn pushGlobalTable(self: *LuaState) LuaError!void {
        const global = self.registry.get(.{ .int64 = LUA_RIDX_GLOBALS });
        try self.stack.?.push(global);
    }

    /// **************************  api_arith  **************************

    // [-(2|1), +1, e]
    // http://www.lua.org/manual/5.3/manual.html#l
    pub fn arith(self: *LuaState, op: ArithOp) LuaError!void {
        const b = try self.stack.?.pop();
        const a = if (op != .lua_op_unm and op != .lua_op_bnot) try self.stack.?.pop() else b;

        const operator = operators[@intFromEnum(op)];
        var result = _arith(a, b, operator);
        if (result != .nil) {
            try self.stack.?.push(result);
            return;
        }

        const mm = operator.metamethod;
        result, const ok = try callMetamethod(self.allocator, a, b, mm, self);
        if (ok) {
            try self.stack.?.push(result);
            return;
        }

        // @panic("arithmetic error!");
        try self.pushString("arithmetic error!");
        return LuaError.Panic;
    }

    /// **************************  api_compare  **************************

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn rawEqual(self: *LuaState, idx1: i32, idx2: i32) LuaError!bool {
        if (!self.stack.?.isValid(idx1) or !self.stack.?.isValid(idx2)) {
            return false;
        }

        const a = self.stack.?.get(idx1);
        const b = self.stack.?.get(idx2);
        return try _eq(self.allocator, a, b, null);
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn compare(self: *LuaState, idx1: i32, idx2: i32, op: CompareOp) LuaError!bool {
        if (!self.stack.?.isValid(idx1) or !self.stack.?.isValid(idx2)) {
            return false;
        }

        const a = self.stack.?.get(idx1);
        const b = self.stack.?.get(idx2);

        return switch (op) {
            .lua_op_eq => try _eq(self.allocator, a, b, self),
            .lua_op_lt => try _lt(self.allocator, a, b, self),
            .lua_op_le => try _le(self.allocator, a, b, self),
        };
    }

    /// **************************  api_misc  **************************

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_len
    pub fn len(self: *LuaState, idx: i32) LuaError!void {
        const val = self.stack.?.get(idx);

        if (val.isStr()) {
            const val_str = val.asStr();
            try self.stack.?.push(.{ .int64 = @intCast(val_str.len()) });
        } else {
            const result, const ok = try callMetamethod(self.allocator, val, val, "__len", self);
            if (ok) {
                try self.stack.?.push(result);
            } else if (val.isTable()) {
                const t = val.asTable();
                try self.stack.?.push(.{ .int64 = @intCast(t.len()) });
            } else {
                // @panic("length error!");
                try self.pushString("length error!");
                return LuaError.Panic;
            }
        }
    }

    // [-n, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(self: *LuaState, n: i32) LuaError!void {
        if (n == 0) {
            const lv_str = self.gc.createLVString("");
            try self.stack.?.push(lv_str);
        } else if (n >= 2) {
            for (1..@as(usize, @intCast(n))) |_| {
                if (self.isString(-1) and self.isString(-2)) {
                    const s2 = try self.toString(-1);
                    const s1 = try self.toString(-2);
                    _ = try self.stack.?.pop();
                    _ = try self.stack.?.pop();
                    const s = std.mem.concat(self.allocator, u8, &.{ s1.bytes, s2.bytes }) catch @panic("allocation for concatenation failed");
                    defer self.allocator.free(s);
                    const lv_str = self.gc.createLVString(s);
                    try self.stack.?.push(lv_str);
                    continue;
                }

                const b = try self.stack.?.pop();
                const a = try self.stack.?.pop();
                const result, const ok = try callMetamethod(self.allocator, a, b, "__concat", self);
                if (ok) {
                    try self.stack.?.push(result);
                    continue;
                }

                // @panic("concatenation error!");
                try self.pushString("concatenation error!");
                return LuaError.Panic;
            }
        }
        // n == 1, do nothing   w
    }

    // [-1, +(2|0), e]
    // http://www.lua.org/manual/5.3/manual.html#lua_next
    pub fn next(self: *LuaState, idx: i32) LuaError!bool {
        const val = self.stack.?.get(idx);
        const ok = val.isTable();
        if (ok) {
            const t = val.asTable();
            const key = try self.stack.?.pop();
            const next_key = t.nextKey(key);
            if (next_key != .nil) {
                try self.stack.?.push(next_key);
                try self.stack.?.push(t.get(next_key));
                return true;
            }
            return false;
        }
        // @panic("table expected!");
        try self.pushString("table expected!");
        return LuaError.Panic;
    }

    // [-1, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#lua_error
    pub fn Error(self: *LuaState) LuaError!i32 {
        const err = try self.stack.?.pop();
        try self.stack.?.push(err);
        return LuaError.Panic;
    }

    /// **************************  api_vm  **************************

    // api_vm
    pub fn pc(self: *LuaState) i32 {
        return self.stack.?.pc;
    }

    pub fn addPC(self: *LuaState, n: i32) void {
        self.stack.?.pc += n;
    }

    pub fn fetch(self: *LuaState) u32 {
        const i = self.stack.?.closure.?.proto.?.code[@as(usize, @intCast(self.stack.?.pc))];
        self.stack.?.pc += 1;
        return i;
    }

    pub fn getConst(self: *LuaState, idx: i32) LuaError!void {
        const c = self.stack.?.closure.?.proto.?.constants[@as(usize, @intCast(idx))];
        try self.stack.?.push(c);
    }

    pub fn getRK(self: *LuaState, rk: i32) LuaError!void {
        if (rk > 0xFF) { // constant
            try self.getConst(rk & 0xFF);
        } else { // register
            try self.pushValue(rk + 1);
        }
    }

    pub fn registerCount(self: *LuaState) i32 {
        return @intCast(self.stack.?.closure.?.proto.?.max_stack_size);
    }

    pub fn loadVararg(self: *LuaState, n_args: i32) LuaError!void {
        const n: i32 = if (n_args < 0)
            if (self.stack.?.varargs) |varargs| @as(i32, @intCast(varargs.len)) else 0
        else
            n_args;

        self.stack.?.check(n);
        if (self.stack.?.varargs) |varargs| {
            try self.stack.?.pushN(varargs, n);
        } else {
            // No varargs available, push nils
            for (0..@as(usize, @intCast(n))) |_| {
                try self.stack.?.push(LuaValue.LUA_NIL);
            }
        }
    }

    pub fn loadProto(self: *LuaState, idx: i32) LuaError!void {
        if (self.stack) |stack| {
            const proto = stack.closure.?.proto.?.protos[@as(usize, @intCast(idx))];
            const lv_closure = self.gc.createLVLuaClosure(proto);
            const closure = lv_closure.asClosure();
            try stack.push(lv_closure);

            for (0.., proto.upvalues) |i, uv_info| {
                const uv_idx: usize = @intCast(uv_info.idx);
                if (uv_info.in_stack == 1) {
                    if (stack.openuvs == null) {
                        stack.openuvs = std.AutoHashMap(i32, *UpValue).init(self.allocator);
                    }

                    const openuv = stack.openuvs.?.get(@as(i32, @intCast(uv_idx)));
                    if (openuv) |uv| {
                        closure.upvals[i] = uv;
                    } else {
                        const lv_upval = self.gc.createOpenObjUpValue(&stack.slots.items[uv_idx]);
                        const upvalue = lv_upval.asUpval();
                        closure.upvals[i] = upvalue;
                        stack.openuvs.?.put(@as(i32, @intCast(uv_idx)), upvalue) catch @panic("allocation failed");
                    }
                } else {
                    closure.upvals[i] = stack.closure.?.upvals[uv_idx];
                }
            }
        }
    }

    pub fn closeUpvalues(self: *LuaState, a: i32) void {
        if (self.stack) |stack| {
            var keys_to_remove = std.ArrayList(i32).initCapacity(self.allocator, 8) catch @panic("allocation failed");
            defer keys_to_remove.deinit(self.allocator);

            var it = stack.openuvs.?.iterator();
            while (it.next()) |entry| {
                const i = entry.key_ptr.*;
                if (i >= a - 1) {
                    const openuv = entry.value_ptr.*;
                    openuv.*.close(self.allocator);
                    keys_to_remove.append(self.allocator, i) catch @panic("allocation failed");
                }
            }

            for (keys_to_remove.items) |key| {
                _ = stack.openuvs.?.remove(key);
            }
        }
    }

    /// **************************  api_get  **************************

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_newtable
    pub fn newTable(self: *LuaState) LuaError!void {
        try self.createTable(0, 0);
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_createtable
    pub fn createTable(self: *LuaState, n_arr: i32, n_rec: i32) LuaError!void {
        const lv_table = self.gc.createLVTable(n_arr, n_rec);
        try self.stack.?.push(lv_table);
    }

    // [-1, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettable
    pub fn GetTable(self: *LuaState, idx: i32) LuaError!LuaType {
        const t = self.stack.?.get(idx);
        const k = try self.stack.?.pop();
        return self.getTable(t, k, false);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getfield
    pub fn getField(self: *LuaState, idx: i32, k: string) LuaError!LuaType {
        const t = self.stack.?.get(idx);
        const lv_str = self.gc.createLVString(k);
        return try self.getTable(t, lv_str, false);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_geti
    pub fn getI(self: *LuaState, idx: i32, i: i64) LuaError!LuaType {
        const t = self.stack.?.get(idx);
        return try self.getTable(t, .{ .int64 = i }, false);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawget
    pub fn rawGet(self: *LuaState, idx: i32) LuaError!LuaType {
        const t = self.stack.?.get(idx);
        const k = try self.stack.?.pop();
        return try self.getTable(t, k, true);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawgeti
    pub fn rawGetI(self: *LuaState, idx: i32, i: i64) LuaError!LuaType {
        const t = self.stack.?.get(idx);
        return try self.getTable(t, .{ .int64 = i }, true);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getglobal
    pub fn getGlobal(self: *LuaState, name: string) LuaError!LuaType {
        const t = self.registry.get(.{ .int64 = LUA_RIDX_GLOBALS });
        const k = self.gc.createLVString(name);
        return try self.getTable(t, k, false);
    }

    // [-0, +(0|1), –]
    // http://www.lua.org/manual/5.3/manual.html#lua_getmetatable
    pub fn GetMetatable(self: *LuaState, idx: i32) LuaError!bool {
        const val = self.stack.?.get(idx);

        if (getMetatable(self.allocator, val, self)) |mt| {
            try self.stack.?.push(.{ .obj = &mt.obj });
            return true;
        } else {
            return false;
        }
    }

    // push(t[k])
    fn getTable(self: *LuaState, t: LuaValue, k: LuaValue, raw: bool) LuaError!LuaType {
        const ok = t.isTable();
        if (ok) {
            const tbl = t.asTable();
            const v = tbl.get(k);
            if (raw or !v.isNil() or !tbl.hasMetaField("__index", self)) {
                try self.stack.?.push(v);
                return typeof(v);
            }
        }

        if (!raw) {
            const mf = getMetafield(self.allocator, t, "__index", self);
            if (!mf.isNil()) {
                return switch (mf) {
                    .obj => |obj| switch (obj.kind) {
                        .lua_table => |_| self.getTable(mf, k, false),
                        .closure => |_| {
                            try self.stack.?.push(mf);
                            try self.stack.?.push(t);
                            try self.stack.?.push(k);
                            try self.call(2, 1);
                            const v = self.stack.?.get(-1);
                            return typeof(v);
                        },
                        else => {
                            // @panic("index error!");
                            try self.pushString("index error!");
                            return LuaError.Panic;
                        },
                    },
                    else => {
                        // @panic("index error!");
                        try self.pushString("index error!");
                        return LuaError.Panic;
                    },
                };
            }
        }

        // @panic("index error!");
        try self.pushString("index error!");
        return LuaError.Panic;
    }

    /// **************************  api_set  **************************

    // [-2, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_settable
    pub fn SetTable(self: *LuaState, idx: i32) LuaError!void {
        const t = self.stack.?.get(idx);
        const v = try self.stack.?.pop();
        const k = try self.stack.?.pop();
        try self.setTable(t, k, v, false);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setfield
    pub fn setField(self: *LuaState, idx: i32, k: string) LuaError!void {
        const t = self.stack.?.get(idx);
        const v = try self.stack.?.pop();
        const lv_str = self.gc.createLVString(k);
        try self.setTable(t, lv_str, v, false);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_seti
    pub fn setI(self: *LuaState, idx: i32, i: i64) LuaError!void {
        const t = self.stack.?.get(idx);
        const v = try self.stack.?.pop();
        try self.setTable(t, .{ .int64 = i }, v, false);
    }

    // [-2, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawset
    pub fn rawSet(self: *LuaState, idx: i32) LuaError!void {
        const t = self.stack.?.get(idx);
        const v = try self.stack.?.pop();
        const k = try self.stack.?.pop();
        try self.setTable(t, k, v, true);
    }

    // [-1, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawseti
    pub fn rawSetI(self: *LuaState, idx: i32, i: i64) LuaError!void {
        const t = self.stack.?.get(idx);
        const v = try self.stack.?.pop();
        try self.setTable(t, .{ .int64 = i }, v, true);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setglobal
    pub fn setGlobal(self: *LuaState, name: string) LuaError!void {
        const t = self.registry.get(.{ .int64 = LUA_RIDX_GLOBALS });
        const v = try self.stack.?.pop();
        const k = self.gc.createLVString(name);
        try self.setTable(t, k, v, false);
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_register
    pub fn register(self: *LuaState, name: string, f: ZigFunction) LuaError!void {
        try self.pushZigFunction(f);
        try self.setGlobal(name);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_setmetatable
    pub fn SetMetatable(self: *LuaState, idx: i32) LuaError!void {
        const val = self.stack.?.get(idx);
        const mt_val = try self.stack.?.pop();

        switch (mt_val) {
            .nil => |_| setMetatable(self.allocator, val, null, self),
            .obj => |_| {
                const mt = mt_val.asTable();
                setMetatable(self.allocator, val, mt, self);
            },
            else => {
                // @panic("table expected!");
                try self.pushString("table expected!");
                return LuaError.Panic;
            }, // todo
        }
    }

    // t[k]=v
    fn setTable(self: *LuaState, t: LuaValue, k: LuaValue, v: LuaValue, raw: bool) LuaError!void {
        const ok = t.isTable();
        if (ok) {
            const tbl = t.asTable();
            if (raw or !tbl.get(k).isNil() or !tbl.hasMetaField("__newindex", self)) {
                tbl.put(k, v);
                return;
            }
        }

        if (!raw) {
            const mf = getMetafield(self.allocator, t, "__newindex", self);
            if (!mf.isNil()) {
                return switch (mf) {
                    .obj => |obj| switch (obj.kind) {
                        .lua_table => |_| self.setTable(mf, k, v, false),
                        .closure => |_| {
                            try self.stack.?.push(mf);
                            try self.stack.?.push(t);
                            try self.stack.?.push(k);
                            try self.stack.?.push(v);
                            try self.call(3, 0);
                            return;
                        },
                        else => {
                            // @panic("index error!");
                            try self.pushString("index error!");
                            return LuaError.Panic;
                        },
                    },
                    else => {
                        // @panic("index error!");
                        try self.pushString("index error!");
                        return LuaError.Panic;
                    },
                };
            }
        }

        // @panic("index error!");
        try self.pushString("index error!");
        return LuaError.Panic;
    }

    /// **************************  api_closure  **************************

    // api_closure
    pub fn setClosure(self: *LuaState, proto: *binchunk.Prototype) void {
        var lv_closure = self.gc.createLVLuaClosure(proto);
        self.stack.?.closure = lv_closure.asClosure();
    }

    /// **************************  api_call  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_load
    pub fn load(self: *LuaState, chunk: []u8, chunk_name: string, mode: string) LuaError!i32 {
        _ = chunk_name;
        _ = mode;

        const proto = binchunk.undump(chunk);
        var lv_closure = self.gc.createLVLuaClosure(proto);
        const c = lv_closure.asClosure();

        try self.stack.?.push(lv_closure);
        if (proto.upvalues.len > 0) {
            var env = self.registry.get(.{ .int64 = LUA_RIDX_GLOBALS });
            const env_ref = &env;
            var lv_upvalue = self.gc.createClosedObjUpValue(env_ref);
            c.upvals[0] = lv_upvalue.asUpval();
        }

        return @intFromEnum(ThreadStatus.lua_ok);
    }

    // [-(nargs+1), +nresults, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_call
    pub fn call(self: *LuaState, n_args: i32, n_results: i32) LuaError!void {
        const val = self.stack.?.get(-(n_args + 1));

        // first try call closure
        var ok: bool = val.isClosure();
        var c: *Closure = if (ok) val.asClosure() else undefined;
        var new_n_args = n_args;
        if (!ok) {
            // then try call __call metamethod
            const mf = getMetafield(self.allocator, val, "__call", self);
            if (!mf.isNil()) {
                ok = mf.isClosure();
                c = mf.asClosure();
                if (ok) {
                    try self.stack.?.push(val);
                    self.insert(-(n_args + 2));
                    new_n_args = n_args + 1;
                }
            }
        }
        if (ok) {
            if (c.proto != null) {
                std.debug.print("call {s}<{d},{d}>\n", .{
                    c.proto.?.source,
                    c.proto.?.line_defined,
                    c.proto.?.last_line_defined,
                });
                try self.callLuaClosure(new_n_args, n_results, c);
            } else {
                try self.callZigClosure(new_n_args, n_results, c);
            }
        } else {
            // @panic("not function!");
            try self.pushString("not function!");
            return LuaError.Panic;
        }
    }

    fn callZigClosure(self: *LuaState, n_args: i32, n_results: i32, c: *Closure) LuaError!void {
        // create new lua stack
        const new_stack = self.allocator.create(LuaStack) catch @panic("allocation failed");
        new_stack.* = LuaStack.init(self.allocator, @intCast(n_args + LUA_MINSTACK), self) catch @panic("allocation failed");
        new_stack.closure = c;

        // pass args, pop func
        var args: ?[]LuaValue = null;
        if (n_args > 0) {
            args = try self.stack.?.popN(self.allocator, n_args);
            try new_stack.pushN(args.?, n_args);
        }
        // Ensure free args memory even unwind stacks
        defer if (args) |a| {
            self.allocator.free(a);
        };
        _ = try self.stack.?.pop();

        // run closure
        self.pushLuaStack(new_stack);
        const r = try c.zig_func.?(self);

        // get results before popping the stack
        const results = if (n_results != 0)
            try new_stack.popN(self.allocator, r)
        else
            null;
        defer if (results) |res| {
            self.allocator.free(res);
        };

        self.popLuaStack();

        // return results
        if (results) |res| {
            const n = if (n_results < 0) @as(i32, @intCast(res.len)) else n_results;
            self.stack.?.check(n);
            try self.stack.?.pushN(res, n_results);
        }
    }

    fn callLuaClosure(self: *LuaState, n_args: i32, n_results: i32, c: *Closure) LuaError!void {
        const n_registers = @as(usize, @intCast(c.proto.?.max_stack_size));
        const n_params = @as(i32, @intCast(c.proto.?.num_params));
        const is_vararg = c.proto.?.is_vararg == 1;

        // create new lua stack
        const new_stack = self.allocator.create(LuaStack) catch @panic("allocation failed");
        new_stack.* = LuaStack.init(self.allocator, @intCast(n_registers + LUA_MINSTACK), self) catch @panic("allocation failed");
        new_stack.closure = c;

        // pass args, pop func
        const func_and_args = try self.stack.?.popN(self.allocator, n_args + 1);
        defer self.allocator.free(func_and_args);

        try new_stack.pushN(func_and_args[1..], n_params);
        new_stack.top = n_registers;
        if (n_args > n_params and is_vararg) {
            new_stack.varargs = func_and_args[@as(usize, @intCast(n_params + 1))..];
        }

        // run closure
        self.pushLuaStack(new_stack);
        try self.runLuaClosure();

        // get results before popping the stack
        const results_count =
            if (new_stack.top > n_registers)
                @as(i32, @intCast(new_stack.top - n_registers))
            else
                0;
        const results =
            if (n_results != 0 and results_count > 0)
                try new_stack.popN(self.allocator, results_count)
            else
                null;
        defer if (results) |res| {
            self.allocator.free(res);
        };

        self.popLuaStack();

        // return results
        if (results) |res| {
            const n = if (n_results < 0) @as(i32, @intCast(res.len)) else n_results;
            self.stack.?.check(n);
            try self.stack.?.pushN(res, n_results);
        }
    }

    fn runLuaClosure(self: *LuaState) LuaError!void {
        var lua_vm_wrapper = LuaVM.of(self);
        const lua_vm = &lua_vm_wrapper;
        outer: while (true) {
            const inst = Instruction.of(lua_vm.fetch());
            try inst.execute(lua_vm);
            if (inst.Opcode() == @intFromEnum(OpCode.OP_RETURN)) {
                break :outer;
            }
        }
    }

    // Calls a function in protected mode.
    // http://www.lua.org/manual/5.3/manual.html#lua_pcall
    pub fn pCall(self: *LuaState, n_args: i32, n_results: i32, msgh: i32) ThreadStatus {
        const caller = self.stack;

        self.call(n_args, n_results) catch |err| {
            if (err != LuaError.Panic) {
                @panic("unknow error");
            }
            // msgh is the stack index of the error handler (if any)
            if (msgh != 0) {
                // For now, we don't support message handlers
                @panic("message handler not supported yet");
            }

            // 1. Recover the error object from the top of the CURRENT active stack.
            const err_val = if (self.stack != null and self.stack.?.top > 0)
                self.stack.?.pop() catch LuaValue.LUA_NIL
            else
                LuaValue.LUA_NIL;

            // 2. Unwind key: Pop stack frames until we return to the caller's frame.
            //    Note: This destroys the intermediate stacks (and their OpenUpvalues if implemented).
            while (self.stack != caller) {
                self.popLuaStack();
            }

            // 3. Push error object to caller stack
            self.stack.?.check(1);
            self.stack.?.push(err_val) catch {};
            return if (err == LuaError.Panic) .lua_errrun else .lua_errmem;
        };

        return .lua_ok;
    }
};
