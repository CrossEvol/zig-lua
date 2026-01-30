const std = @import("std");

const Closure = @import("closure.zig").Closure;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const UpValue = @import("closure.zig").UpValue;

const LuaThread = struct {
    pub fn deinit(self: *LuaThread, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub const Object = struct {
    pub const ObjectTag = enum {
        string,
        lua_table,
        closure,
        lua_state,
        upval,
        none,
    };

    pub const AS = union(ObjectTag) {
        string: *LuaString,
        lua_table: *LuaTable,
        closure: *Closure,
        lua_state: *LuaThread,
        upval: *UpValue,
        none: void,
    };

    next: ?*Object = null,
    marked: bool = false,
    as: AS = .{ .none = {} },

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.as) {
            .string => {
                self.as.string.deinit(allocator);
            },
            .lua_table => {
                self.as.lua_table.deinit();
                allocator.destroy(self.as.lua_table);
            },
            .closure => {
                self.as.closure.deinit(allocator);
            },
            .lua_state => {
                self.as.lua_state.deinit(allocator);
            },
            .upval => {
                self.as.upval.deinit(allocator);
            },
            .none => {},
        }
    }
};
