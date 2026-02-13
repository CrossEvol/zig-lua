const std = @import("std");

const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const UpValue = @import("closure.zig").UpValue;

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
            .lua_state => LuaState.fromObj(self).mark(),
            else => {},
        }
    }

    pub fn destroy(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.kind) {
            .string => allocator.destroy(LuaString.fromObj(self)),
            .lua_table => allocator.destroy(LuaTable.fromObj(self)),
            .closure => allocator.destroy(Closure.fromObj(self)),
            .lua_state => allocator.destroy(LuaState.fromObj(self)),
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
            .lua_state => LuaState.fromObj(self).deinit(allocator),
            .upval => UpValue.fromObj(self).deinit(allocator),
            .none => {},
        }
    }
};
