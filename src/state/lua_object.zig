const std = @import("std");

const Closure = @import("closure.zig").Closure;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const UpValue = @import("closure.zig").UpValue;

pub const LuaThread = struct {
    obj: Object,

    pub fn init() LuaThread {
        return .{
            .obj = Object.init(.lua_state),
        };
    }

    // Cast from generic object -> LuaThread(**Downcast**)
    pub fn fromObj(obj: *Object) *LuaThread {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from LuaThread -> generic object(**Upcast**)
    pub fn asObj(self: *LuaThread) *Object {
        return &self.obj;
    }

    pub fn deinit(self: *LuaThread, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn markInner(self: *LuaThread) void {
        _ = self;
    }
};

pub const ObjectKind = enum {
    string,
    lua_table,
    closure,
    lua_state,
    upval,
    none,
};

pub const Object = struct {
    next: ?*Object = null,
    kind: ObjectKind = .none,
    marked: bool = false,

    pub fn init(kind: ObjectKind) Object {
        return .{
            .next = null,
            .kind = kind,
            .marked = false,
        };
    }

    pub fn markObject(self: *Object) void {
        if (self.marked) return;
        self.marked = true;

        switch (self.kind) {
            .lua_table => LuaTable.fromObj(self).markEntries(),
            .closure => Closure.fromObj(self).markUpvals(),
            .upval => UpValue.fromObj(self).markWrappedVals(),
            .lua_state => LuaThread.fromObj(self).markInner(),
            else => {},
        }
    }

    pub fn destroy(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.kind) {
            .string => allocator.destroy(LuaString.fromObj(self)),
            .lua_table => allocator.destroy(LuaTable.fromObj(self)),
            .closure => allocator.destroy(Closure.fromObj(self)),
            .lua_state => allocator.destroy(LuaThread.fromObj(self)),
            .upval => allocator.destroy(UpValue.fromObj(self)),
            .none => {},
        }
    }

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.kind) {
            .string => LuaString.fromObj(self).deinit(allocator),
            .lua_table => {
                var t = LuaTable.fromObj(self);
                t.deinit();
            },
            .closure => Closure.fromObj(self).deinit(allocator),
            .lua_state => LuaThread.fromObj(self).deinit(allocator),
            .upval => UpValue.fromObj(self).deinit(allocator),
            .none => {},
        }
    }
};
