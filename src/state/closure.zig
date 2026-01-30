const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const LuaState = @import("lua_state.zig").LuaState;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;

pub const ZigFunction = *const fn (*LuaState) i32;

pub const UpValue = struct {
    val: *LuaValue,
    closed_val: LuaValue = LuaValue.LUA_NIL,

    pub fn init(val: *LuaValue) UpValue {
        return .{
            .val = val,
            .closed_val = LuaValue.LUA_NIL,
        };
    }

    pub fn deinit(self: *UpValue, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn createOpen(allocator: std.mem.Allocator, val: *LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .val = val,
            .closed_val = LuaValue.LUA_NIL,
        };
        return upval;
    }

    pub fn createClosed(allocator: std.mem.Allocator, val: LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .val = undefined,
            .closed_val = val,
        };
        upval.val = &upval.closed_val;
        return upval;
    }

    pub fn close(self: *UpValue, allocator: std.mem.Allocator) void {
        _ = allocator;
        if (self.val != &self.closed_val) {
            self.closed_val = self.val.*;
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

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        allocator.free(self.upvals);
        allocator.destroy(self);
    }
};
