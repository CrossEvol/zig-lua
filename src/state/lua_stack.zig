const std = @import("std");

const LuaError = @import("../api/root.zig").LuaError;
const binchunk = @import("../binchunk/root.zig");
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaTable = @import("lua_table.zig").LuaTable;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;
const UpValue = @import("closure.zig").UpValue;

const LUA_REGISTRYINDEX: i32 = @intCast(@import("../api/root.zig").LUA_REGISTRYINDEX);
pub const LuaStack = struct {
    // virtual stack
    slots: std.ArrayList(LuaValue),
    top: usize,

    // call info
    state: ?*LuaState,
    closure: ?*Closure,
    varargs: ?[]LuaValue,
    openuvs: ?std.AutoHashMap(i32, *UpValue),
    pc: i32,

    // linked list
    prev: ?*LuaStack,

    // memory management
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, size: usize, state: ?*LuaState) !LuaStack {
        var slots = try std.ArrayList(LuaValue).initCapacity(allocator, size);
        try slots.ensureTotalCapacity(allocator, size);
        try slots.appendNTimes(allocator, LuaValue.LUA_NIL, size);

        return .{
            .slots = slots,
            .top = 0,
            .state = state,
            .closure = null,
            .varargs = null,
            .openuvs = std.AutoHashMap(i32, *UpValue).init(allocator),
            .pc = 0,
            .prev = null,
            .allocator = allocator,
        };
    }

    pub fn mark(self: *LuaStack) void {
        for (self.slots.items) |*item| {
            item.mark();
        }
        if (self.varargs) |varargs| {
            for (varargs) |val| {
                val.mark();
            }
        }
        if (self.closure) |closure| {
            closure.asObj().markObject();
        }
        if (self.openuvs) |openuvs| {
            var it = openuvs.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.*.asObj().markObject();
            }
        }
        if (self.prev) |prev| {
            prev.mark();
        }
    }

    pub fn deinit(self: *LuaStack) void {
        // collect slots
        self.slots.deinit(self.allocator);

        // collect openuvs
        self.openuvs.?.deinit();
    }

    pub fn check(self: *LuaStack, n: i32) void {
        const free = self.slots.items.len - self.top;
        if (@as(usize, @intCast(n)) < free) return;
        for (free..@as(usize, @intCast(n))) |_| {
            self.slots.append(self.allocator, LuaValue.LUA_NIL) catch @panic("stack overflow");
        }
    }

    /// Push a value onto the stack.
    /// The stack takes full ownership of the value.
    pub fn push(self: *LuaStack, val: LuaValue) LuaError!void {
        if (self.top == self.slots.items.len) {
            if (self.state) |state| {
                try state.pushString("stack overflow");
            }
            return LuaError.Panic;
        }
        self.slots.items[self.top] = val;
        self.top += 1;
    }

    /// Pop a value from the stack and return it.
    /// Transfers ownership of the value back to the caller.
    pub fn pop(self: *LuaStack) LuaError!LuaValue {
        if (self.top < 1) {
            if (self.state) |state| {
                try state.pushString("stack underflow!");
            }
            return LuaError.Panic;
        }
        self.top -= 1;
        const val = self.slots.items[self.top];
        self.slots.items[self.top] = LuaValue.LUA_NIL;
        return val;
    }

    pub fn pushN(self: *LuaStack, vals: []LuaValue, n: i32) LuaError!void {
        const n_vals = vals.len;
        const end: usize = if (n < 0) n_vals else @intCast(n);

        for (0..end) |i| {
            if (i < n_vals) {
                try self.push(vals[i]);
            } else {
                try self.push(LuaValue.LUA_NIL);
            }
        }
    }

    pub fn popN(self: *LuaStack, allocator: std.mem.Allocator, n: i32) LuaError![]LuaValue {
        const vals = try allocator.alloc(LuaValue, @as(usize, @intCast(n)));
        var i = n - 1;
        while (i >= 0) : (i -= 1) {
            vals[@as(usize, @intCast(i))] = try self.pop();
        }
        return vals;
    }

    pub fn absIndex(self: *LuaStack, idx: i32) i32 {
        if (idx >= 0 or idx <= LUA_REGISTRYINDEX) {
            return idx;
        }

        return idx + @as(i32, @intCast(self.top)) + 1;
    }

    pub fn isValid(self: *LuaStack, idx: i32) bool {
        if (idx < LUA_REGISTRYINDEX) { // upvalues
            const uv_idx: usize = @intCast(LUA_REGISTRYINDEX - idx - 1);
            const c = self.closure;
            return c != null and uv_idx < c.?.upvals.len;
        }
        if (idx == LUA_REGISTRYINDEX) {
            return true;
        }
        const absIdx = @as(usize, @intCast(self.absIndex(idx)));
        return absIdx > 0 and absIdx <= self.top;
    }

    /// Get a value from the stack by index.
    /// Returns a reference (borrowing). NO cloning is performed here.
    /// If the caller needs to keep the value beyond the current stack
    /// operation, they MUST clone it themselves.
    pub fn get(self: *LuaStack, idx: i32) LuaValue {
        if (idx < LUA_REGISTRYINDEX) { // upvalues
            const uv_idx: usize = @intCast(LUA_REGISTRYINDEX - idx - 1);
            const c = self.closure;
            if (c == null or uv_idx >= c.?.upvals.len) {
                return LuaValue.LUA_NIL;
            } else {
                return c.?.upvals[uv_idx].?.val.*;
            }
        }
        if (idx == LUA_REGISTRYINDEX) {
            // Return the value without cloning - caller is responsible for cloning if needed
            return .{ .obj = self.state.?.registry.asObj() };
        }

        const absIdx = @as(usize, @intCast(self.absIndex(idx)));
        if (absIdx > 0 and absIdx <= self.top) {
            // Return the value without cloning - caller is responsible for cloning if needed
            return self.slots.items[absIdx - 1];
        }
        return LuaValue.LUA_NIL;
    }

    /// Set a value at the specified stack index.
    /// The stack takes full ownership of the new value.
    /// The previous value at this index is automatically de-initialized.
    pub fn set(self: *LuaStack, idx: i32, val: LuaValue) LuaError!void {
        if (idx < LUA_REGISTRYINDEX) { // upvalues
            const uv_idx: usize = @intCast(LUA_REGISTRYINDEX - idx - 1);
            const c = self.closure;
            if (c != null and uv_idx < c.?.upvals.len) {
                if (c.?.upvals[uv_idx]) |uv| {
                    uv.val.* = val;
                }
            }
            return;
        }
        if (idx == LUA_REGISTRYINDEX) {
            self.state.?.registry = val.asTable();
            return;
        }

        const absIdx = @as(usize, @intCast(self.absIndex(idx)));
        if (absIdx > 0 and absIdx <= self.top) {
            self.slots.items[absIdx - 1] = val;
            return;
        }

        // @panic("invalid index!");
        if (self.state) |state| {
            try state.pushString("invalid index!");
        }
        return LuaError.Panic;
    }

    pub fn reverse(self: *LuaStack, from: i32, to: i32) void {
        var i: usize = @intCast(from);
        var j: usize = @intCast(to);
        while (i < j) {
            std.mem.swap(LuaValue, &self.slots.items[i], &self.slots.items[j]);
            i += 1;
            j -= 1;
        }
    }
};
