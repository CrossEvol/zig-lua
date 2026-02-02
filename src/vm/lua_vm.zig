const std = @import("std");

const api = @import("../api/root.zig").Api;
const ArithOp = api.ArithOp;
const CompareOp = api.CompareOp;
const LuaType = api.LuaType;
const LuaError = @import("../api/root.zig").Api.LuaError;
const ThreadStatus = @import("../api/root.zig").Api.LuaError;
const binchunk = @import("../binchunk/root.zig").binchunk;
const ZigFunction = @import("../state/closure.zig").ZigFunction;
const GC = @import("../state/gc.zig").GC;
const LuaString = @import("../state/lua_string.zig").LuaString;
const LuaValue = @import("../state/lua_value.zig").LuaValue;
const LuaState = @import("../state/root.zig").state.LuaState;

const string = []const u8;

pub const LuaVM = struct {
    ls: *LuaState,

    // memory management
    allocator: std.mem.Allocator,
    gc: *GC,

    pub fn init(allocator: std.mem.Allocator) !LuaVM {
        const gc = try allocator.create(GC);
        gc.* = GC.init(allocator);
        errdefer allocator.destroy(gc);

        const ls = try allocator.create(LuaState);
        errdefer allocator.destroy(ls);

        ls.* = try LuaState.init(allocator, gc);

        gc.lua_state = ls;

        return .{
            .ls = ls,
            .allocator = allocator,
            .gc = gc,
        };
    }

    pub fn of(ls: *LuaState) LuaVM {
        return .{
            .ls = ls,
            .allocator = ls.allocator,
            .gc = ls.gc,
        };
    }

    pub fn deinit(self: *LuaVM) void {
        self.ls.deinit(self.allocator);
        self.allocator.destroy(self.ls);

        self.gc.deinit();
        self.allocator.destroy(self.gc);
    }

    /// **************************  api_access  **************************

    //     // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawlen
    pub fn rawLen(self: *LuaVM, idx: i32) LuaError!usize {
        return try self.ls.rawLen(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_typename
    pub fn typeName(self: *LuaVM, tp: LuaType) []const u8 {
        return self.ls.typeName(tp);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_type
    pub fn Type(self: *LuaVM, idx: i32) LuaType {
        return self.ls.Type(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnone
    pub fn isNone(self: *LuaVM, idx: i32) bool {
        return self.ls.isNone(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnil
    pub fn isNil(self: *LuaVM, idx: i32) bool {
        return self.ls.isNil(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnoneornil
    pub fn isNoneOrNil(self: *LuaVM, idx: i32) bool {
        return self.ls.isNoneOrNil(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isboolean
    pub fn isBoolean(self: *LuaVM, idx: i32) bool {
        return self.ls.isBoolean(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_istable
    pub fn isTable(self: *LuaVM, idx: i32) bool {
        return self.ls.isTable(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isfunction
    pub fn isFunction(self: *LuaVM, idx: i32) bool {
        return self.ls.isFunction(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isthread
    pub fn isThread(self: *LuaVM, idx: i32) bool {
        return self.ls.isThread(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isstring
    pub fn isString(self: *LuaVM, idx: i32) bool {
        return self.ls.isString(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isnumber
    pub fn isNumber(self: *LuaVM, idx: i32) bool {
        return self.ls.isNumber(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_isinteger
    pub fn isInteger(self: *LuaVM, idx: i32) bool {
        return self.ls.isInteger(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_iscfunction
    pub fn isZigFunction(self: *LuaVM, idx: i32) bool {
        return self.ls.isZigFunction(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_toboolean
    pub fn toBoolean(self: *LuaVM, idx: i32) bool {
        return self.ls.toBoolean(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tointeger
    pub fn toInteger(self: *LuaVM, idx: i32) i64 {
        return self.ls.toInteger(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tointegerx
    pub fn toIntegerX(self: *LuaVM, idx: i32) struct { i64, bool } {
        return self.ls.toIntegerX(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tonumber
    pub fn toNumber(self: *LuaVM, idx: i32) f64 {
        return self.ls.toNumber(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tonumberx
    pub fn toNumberX(self: *LuaVM, idx: i32) struct { f64, bool } {
        return self.ls.toNumberX(idx);
    }

    // [-0, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_tostring
    pub fn toString(self: *LuaVM, idx: i32) LuaError!*LuaString {
        return try self.ls.toString(idx);
    }

    pub fn toStringX(self: *LuaVM, idx: i32) LuaError!struct { *LuaString, bool } {
        return try self.ls.toStringX(idx, self.allocator);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_tocfunction
    pub fn toZigFunction(self: *LuaVM, idx: i32) ?ZigFunction {
        return self.ls.toZigFunction(idx);
    }

    /// **************************  api_stack  **************************

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettop
    pub fn getTop(self: *LuaVM) usize {
        return self.ls.getTop();
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_absindex
    pub fn absIndex(self: *LuaVM, idx: i32) usize {
        return self.ls.absIndex(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_checkstack
    pub fn checkStack(self: *LuaVM, n: i32) bool {
        return self.ls.checkStack(n);
    }

    // [-n, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pop
    pub fn pop(self: *LuaVM, n: i32) LuaError!void {
        try self.ls.pop(n);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_copy
    pub fn copy(self: *LuaVM, from_idx: i32, to_idx: i32) LuaError!void {
        try self.ls.copy(from_idx, to_idx);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushvalue
    pub fn pushValue(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.pushValue(idx);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_replace
    pub fn replace(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.replace(idx);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_insert
    pub fn insert(self: *LuaVM, idx: i32) void {
        self.ls.insert(idx);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_remove
    pub fn remove(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.remove(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rotate
    pub fn rotate(self: *LuaVM, idx: i32, n: i32) void {
        self.ls.rotate(idx, n);
    }

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_settop
    pub fn setTop(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.setTop(idx);
    }

    /// **************************  api_push  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnil
    pub fn pushNil(self: *LuaVM) LuaError!void {
        try self.ls.pushNil();
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushboolean
    pub fn pushBoolean(self: *LuaVM, b: bool) LuaError!void {
        try self.ls.pushBoolean(b);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushinteger
    pub fn pushInteger(self: *LuaVM, n: i64) LuaError!void {
        try self.ls.pushInteger(n);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnumber
    pub fn pushNumber(self: *LuaVM, n: f64) LuaError!void {
        try self.ls.pushNumber(n);
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushstring
    pub fn pushString(self: *LuaVM, s: []const u8) LuaError!void {
        try self.ls.pushString(s);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushcfunction
    pub fn pushZigFunction(self: *LuaVM, f: ZigFunction) LuaError!void {
        try self.ls.pushZigFunction(f);
    }

    // [-n, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushcclosure
    pub fn pushZigClosure(self: *LuaVM, f: ZigFunction, n: i32) LuaError!void {
        try self.ls.pushZigClosure(f, n);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushglobaltable
    pub fn pushGlobalTable(self: *LuaVM) LuaError!void {
        try self.ls.pushGlobalTable();
    }

    /// **************************  api_arith  **************************

    // [-(2|1), +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_arith
    pub fn arith(self: *LuaVM, op: ArithOp) LuaError!void {
        try self.ls.arith(op);
    }

    /// **************************  api_compare  **************************

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn rawEqual(self: *LuaVM, idx1: i32, idx2: i32) LuaError!bool {
        return try self.ls.rawEqual(idx1, idx2);
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn compare(self: *LuaVM, idx1: i32, idx2: i32, op: CompareOp) LuaError!bool {
        return try self.ls.compare(idx1, idx2, op);
    }

    /// **************************  api_misc  **************************

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_len
    pub fn len(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.len(idx);
    }

    // [-n, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(self: *LuaVM, n: i32) LuaError!void {
        try self.ls.concat(self.allocator, n);
    }

    // [-1, +(2|0), e]
    // http://www.lua.org/manual/5.3/manual.html#lua_next
    pub fn next(self: *LuaVM, idx: i32) LuaError!bool {
        return try self.ls.next(idx);
    }

    // [-1, +0, v]
    // http://www.lua.org/manual/5.3/manual.html#lua_error
    pub fn Error(self: *LuaVM) LuaError!i32 {
        return try self.ls.Error();
    }

    /// **************************  api_vm  **************************
    pub fn pc(self: *LuaVM) i32 {
        return self.ls.pc();
    }

    pub fn addPC(self: *LuaVM, n: i32) void {
        self.ls.addPC(n);
    }

    pub fn fetch(self: *LuaVM) u32 {
        return self.ls.fetch();
    }

    pub fn getConst(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.getConst(idx);
    }

    pub fn getRK(self: *LuaVM, rk: i32) LuaError!void {
        try self.ls.getRK(rk);
    }

    pub fn registerCount(self: *LuaVM) i32 {
        return self.ls.registerCount();
    }

    pub fn loadVararg(self: *LuaVM, n: i32) LuaError!void {
        try self.ls.loadVararg(n);
    }

    pub fn loadProto(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.loadProto(idx);
    }

    pub fn closeUpvalues(self: *LuaVM, a: i32) void {
        self.ls.closeUpvalues(a);
    }

    /// **************************  api_get  **************************

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_newtable
    pub fn newTable(self: *LuaVM) LuaError!void {
        try self.ls.newTable();
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_createtable
    pub fn createTable(self: *LuaVM, n_arr: i32, n_rec: i32) LuaError!void {
        try self.ls.createTable(n_arr, n_rec);
    }

    // [-1, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettable
    pub fn getTable(self: *LuaVM, idx: i32) LuaError!LuaType {
        return try self.ls.GetTable(idx);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getglobal
    pub fn getGlobal(self: *LuaVM, name: string) LuaError!LuaType {
        return try self.ls.getGlobal(name);
    }

    // [-0, +(0|1), –]
    // http://www.lua.org/manual/5.3/manual.html#lua_getmetatable
    pub fn GetMetatable(self: *LuaVM, idx: i32) LuaError!bool {
        return try self.ls.GetMetatable(idx);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getfield
    pub fn getField(self: *LuaVM, idx: i32, k: []const u8) LuaError!LuaType {
        return try self.ls.getField(idx, k);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_geti
    pub fn getI(self: *LuaVM, idx: i32, i: i64) LuaError!LuaType {
        return try self.ls.getI(idx, i);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawget
    pub fn rawGet(self: *LuaVM, idx: i32) LuaError!LuaType {
        return try self.ls.rawGet(idx);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawgeti
    pub fn rawGetI(self: *LuaVM, idx: i32, i: i64) LuaError!LuaType {
        return try self.ls.rawGetI(idx, i);
    }

    /// **************************  api_set  **************************

    // [-2, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_settable
    pub fn setTable(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.SetTable(idx);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setfield
    pub fn setField(self: *LuaVM, idx: i32, k: []const u8) LuaError!void {
        try self.ls.setField(idx, k);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_seti
    pub fn setI(self: *LuaVM, idx: i32, i: i64) LuaError!void {
        try self.ls.setI(idx, i);
    }

    // [-2, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawset
    pub fn rawSet(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.rawSet(idx);
    }

    // [-1, +0, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_rawseti
    pub fn rawSetI(self: *LuaVM, idx: i32, i: i64) LuaError!void {
        try self.ls.rawSetI(idx, i);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setglobal
    pub fn setGlobal(self: *LuaVM, name: string) LuaError!void {
        try self.ls.getGlobal(name);
    }

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_register
    pub fn register(self: *LuaVM, name: string, f: ZigFunction) LuaError!void {
        try self.ls.register(name, f);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_setmetatable
    pub fn SetMetatable(self: *LuaVM, idx: i32) LuaError!void {
        try self.ls.SetMetatable(idx);
    }

    /// **************************  api_closure  **************************

    // api_closure
    pub fn setClosure(self: *LuaVM, proto: *binchunk.Prototype) void {
        self.ls.setClosure(proto);
    }

    /// **************************  api_call  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_load
    pub fn load(self: *LuaVM, chunk: []u8, chunk_name: string, mode: string) LuaError!i32 {
        return try self.ls.load(chunk, chunk_name, mode);
    }

    // [-(nargs+1), +nresults, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_call
    pub fn call(self: *LuaVM, n_args: i32, n_results: i32) LuaError!void {
        try self.ls.call(n_args, n_results);
    }

    // Calls a function in protected mode.
    // http://www.lua.org/manual/5.3/manual.html#lua_pcall
    pub fn pCall(self: *LuaVM, n_args: i32, n_results: i32, msgh: i32) ThreadStatus {
        return self.ls.pCall(n_args, n_results, msgh);
    }
};
