const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const LuaState = @import("lua_state.zig").LuaState;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;
const ObjectKind = @import("lua_object.zig").ObjectKind;

pub const ZigFunction = *const fn (*LuaState) i32;

pub const UpValue = struct {
    obj: Object,
    val: *LuaValue, // borrowed from stack.slots
    closed_val: LuaValue = LuaValue.LUA_NIL, // owned

    pub fn init(val: *LuaValue) UpValue {
        return .{
            .obj = Object.init(.upval),
            .val = val,
            .closed_val = LuaValue.LUA_NIL,
        };
    }

    pub fn deinit(self: *UpValue, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    // Cast from generic object -> UpValue(**Downcast**)
    pub fn fromObj(obj: *Object) *UpValue {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from UpValue -> generic object(**Upcast**)
    pub fn asObj(self: *UpValue) *Object {
        return &self.obj;
    }

    pub fn createOpen(allocator: std.mem.Allocator, val: *LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .obj = Object.init(.upval),
            .val = val,
            .closed_val = LuaValue.LUA_NIL,
        };
        return upval;
    }

    pub fn createClosed(allocator: std.mem.Allocator, val: LuaValue) *UpValue {
        const upval = allocator.create(UpValue) catch @panic("allocation failed");
        upval.* = .{
            .obj = Object.init(.upval),
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

    pub fn markWrappedVals(self: *UpValue) void {
        self.val.mark();
        self.closed_val.mark();
    }
};

pub const Closure = struct {
    obj: Object,
    proto: ?*binchunk.Prototype, // lua closure
    zig_func: ?ZigFunction, // go closure
    upvals: []?*UpValue,
    ref_count: u32,

    pub fn initLuaClosure(allocator: std.mem.Allocator, proto: *binchunk.Prototype) Closure {
        var self: Closure = .{
            .obj = Object.init(.closure),
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
            .obj = Object.init(.closure),
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

    // Cast from generic object -> Closure(**Downcast**)
    pub fn fromObj(obj: *Object) *Closure {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from Closure -> generic object(**Upcast**)
    pub fn asObj(self: *Closure) *Object {
        return &self.obj;
    }

    pub fn markUpvals(self: *Closure) void {
        for (self.upvals) |upval| {
            if (upval) |uv| {
                uv.asObj().markObject();
            }
        }
    }

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        allocator.free(self.upvals);
    }
};
