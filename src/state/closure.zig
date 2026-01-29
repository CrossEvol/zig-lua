const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const LuaState = @import("lua_state.zig").LuaState;
const LuaValue = @import("lua_value.zig").LuaValue;

pub const ZigFunction = *const fn (*LuaState) i32;

pub const UpValue = struct {
    val: *LuaValue,
    closed_val: LuaValue = LuaValue.LUA_NIL,
    ref_count: u32,

    pub fn create(allocator: std.mem.Allocator, val: *LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .val = val,
            .ref_count = 1,
            .closed_val = LuaValue.LUA_NIL,
        };
        return upval;
    }

    pub fn createClosed(allocator: std.mem.Allocator, val: LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .val = undefined,
            .ref_count = 1,
            .closed_val = val,
        };
        upval.val = &upval.closed_val;
        return upval;
    }

    pub fn retain(self: *UpValue) void {
        self.ref_count += 1;
    }

    pub fn release(self: *UpValue, allocator: std.mem.Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.closed_val.deinit(allocator);
            allocator.destroy(self);
        }
    }

    pub fn close(self: *UpValue, allocator: std.mem.Allocator) void {
        if (self.val != &self.closed_val) {
            self.closed_val = self.val.*.clone(allocator);
            self.val = &self.closed_val;
        }
    }
};

pub const Closure = struct {
    proto: ?*binchunk.Prototype, // lua closure
    zig_func: ?ZigFunction, // go closure
    upvals: []?*UpValue,
    ref_count: u32,

    pub fn initLuaClosure(allocator: std.mem.Allocator, proto: *binchunk.Prototype) Closure {
        var self: Closure = .{
            .proto = proto,
            .zig_func = null,
            .upvals = &.{},
            .ref_count = 1,
        };

        const n_upvals = proto.upvalues.len;
        if (n_upvals > 0) {
            self.upvals = allocator.alloc(?*UpValue, @intCast(n_upvals)) catch @panic("allocation failed");
            @memset(self.upvals, null);
        }

        return self;
    }

    pub fn initZigClosure(allocator: std.mem.Allocator, f: ZigFunction, n_upvals: i32) Closure {
        var self: Closure = .{
            .proto = null,
            .zig_func = f,
            .upvals = &.{},
            .ref_count = 1,
        };

        if (n_upvals > 0) {
            self.upvals = allocator.alloc(?*UpValue, @intCast(n_upvals)) catch @panic("allocation failed");
            @memset(self.upvals, null);
        }

        return self;
    }

    pub fn retain(self: *Closure) void {
        self.ref_count += 1;
    }

    pub fn release(self: *Closure, allocator: std.mem.Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            for (self.upvals) |maybe_upval| {
                if (maybe_upval) |upval| {
                    upval.release(allocator);
                }
            }

            allocator.free(self.upvals);
            allocator.destroy(self);
        }
    }
};
