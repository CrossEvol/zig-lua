const std = @import("std");

const ArithOp = @import("api").ArithOp;
const binchunk = @import("binchunk");
const CompareOp = @import("api").CompareOp;
const LuaType = @import("api").LuaType;

const LuaState = @import("lua_state.zig").LuaState;

const string = []const u8;

pub const LuaVM = struct {
    ls: *LuaState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !LuaVM {
        const ls = try allocator.create(LuaState);
        errdefer allocator.destroy(ls);

        ls.* = try LuaState.init(allocator);

        return .{
            .ls = ls,
            .allocator = allocator,
        };
    }

    pub fn of(ls: *LuaState) LuaVM {
        return .{
            .ls = ls,
            .allocator = ls.allocator,
        };
    }

    pub fn deinit(self: *LuaVM) void {
        self.ls.deinit();
        self.allocator.destroy(self.ls);
    }

    /// **************************  api_access  **************************

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
    pub fn toString(self: *LuaVM, idx: i32) []const u8 {
        return self.ls.toString(idx);
    }

    pub fn toStringX(self: *LuaVM, idx: i32) struct { []const u8, bool } {
        return self.ls.toStringX(idx);
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
    pub fn pop(self: *LuaVM, n: i32) void {
        self.ls.pop(n);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_copy
    pub fn copy(self: *LuaVM, from_idx: i32, to_idx: i32) void {
        self.ls.copy(from_idx, to_idx);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushvalue
    pub fn pushValue(self: *LuaVM, idx: i32) void {
        self.ls.pushValue(idx);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_replace
    pub fn replace(self: *LuaVM, idx: i32) void {
        self.ls.replace(idx);
    }

    // [-1, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_insert
    pub fn insert(self: *LuaVM, idx: i32) void {
        self.ls.insert(idx);
    }

    // [-1, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_remove
    pub fn remove(self: *LuaVM, idx: i32) void {
        self.ls.remove(idx);
    }

    // [-0, +0, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_rotate
    pub fn rotate(self: *LuaVM, idx: i32, n: i32) void {
        self.ls.rotate(idx, n);
    }

    // [-?, +?, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_settop
    pub fn setTop(self: *LuaVM, idx: i32) void {
        self.ls.setTop(idx);
    }

    /// **************************  api_push  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnil
    pub fn pushNil(self: *LuaVM) void {
        self.ls.pushNil();
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushboolean
    pub fn pushBoolean(self: *LuaVM, b: bool) void {
        self.ls.pushBoolean(b);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushinteger
    pub fn pushInteger(self: *LuaVM, n: i64) void {
        self.ls.pushInteger(n);
    }

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushnumber
    pub fn pushNumber(self: *LuaVM, n: f64) void {
        self.ls.pushNumber(n);
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_pushstring
    pub fn pushString(self: *LuaVM, s: []const u8) void {
        self.ls.pushString(s);
    }

    /// **************************  api_arith  **************************

    // [-(2|1), +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_arith
    pub fn arith(self: *LuaVM, op: ArithOp) void {
        self.ls.arith(op);
    }

    /// **************************  api_compare  **************************

    // [-0, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_compare
    pub fn compare(self: *LuaVM, idx1: i32, idx2: i32, op: CompareOp) bool {
        return self.ls.compare(idx1, idx2, op);
    }

    /// **************************  api_misc  **************************

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_len
    pub fn len(self: *LuaVM, idx: i32) void {
        self.ls.len(idx);
    }

    // [-n, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_concat
    pub fn concat(self: *LuaVM, n: i32) void {
        self.ls.concat(n);
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

    pub fn getConst(self: *LuaVM, idx: i32) void {
        self.ls.getConst(idx);
    }

    pub fn getRK(self: *LuaVM, rk: i32) void {
        self.ls.getRK(rk);
    }

    pub fn registerCount(self: *LuaVM) i32 {
        return self.ls.registerCount();
    }

    pub fn loadVararg(self: *LuaVM, n: i32) void {
        self.ls.loadVararg(n);
    }

    pub fn loadProto(self: *LuaVM, idx: i32) void {
        self.ls.loadProto(idx);
    }

    /// **************************  api_get  **************************

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_newtable
    pub fn newTable(self: *LuaVM) void {
        self.ls.newTable();
    }

    // [-0, +1, m]
    // http://www.lua.org/manual/5.3/manual.html#lua_createtable
    pub fn createTable(self: *LuaVM, n_arr: i32, n_rec: i32) void {
        self.ls.createTable(n_arr, n_rec);
    }

    // [-1, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_gettable
    pub fn getTable(self: *LuaVM, idx: i32) LuaType {
        return self.ls.getTable(idx);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_getfield
    pub fn getField(self: *LuaVM, idx: i32, k: []const u8) LuaType {
        return self.ls.getField(idx, k);
    }

    // [-0, +1, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_geti
    pub fn getI(self: *LuaVM, idx: i32, i: i64) LuaType {
        return self.ls.getI(idx, i);
    }

    /// **************************  api_set  **************************

    // [-2, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_settable
    pub fn setTable(self: *LuaVM, idx: i32) void {
        self.ls.setTable(idx);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_setfield
    pub fn setField(self: *LuaVM, idx: i32, k: []const u8) void {
        self.ls.setField(idx, k);
    }

    // [-1, +0, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_seti
    pub fn setI(self: *LuaVM, idx: i32, i: i64) void {
        self.ls.setI(idx, i);
    }

    /// **************************  api_closure  **************************

    // api_closure
    pub fn setClosure(self: *LuaVM, proto: *binchunk.Prototype) void {
        self.ls.setClosure(proto);
    }

    pub fn unsetClosure(self: *LuaVM) void {
        self.ls.unsetClosure();
    }

    /// **************************  api_all  **************************

    // [-0, +1, –]
    // http://www.lua.org/manual/5.3/manual.html#lua_load
    pub fn load(self: *LuaVM, chunk: []u8, chunk_name: string, mode: string) i32 {
        return self.ls.load(chunk, chunk_name, mode);
    }

    // [-(nargs+1), +nresults, e]
    // http://www.lua.org/manual/5.3/manual.html#lua_call
    pub fn call(self: *LuaVM, n_args: i32, n_results: i32) void {
        self.ls.call(n_args, n_results);
    }
};
