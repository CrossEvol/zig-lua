const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
pub const Closure = @import("closure.zig").Closure;
pub const LuaTable = @import("lua_table.zig").LuaTable;
pub const LuaValue = @import("lua_value.zig").LuaValue;

pub const LuaStack = struct {
    // virtual stack
    slots: std.ArrayList(LuaValue),
    top: usize,

    // call info
    closure: ?*Closure,
    varargs: ?[]LuaValue,
    pc: i32,

    // linked list
    prev: ?*LuaStack,

    // memory management
    allocator: std.mem.Allocator,

    pub fn init(size: usize, allocator: std.mem.Allocator) !LuaStack {
        var slots = try std.ArrayList(LuaValue).initCapacity(allocator, size);
        try slots.ensureTotalCapacity(allocator, size);
        try slots.appendNTimes(allocator, .{ .nil = {} }, size);

        return .{
            .slots = slots,
            .top = 0,
            .closure = null,
            .varargs = null,
            .pc = 0,
            .prev = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LuaStack) void {
        for (0..self.top) |i| {
            self.slots.items[i].deinit(self.allocator);
        }
        self.slots.deinit(self.allocator);

        if (self.varargs) |varargs| {
            for (varargs) |*v| {
                v.deinit(self.allocator);
            }
        }
    }

    pub fn check(self: *LuaStack, n: i32) void {
        const free = self.slots.items.len - self.top;
        if (@as(usize, @intCast(n)) < free) return;
        for (free..@as(usize, @intCast(n))) |_| {
            self.slots.append(self.allocator, .{ .nil = {} }) catch @panic("stack overflow");
        }
    }

    pub fn push(self: *LuaStack, val: LuaValue) void {
        if (self.top == self.slots.items.len) {
            @panic("stack overflow");
        }
        self.slots.items[self.top] = val;
        self.top += 1;
    }

    pub fn pop(self: *LuaStack) LuaValue {
        if (self.top < 1) {
            @panic("stack underflow!");
        }
        self.top -= 1;
        const val = self.slots.items[self.top];
        self.slots.items[self.top] = .{ .nil = {} };
        return val;
    }

    pub fn absIndex(self: *LuaStack, idx: i32) usize {
        if (idx >= 0) {
            return @intCast(idx);
        }

        return @intCast(idx + @as(i32, @intCast(self.top)) + 1);
    }

    pub fn isValid(self: *LuaStack, idx: i32) bool {
        const absIdx = self.absIndex(idx);
        return absIdx > 0 and absIdx <= self.top;
    }

    pub fn get(self: *LuaStack, idx: i32) LuaValue {
        const absIdx = self.absIndex(idx);
        if (absIdx > 0 and absIdx <= self.top) {
            // Return the value without cloning - caller is responsible for cloning if needed
            return self.slots.items[absIdx - 1];
        }
        return .{ .nil = {} };
    }

    pub fn set(self: *LuaStack, idx: i32, val: LuaValue) void {
        const absIdx = self.absIndex(idx);
        if (absIdx > 0 and absIdx <= self.top) {
            // Free the old value before replacing it
            // This is safe because replace() pops the new value first
            var old_val = self.slots.items[absIdx - 1];
            old_val.deinit(self.allocator);
            self.slots.items[absIdx - 1] = val;
            return;
        }
        @panic("invalid index!");
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

    pub fn pushN(self: *LuaStack, vals: []LuaValue, n: i32) void {
        const n_vals = vals.len;
        const end: usize = if (n < 0) n_vals else @intCast(n);

        for (0..end) |i| {
            if (i < n_vals) {
                self.push(vals[i]);
            } else {
                self.push(.{ .nil = {} });
            }
        }
    }

    pub fn popN(self: *LuaStack, n: i32) []LuaValue {
        const vals = self.allocator.alloc(LuaValue, @as(usize, @intCast(n))) catch @panic("allocation failed");
        var i = n - 1;
        while (i >= 0) : (i -= 1) {
            vals[@as(usize, @intCast(i))] = self.pop();
        }
        return vals;
    }
};
