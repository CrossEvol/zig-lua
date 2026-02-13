const std = @import("std");
const math = std.math;
const Thread = std.Thread;

const api = @import("../api/root.zig");
const LUA_REGISTRYINDEX = api.LUA_REGISTRYINDEX;
const LUA_MULTRET = api.LUA_MULTRET;
const ThreadStatus = api.ThreadStatus;
const LuaType = api.LuaType;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LUA_RIDX_GLOBALS = api.LUA_RIDX_GLOBALS;
const LUA_RIDX_MAINTHREAD = api.LUA_RIDX_MAINTHREAD;
const LUA_MINSTACK = api.LUA_MINSTACK;
const LuaError = @import("../api/root.zig").LuaError;
const Rand = @import("../api/root.zig").Rand;
const binchunk = @import("../binchunk/root.zig");
const compiler = @import("../compiler/root.zig");
const number = @import("../number/root.zig");
const state = @import("../state/root.zig");
const operators = state.operators;
const _arith = state._arith;
const _eq = state._eq;
const _lt = state._lt;
const _le = state._le;
const stdlib = @import("../stdlib/root.zig");
const vm = @import("../vm/root.zig");
const LuaVM = vm.LuaVM;
const OpCode = vm.OpCode;
const Instruction = vm.Instruction;
const callMetamethod = @import("lua_value.zig").callMetamethod;
const Channel = @import("channel.zig").Channel;
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

pub const FuncReg = std.StaticStringMap(?ZigFunction);

pub const LuaState = struct {
    obj: Object,
    registry: *LuaTable, // borrow from gc
    stack: ?*LuaStack, // referenced
    rand: Rand,

    // coroutine
    co_chan: ?*Channel,
    co_status: ThreadStatus,
    co_caller: ?*LuaState,
    co_thread: ?Thread,

    // memory management
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    gc: *GC,

    pub fn init(allocator: std.mem.Allocator, gc: *GC) !LuaState {
        var lv_table = gc.createLVTable(0, 0);
        const registry = lv_table.asTable();

        const rand = Rand.init(@intCast((std.time.Instant.now() catch @panic("Unsupported")).timestamp));

        var ls: LuaState = .{
            .obj = Object.init(.lua_state),
            .registry = registry,
            .stack = null,
            .rand = rand,
            .co_chan = null,
            .co_status = .lua_ok,
            .co_caller = null,
            .co_thread = null,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .gc = gc,
        };

        const env = gc.createLVTable(0, 0);
        registry.put(.{ .int64 = LUA_RIDX_GLOBALS }, env);
        const global_table = gc.createLVTable(0, 20);
        registry.put(.{ .int64 = LUA_RIDX_MAINTHREAD }, global_table);

        const stack = try allocator.create(LuaStack);
        stack.* = try LuaStack.init(allocator, @intCast(LUA_MINSTACK), null);
        ls.pushLuaStack(stack);

        return ls;
    }

    pub fn deinit(self: *LuaState, allocator: std.mem.Allocator) void {
        var option_curr = self.stack;
        while (true) {
            if (option_curr) |curr| {
                const prev = curr.prev;
                curr.deinit();
                allocator.destroy(curr);
                option_curr = prev;
            } else {
                break;
            }
        }

        if (self.co_thread) |t| {
            t.detach();
        }
        if (self.co_chan) |c| {
            allocator.destroy(c);
        }

        self.arena.deinit();
    }

    pub fn create(gc: *GC) !*LuaState {
        var lv_table = gc.createLVTable(0, 0);
        const registry = lv_table.asTable();

        const rand = Rand.init(@intCast((std.time.Instant.now() catch @panic("Unsupported")).timestamp));

        const ls = try gc.allocator.create(LuaState);
        errdefer gc.allocator.destroy(ls);

        ls.* = .{
            .obj = Object.init(.lua_state),
            .registry = registry,
            .stack = null,
            .rand = rand,
            .co_chan = null,
            .co_status = .lua_ok,
            .co_caller = null,
            .co_thread = null,
            .allocator = gc.allocator,
            .arena = std.heap.ArenaAllocator.init(gc.allocator),
            .gc = gc,
        };

        const env = gc.createLVTable(0, 0);
        registry.put(.{ .int64 = LUA_RIDX_GLOBALS }, env);
        const global_table = gc.createLVTable(0, 20);
        registry.put(.{ .int64 = LUA_RIDX_MAINTHREAD }, global_table);

        const stack = try gc.allocator.create(LuaStack);
        stack.* = try LuaStack.init(gc.allocator, @intCast(LUA_MINSTACK), ls);
        ls.pushLuaStack(stack);

        return ls;
    }

    pub fn createWithRegistry(gc: *GC, registry: *LuaTable) !*LuaState {
        const rand = Rand.init(@intCast((std.time.Instant.now() catch @panic("Unsupported")).timestamp));

        const ls = try gc.allocator.create(LuaState);
        errdefer gc.allocator.destroy(ls);

        ls.* = .{
            .obj = Object.init(.lua_state),
            .registry = registry,
            .stack = null,
            .rand = rand,
            .co_chan = null,
            .co_status = .lua_ok,
            .co_caller = null,
            .co_thread = null,
            .allocator = gc.allocator,
            .arena = std.heap.ArenaAllocator.init(gc.allocator),
            .gc = gc,
        };

        return ls;
    }

    // Cast from generic object -> LuaState(**Downcast**)
    pub fn fromObj(obj: *Object) *LuaState {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from LuaState -> generic object(**Upcast**)
    pub fn asObj(self: *LuaState) *Object {
        return &self.obj;
    }

    pub fn mark(self: *const LuaState) void {
        self.registry.asObj().markObject();
        if (self.stack) |stack| {
            stack.mark();
        }
    }

    pub fn isMainThread(self: *LuaState) bool {
        return self.registry.get(.{ .int64 = LUA_RIDX_MAINTHREAD }).eql(.{ .obj = self.asObj() });
    }

    pub fn pushLuaStack(self: *LuaState, stack: *LuaStack) void {
        stack.prev = self.stack;
        self.stack = stack;
    }

    pub fn popLuaStack(self: *LuaState, allocator: std.mem.Allocator) void {
        const lua_stack = self.stack;

        if (lua_stack) |stack| {
            self.stack = stack.prev.?;
            stack.prev = null;
            stack.deinit(); // TODO: LuaStack不由 GC 管理
            allocator.destroy(stack);
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

        try self.pushString("rawLen failed");
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
        const s, const ok = try self.toStringX(self.allocator, idx);
        _ = ok;
        return s;
    }

    pub fn toStringX(self: *LuaState, allocator: std.mem.Allocator, idx: i32) LuaError!struct { *LuaString, bool } {
        const val = self.stack.?.get(idx);
        switch (val) {
            .int64 => |x| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{x});
                defer allocator.free(s);
                var lv_str = self.gc.createLVString(s);
                try self.stack.?.set(idx, lv_str);
                return .{ lv_str.asStr(), true };
            },
            .float64 => |x| {
                const s = try std.fmt.allocPrint(allocator, "{d}", .{x});
                defer allocator.free(s);
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

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tothread
    pub fn toThread(self: *LuaState, idx: i32) ?*LuaState {
        const val = self.stack.?.get(idx);
        return switch (val) {
            .obj => |obj| switch (obj.kind) {
                .lua_state => |_| val.asThread(),
                else => null,
            },
            else => null,
        };
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_topointer
    pub fn toPointer(self: *LuaState, idx: i32) i32 {
        const addr = @intFromPtr(&self.stack.?.get(idx));
        return @intCast(addr);
    }

    /// **************************  api_stack  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettop
    pub fn getTop(self: *LuaState) i32 {
        return @intCast(self.stack.?.top);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_absindex
    pub fn absIndex(self: *LuaState, idx: i32) i32 {
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
            try self.pushString("stack underflow!");
            return LuaError.Panic;
        }

        const n = @as(i32, @intCast(self.stack.?.top)) - new_top;
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

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_xmove
    pub fn xMove(self: *LuaState, to: *LuaState, n: i32) LuaError!void {
        const vals = try self.stack.?.popN(self.arena.allocator(), n);
        try to.stack.?.pushN(vals, n);
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

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushfstring
    pub fn pushFString(self: *LuaState, comptime fmt_str: string, args: anytype) LuaError!void {
        const Args = @TypeOf(args);
        const args_type_info = @typeInfo(Args);
        comptime {
            const valid = switch (args_type_info) {
                .@"struct" => |s| s.is_tuple,
                .void => true, // .{}
                else => false,
            };

            if (!valid) {
                @compileError("pushFString require tuple syntax:\n, got type: " ++ @typeName(Args));
            }
        }

        const str = try std.fmt.allocPrint(self.allocator, fmt_str, args);
        defer self.allocator.free(str);
        const lv_str = self.gc.createLVString(str);
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
            closure.upvals[@as(usize, @intCast(i - 1))] = self.gc.createClosedObjUpValue(val_ref).asUpval();
        }
        try self.stack.?.push(lv_closure);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushglobaltable
    pub fn pushGlobalTable(self: *LuaState) LuaError!void {
        const global = self.registry.get(.{ .int64 = LUA_RIDX_GLOBALS });
        try self.stack.?.push(global);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushthread
    pub fn pushThread(self: *LuaState) LuaError!bool {
        try self.stack.?.push(.{ .obj = self.asObj() });
        return self.isMainThread();
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
                try self.pushString("length error!");
                return LuaError.Panic;
            }
        }
    }

    // [-n, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(self: *LuaState, allocator: std.mem.Allocator, n: i32) LuaError!void {
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
                    const s = try std.mem.concat(allocator, u8, &.{ s1.bytes, s2.bytes });
                    defer allocator.free(s);
                    const lv_str = self.gc.createLVString(s);
                    try self.stack.?.push(lv_str);
                    continue;
                }

                const b = try self.stack.?.pop();
                const a = try self.stack.?.pop();
                const result, const ok = try callMetamethod(allocator, a, b, "__concat", self);
                if (ok) {
                    try self.stack.?.push(result);
                    continue;
                }

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

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_stringtonumber
    pub fn stringToNumber(self: *LuaState, s: string) !bool {
        {
            const n, const ok = number.parseInteger(s);
            if (ok) {
                try self.pushInteger(n);
                return true;
            }
        }

        {
            const n, const ok = number.parseFloat(s);
            if (ok) {
                try self.pushNumber(n);
                return true;
            }
        }

        return false;
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
                        try stack.openuvs.?.put(@as(i32, @intCast(uv_idx)), upvalue);
                    }
                } else {
                    closure.upvals[i] = stack.closure.?.upvals[uv_idx];
                }
            }
        }
    }

    pub fn closeUpvalues(self: *LuaState, a: i32) LuaError!void {
        if (self.stack) |stack| {
            var keys_to_remove = try std.ArrayList(i32).initCapacity(self.allocator, 8);
            defer keys_to_remove.deinit(self.allocator);

            var it = stack.openuvs.?.iterator();
            while (it.next()) |entry| {
                const i = entry.key_ptr.*;
                if (i >= a - 1) {
                    const openuv = entry.value_ptr.*;
                    openuv.*.close(self.allocator);
                    try keys_to_remove.append(self.allocator, i);
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
                            try self.pushString("index error!");
                            return LuaError.Panic;
                        },
                    },
                    else => {
                        try self.pushString("index error!");
                        return LuaError.Panic;
                    },
                };
            }
        }

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
                            try self.pushString("index error!");
                            return LuaError.Panic;
                        },
                    },
                    else => {
                        try self.pushString("index error!");
                        return LuaError.Panic;
                    },
                };
            }
        }

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
    pub fn load(self: *LuaState, chunk: []const u8, chunk_name: string, mode: string) LuaError!i32 {
        _ = mode;

        var proto: *binchunk.Prototype = undefined;
        if (binchunk.is_binary_chunk(chunk)) {
            proto = binchunk.undump(chunk);
        } else {
            proto = compiler.Compile(self.arena.allocator(), chunk, chunk_name) catch {
                std.debug.print("Compiler error!", .{});
                return LuaError.Panic;
            };
        }

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
                // std.debug.print("call {s}<{d},{d}>\n", .{
                //     c.proto.?.source,
                //     c.proto.?.line_defined,
                //     c.proto.?.last_line_defined,
                // });
                try self.callLuaClosure(self.allocator, new_n_args, n_results, c);
            } else {
                try self.callZigClosure(self.allocator, new_n_args, n_results, c);
            }
        } else {
            try self.pushString("not function!");
            return LuaError.Panic;
        }
    }

    fn callZigClosure(self: *LuaState, allocator: std.mem.Allocator, n_args: i32, n_results: i32, c: *Closure) LuaError!void {
        // create new lua stack
        const new_stack = try allocator.create(LuaStack);
        new_stack.* = try LuaStack.init(allocator, @intCast(n_args + LUA_MINSTACK), self);
        new_stack.closure = c;

        // pass args, pop func
        var args: ?[]LuaValue = null;
        if (n_args > 0) {
            args = try self.stack.?.popN(self.arena.allocator(), n_args);
            try new_stack.pushN(args.?, n_args);
        }

        _ = try self.stack.?.pop();

        // run closure
        self.pushLuaStack(new_stack);
        const r = try c.zig_func.?(self);

        // get results before popping the stack
        const results = if (n_results != 0)
            try new_stack.popN(self.arena.allocator(), r)
        else
            null;

        self.popLuaStack(allocator);

        // return results
        if (results) |res| {
            const n = if (n_results < 0) @as(i32, @intCast(res.len)) else n_results;
            self.stack.?.check(n);
            try self.stack.?.pushN(res, n_results);
        }
    }

    fn callLuaClosure(self: *LuaState, allocator: std.mem.Allocator, n_args: i32, n_results: i32, c: *Closure) LuaError!void {
        const n_registers = @as(usize, @intCast(c.proto.?.max_stack_size));
        const n_params = @as(i32, @intCast(c.proto.?.num_params));
        const is_vararg = c.proto.?.is_vararg == 1;

        // create new lua stack
        const new_stack = try allocator.create(LuaStack);
        new_stack.* = try LuaStack.init(allocator, @intCast(n_registers + LUA_MINSTACK), self);
        new_stack.closure = c;

        // pass args, pop func
        const func_and_args = try self.stack.?.popN(self.arena.allocator(), n_args + 1);

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
                try new_stack.popN(self.arena.allocator(), results_count)
            else
                null;

        self.popLuaStack(allocator);

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
                self.popLuaStack(self.allocator);
            }

            // 3. Push error object to caller stack
            self.stack.?.check(1);
            self.stack.?.push(err_val) catch {};
            return if (err == LuaError.Panic) .lua_errrun else .lua_errmem;
        };

        return .lua_ok;
    }

    /// **************************  auxlib  **************************

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_error
    pub fn error2(self: *LuaState, comptime fmt_str: string, args: anytype) LuaError!i32 {
        try self.pushFString(fmt_str, args);
        return self.Error();
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_argerror
    pub fn argError(self: *LuaState, arg: i32, extra_msg: string) LuaError!i32 {
        // bad argument #arg to 'funcname' (extramsg)
        return self.error2("bad argument #{d} ({s})", .{ arg, extra_msg });
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checkstack
    pub fn checkStack2(self: *LuaState, sz: i32, msg: string) LuaError!void {
        if (!self.checkStack(sz)) {
            if (!std.mem.eql(u8, msg, "")) {
                _ = try self.error2("stack overflow ({s})", .{msg});
            } else {
                _ = try self.error2("stack overflow", .{});
            }
        }
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_argcheck
    pub fn argCheck(self: *LuaState, cond: bool, arg: i32, extra_msg: string) LuaError!void {
        if (!cond) {
            _ = try self.argError(arg, extra_msg);
            unreachable;
        }
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checkany
    pub fn checkAny(self: *LuaState, arg: i32) LuaError!void {
        if (self.Type(arg) == .lua_t_none) {
            _ = try self.argError(arg, "value expected");
            unreachable;
        }
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checktype
    pub fn checkType(self: *LuaState, arg: i32, t: LuaType) LuaError!void {
        if (self.Type(arg) != t) {
            _ = try self.tagError(arg, t);
            unreachable;
        }
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checkinteger
    pub fn checkInteger(self: *LuaState, arg: i32) LuaError!i64 {
        const i, const ok = self.toIntegerX(arg);
        if (!ok) {
            _ = try self.intError(arg);
            unreachable;
        }
        return i;
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checknumber
    pub fn checkNumber(self: *LuaState, arg: i32) LuaError!f64 {
        const f, const ok = self.toNumberX(arg);
        if (!ok) {
            _ = try self.tagError(arg, .lua_t_number);
            unreachable;
        }
        return f;
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_checkstring
    // http://www.lua.org/manual/5.3/manual.html#luaL_checklstring
    pub fn checkString(self: *LuaState, arg: i32) LuaError!string {
        const s, const ok = try self.toStringX(self.allocator, arg);
        if (!ok) {
            _ = try self.tagError(arg, .lua_t_string);
            unreachable;
        }
        return s.bytes;
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_optinteger
    pub fn optInteger(self: *LuaState, arg: i32, def: i64) LuaError!i64 {
        if (self.isNoneOrNil(arg)) {
            return def;
        }
        return self.checkInteger(arg);
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_optnumber
    pub fn optNumber(self: *LuaState, arg: i32, def: f64) LuaError!f64 {
        if (self.isNoneOrNil(arg)) {
            return def;
        }
        return self.checkNumber(arg);
    }

    // [-0, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#luaL_optstring
    pub fn optString(self: *LuaState, arg: i32, def: string) LuaError!string {
        if (self.isNoneOrNil(arg)) {
            return def;
        }
        return self.checkString(arg);
    }

    // [-0, +?, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_dofile
    pub fn doFile(self: *LuaState, filename: string) LuaError!bool {
        return (try self.loadFile(filename)) != .lua_ok or self.pCall(0, LUA_MULTRET, 0) != .lua_ok;
    }

    // [-0, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#luaL_dostring
    pub fn doString(self: *LuaState, str: string) LuaError!bool {
        return (try self.loadString(str)) != .lua_ok or self.pCall(0, LUA_MULTRET, 0) != .lua_ok;
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_loadfile
    pub fn loadFile(self: *LuaState, filename: string) LuaError!ThreadStatus {
        return try self.loadFileX(filename, "bt");
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_loadfilex
    pub fn loadFileX(self: *LuaState, filename: string, mode: string) LuaError!ThreadStatus {
        var threaded: std.Io.Threaded = .init(self.allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const cwd = std.Io.Dir.cwd();
        const file = cwd.openFile(io, filename, .{ .mode = .read_only }) catch return LuaError.Panic;
        defer file.close(io);
        const stat = file.stat(io) catch return LuaError.Panic;
        const file_size = stat.size;
        const data = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(data);

        var fr = file.reader(io, data);
        var reader = &fr.interface;
        if (reader.readSliceAll(data)) {
            const chunk_name = try std.fmt.allocPrint(self.allocator, "@{s}", .{filename});
            defer self.allocator.free(chunk_name);
            return @enumFromInt(try self.load(data, chunk_name, mode));
        } else |err| {
            std.debug.print("{s}", .{@errorName(err)});
            return .lua_errfile;
        }
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#luaL_loadstring
    pub fn loadString(self: *LuaState, s: string) LuaError!i32 {
        return self.load(s, s, "bt");
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#luaL_typename
    pub fn typeName2(self: *LuaState, idx: i32) LuaError!string {
        return self.typeName(self.Type(idx));
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_len
    pub fn len2(self: *LuaState, idx: i32) LuaError!i64 {
        try self.len(idx);
        const i, const is_num = self.toIntegerX(-1);
        if (!is_num) {
            _ = try self.error2("object length is not an integer", .{});
        }
        try self.pop(1);
        return i;
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_tolstring
    pub fn toString2(self: *LuaState, idx: i32) LuaError!string {
        if (try self.callMeta(idx, "__tostring")) { //metafield?
            if (!self.isString(-1)) {
                _ = try self.error2("'__tostring' must return a string", .{});
            }
        } else {
            switch (self.Type(idx)) {
                .lua_t_number => {
                    if (self.isInteger(idx)) {
                        const s = try std.fmt.allocPrint(self.allocator, "{d}", .{self.toInteger(idx)});
                        defer self.allocator.free(s);
                        try self.pushString(s);
                    } else {
                        const s = try std.fmt.allocPrint(self.allocator, "{d}", .{self.toNumber(idx)});
                        defer self.allocator.free(s);
                        try self.pushString(s);
                    }
                },
                .lua_t_string => {
                    try self.pushValue(idx);
                },
                .lua_t_boolean => {
                    if (self.toBoolean(idx)) {
                        try self.pushString("true");
                    } else {
                        try self.pushString("false");
                    }
                },
                .lua_t_nil => {
                    try self.pushString("nil");
                },
                else => {
                    const tt = try self.GetMetafield(idx, "__name"); // try name
                    var kind: string = undefined;
                    if (tt == .lua_t_string) {
                        kind = try self.checkString(-1);
                    } else {
                        kind = try self.typeName2(idx);
                    }

                    const s = try std.fmt.allocPrint(self.allocator, "{s}: {x}", .{ kind, self.toPointer(idx) });
                    defer self.allocator.free(s);
                    try self.pushString(s);
                    if (tt != .lua_t_nil) {
                        try self.remove(-2); // remove '__name'
                    }
                },
            }
        }
        return self.checkString(-1);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_getsubtable
    pub fn getSubTable(self: *LuaState, idx0: i32, fname: string) LuaError!bool {
        var idx = idx0;
        if (try self.getField(idx, fname) == .lua_t_table) {
            return true; // table already there
        }
        try self.pop(1); // remove previous result
        idx = self.stack.?.absIndex(idx);
        try self.newTable(); // copy to be left at top
        try self.pushValue(-1); // assign new table to field
        try self.setField(idx, fname); // false, because did not find table there
        return false;
    }

    // [-0, +(0|1), m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_getmetafield
    pub fn GetMetafield(self: *LuaState, obj: i32, event: string) LuaError!LuaType {
        if (!(try self.GetMetatable(obj))) { // no metatable?
            return .lua_t_nil;
        }

        try self.pushString(event);
        const tt = try self.rawGet(-2);
        if (tt == .lua_t_nil) { // is metafield nil?
            try self.pop(2); // remove metatable and metafield
        } else {
            try self.remove(-2); // remove only metatable
        }
        return tt; // return metafield type
    }

    // [-0, +(0|1), e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_callmeta
    pub fn callMeta(self: *LuaState, obj0: i32, event: string) LuaError!bool {
        const obj = self.absIndex(obj0);
        if ((try self.GetMetafield(obj, event)) == .lua_t_nil) { // no metafield?
            return false;
        }

        try self.pushValue(obj);
        try self.call(1, 1);
        return true;
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_openlibs
    pub fn openLibs(self: *LuaState) LuaError!void {
        const libs = std.StaticStringMap(ZigFunction).initComptime(
            .{
                .{ "_G", stdlib.openBaseLib },
                .{ "math", stdlib.openMathLib },
                .{ "table", stdlib.openTableLib },
                .{ "string", stdlib.openStringLib },
                .{ "string", stdlib.openStringLib },
                .{ "utf8", stdlib.openUTF8Lib },
                .{ "os", stdlib.openOSLib },
                .{ "package", stdlib.openPackageLib },
                .{ "coroutine", stdlib.openCoroutineLib },
            },
        );

        for (libs.keys()) |name| {
            const fun = libs.get(name).?;
            try self.requireF(name, fun, true);
            try self.pop(1);
        }
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#luaL_requiref
    pub fn requireF(self: *LuaState, mod_name: string, open_f: ZigFunction, glb: bool) LuaError!void {
        _ = try self.getSubTable(LUA_REGISTRYINDEX, "_LOADED");
        _ = try self.getField(-1, mod_name); // LOADED[modname]
        if (!self.toBoolean(-1)) { // package not already loaded?
            try self.pop(1); // remove field
            try self.pushZigFunction(open_f);
            try self.pushString(mod_name); // argument to open function
            try self.call(1, 1); // call 'openf' to open module
            try self.pushValue(-1); // make copy of module (call result)
            try self.setField(-3, mod_name); // _LOADED[modname] = module
        }
        try self.remove(-2); // remove _LOADED table
        if (glb) {
            try self.pushValue(-1); // copy of module
            try self.setGlobal(mod_name); // _G[modname] = module
        }
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_newlib
    pub fn newLib(self: *LuaState, l: FuncReg) LuaError!void {
        try self.newLibTable(l);
        try self.setFuncs(l, 0);
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_newlibtable
    pub fn newLibTable(self: *LuaState, l: FuncReg) LuaError!void {
        try self.createTable(0, @intCast(l.keys().len));
    }

    // [-nup, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#luaL_setfuncs
    pub fn setFuncs(self: *LuaState, l: FuncReg, nup: i32) LuaError!void {
        try self.checkStack2(nup, "too many upvalues");
        for (l.keys()) |name| { // fill the table with given functions
            const fun = l.get(name).?;
            for (0..@as(usize, @intCast(nup))) |_| { // copy upvalues to the top
                try self.pushValue(-nup);
            }
            // r[-(nup+2)][name]=fun
            try self.pushZigClosure(fun.?, nup); // closure with those upvalues
            try self.setField(-(nup + 2), name);
        }
        try self.pop(nup);
    }

    pub fn intError(self: *LuaState, arg: i32) LuaError!void {
        if (self.isNumber(arg)) {
            _ = try self.argError(arg, "number has no integer representation");
            unreachable;
        } else {
            _ = try self.tagError(arg, .lua_t_number);
            unreachable;
        }
    }

    pub fn tagError(self: *LuaState, arg: i32, tag: LuaType) LuaError!void {
        _ = try self.typeError(arg, self.typeName(tag));
    }

    pub fn typeError(self: *LuaState, arg: i32, t_name: string) LuaError!i32 {
        var type_arg: string = undefined; // name for the type of the actual argument
        if (try self.GetMetafield(arg, "__name") == .lua_t_string) {
            type_arg = (try self.toString(-1)).bytes; // use the given type name
        } else if (self.Type(arg) == .lua_t_light_userdata) {
            type_arg = "light userdata"; // special name for messages
        } else {
            type_arg = try self.typeName2(arg); // standard name
        }
        const msg = try std.fmt.allocPrint(self.allocator, "{s} expected, got {s}", .{ t_name, type_arg });
        defer self.allocator.free(msg);
        try self.pushString(msg);
        return self.argError(arg, msg);
    }

    /// **************************  api_coroutine  **************************

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_newthread
    // lua-5.3.4/src/lstate.c#lua_newthread()
    pub fn newThread(self: *LuaState) LuaError!*LuaState {
        const lv_thread = self.gc.createLVLuaState(self.registry);
        const t = lv_thread.asThread();
        const stack = try self.allocator.create(LuaStack);
        stack.* = try LuaStack.init(self.allocator, LUA_MINSTACK, t);
        t.pushLuaStack(stack);
        try self.stack.?.push(lv_thread);
        return t;
    }

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_resume
    pub fn Resume(self: *LuaState, from: *LuaState, n_args: i32) LuaError!ThreadStatus {
        const ls_from = from;

        if (ls_from.co_chan == null) {
            ls_from.co_chan = try Channel.create(self.allocator);
        }

        if (self.co_chan) |co_chan| {
            // resume coroutine
            if (self.co_status != .lua_yield) {
                try self.pushString("cannot resume non-suspended coroutine");
                return .lua_errrun;
            }
            self.co_status = .lua_ok;
            co_chan.send(1);
        } else {
            // create coroutine
            self.co_chan = try Channel.create(self.allocator);
            self.co_caller = ls_from;

            if (Thread.spawn(.{}, coroutineEntry, .{ self, n_args })) |thread| {
                self.co_thread = thread;
            } else |err| {
                std.debug.print("{s}", .{@errorName(err)});
                return LuaError.Panic;
            }
        }

        _ = ls_from.co_chan.?.recv(); // wait for resume or yield
        return self.co_status;
    }

    fn coroutineEntry(self: *LuaState, n_args: i32) LuaError!void {
        self.co_status = self.pCall(n_args, -1, 0);
        self.co_caller.?.co_chan.?.send(1);
    }

    // [-?, +?, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_yield
    pub fn yield(self: *LuaState, n_results: i32) LuaError!i32 {
        _ = n_results;
        if (self.co_caller == null) {
            std.debug.print("attempt to yield from outside a coroutine", .{});
            try self.pushString("attempt to yield from outside a coroutine");
            return LuaError.Panic;
        }

        self.co_status = .lua_yield;
        self.co_caller.?.co_chan.?.send(1);
        _ = self.co_chan.?.recv();

        return self.getTop();
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isyieldable
    pub fn isYieldable(self: *LuaState) bool {
        if (self.isMainThread()) {
            return false;
        }
        return self.co_status != .lua_yield;
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_status
    // lua-5.3.4/src/lapi.c#lua_status()
    pub fn Status(self: *LuaState) ThreadStatus {
        return self.co_status;
    }

    // debug
    pub fn getStack(self: *LuaState) bool {
        if (self.stack) |stack| {
            return stack.prev != null;
        }
        return false;
    }
};
