const std = @import("std");

const number = @import("number");

const LuaTable = @import("lua_table.zig").LuaTable;
const LuaType = @import("consts.zig").LuaType;

const string = []const u8;

pub const LuaValue = union(enum) {
    nil: void,
    bool: bool,
    int64: i64,
    float64: f64,
    string: string,
    lua_table: *LuaTable,
    closure: *struct {},
    lua_state: *struct {},

    pub fn deinit(self: *LuaValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .lua_table => |t| {
                t.deinit();
                allocator.destroy(t);
            },
            .closure => |c| allocator.destroy(c),
            .lua_state => |s| allocator.destroy(s),
            else => {},
        }
    }

    pub fn clone(self: LuaValue, allocator: std.mem.Allocator) LuaValue {
        return switch (self) {
            .string => |s| .{ .string = allocator.dupe(u8, s) catch @panic("clone allocation failed") },
            else => self,
        };
    }

    pub fn hash(self: LuaValue) u64 {
        var hasher = std.hash.Wyhash.init(0);

        std.hash.autoHash(&hasher, std.meta.activeTag(self));

        switch (self) {
            .nil => {},
            .bool => |b| std.hash.autoHash(&hasher, b),
            .int64 => |i| std.hash.autoHash(&hasher, i),
            .float64 => |f| {
                const bits: u64 = @bitCast(f);
                std.hash.autoHash(&hasher, bits);
            },
            .string => |s| hasher.update(s),
            .lua_table => |t| std.hash.autoHash(&hasher, @intFromPtr(t)),
            .closure => |c| std.hash.autoHash(&hasher, @intFromPtr(c)),
            .lua_state => |s| std.hash.autoHash(&hasher, @intFromPtr(s)),
        }
        return hasher.final();
    }

    pub fn eql(self: LuaValue, other: LuaValue) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) {
            return false;
        }

        return switch (self) {
            .nil => true,
            .bool => |b| b == other.bool,
            .int64 => |i| i == other.int64,
            .float64 => |f| f == other.float64,
            .string => |s| std.mem.eql(u8, s, other.string),
            .lua_table => |t| t == other.lua_table,
            .closure => |c| c == other.closure,
            .lua_state => |s| s == other.lua_state,
        };
    }
};

pub fn typeOf(val: LuaValue) LuaType {
    return switch (val) {
        .nil => .lua_t_nil,
        .bool => .lua_t_boolean,
        .int64, .float64 => .lua_t_number,
        .string => .lua_t_string,
        .lua_table => .lua_t_table,
        else => @panic("todo!"),
    };
}

pub fn convertToBoolean(val: LuaValue) bool {
    return switch (val) {
        .nil => false,
        .bool => |x| x,
        else => true,
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToFloat(val: LuaValue) struct { f64, bool } {
    return switch (val) {
        .int64 => |x| .{ @floatFromInt(x), true },
        .float64 => |x| .{ x, true },
        .string => |x| number.parseFloat(x),
        else => .{ 0, false },
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToInteger(val: LuaValue) struct { i64, bool } {
    return switch (val) {
        .int64 => |x| .{ x, true },
        .float64 => |x| number.FloatToInteger(x),
        .string => |x| _stringToInteger(x),
        else => .{ 0, false },
    };
}

fn _stringToInteger(s: string) struct { i64, bool } {
    const i, var ok = number.parseInteger(s);
    if (ok) {
        return .{ i, true };
    }
    const f, ok = number.parseFloat(s);
    if (ok) {
        return number.FloatToInteger(f);
    }
    return .{ 0, false };
}
