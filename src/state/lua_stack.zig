const std = @import("std");

const LuaValue = @import("lua_value.zig").LuaValue;

pub const LuaStack = struct {
    slots: std.ArrayList(LuaValue),
    top: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(size: usize, allocator: std.mem.Allocator) !LuaStack {
        var slots = try std.ArrayList(LuaValue).initCapacity(allocator, size);
        try slots.ensureTotalCapacity(allocator, size);
        try slots.appendNTimes(allocator, .{ .nil = {} }, size);

        return .{
            .slots = slots,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LuaStack) void {
        self.slots.deinit(self.allocator);
    }

    pub fn check(self: *LuaStack, n: usize) !void {
        const free = self.slots.items.len - self.top;
        for (free..n) |_| {
            try self.slots.append(self.allocator, .{ .nil = {} });
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

        const t: i32 = @intCast(self.top);
        return @intCast(idx + t + 1);
    }

    pub fn isValid(self: *LuaStack, idx: i32) bool {
        const absIdx = self.absIndex(idx);
        return absIdx > 0 and absIdx <= self.top;
    }

    pub fn get(self: *LuaStack, idx: i32) LuaValue {
        const absIdx = self.absIndex(idx);
        if (absIdx > 0 and absIdx <= self.top) {
            return self.slots.items[absIdx - 1];
        }
        return .{ .nil = {} };
    }

    pub fn set(self: *LuaStack, idx: i32, val: LuaValue) void {
        const absIdx = self.absIndex(idx);
        if (absIdx > 0 and absIdx <= self.top) {
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
};
