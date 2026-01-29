const std = @import("std");

const LuaType = @import("../api/root.zig").Api.LuaType;
const number = @import("../number/root.zig").number;
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;

const string = []const u8;

pub const LuaValue = union(enum) {
    nil: void,
    bool: bool,
    int64: i64,
    float64: f64,
    string: *LuaString,
    lua_table: *LuaTable,
    closure: *Closure,
    lua_state: *struct {},

    pub const LUA_NIL = LuaValue{ .nil = {} };

    pub const LUA_NIL_REF = &LUA_NIL;

    pub fn deinit(self: *LuaValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| s.release(allocator),
            .lua_table => |t| t.release(allocator),
            .closure => |c| c.release(allocator),
            .lua_state => |s| allocator.destroy(s),
            else => {},
        }
    }

    pub fn clone(self: LuaValue, allocator: std.mem.Allocator) LuaValue {
        _ = allocator;
        return switch (self) {
            .string => |s| {
                s.retain();
                return self;
            },
            .lua_table => |t| {
                t.retain();
                return self;
            },
            .closure => |c| {
                c.retain();
                return self;
            },
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
            .string => |s| std.hash.autoHash(&hasher, s.hash()),
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
            .string => |s| s.hash() == other.string.hash(),
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
        .closure => .lua_t_function,
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
        .string => |x| number.parseFloat(x.data()),
        else => .{ 0, false },
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToInteger(val: LuaValue) struct { i64, bool } {
    return switch (val) {
        .int64 => |x| .{ x, true },
        .float64 => |x| number.FloatToInteger(x),
        .string => |x| _stringToInteger(x.data()),
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

pub fn getMetatable(allocator: std.mem.Allocator, val: LuaValue, ls: *LuaState) ?*LuaTable {
    return switch (val) {
        .lua_table => |t| t.meta_table,
        else => {
            const mt_key = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
            defer allocator.free(mt_key);

            const key = LuaString.create(allocator, mt_key);
            defer key.release(allocator);

            return switch ((ls.registry.get(.{ .string = key }))) {
                .lua_table => |mt| mt,
                else => null,
            };
        },
    };
}

pub fn setMetatable(allocator: std.mem.Allocator, val: LuaValue, mt: ?*LuaTable, ls: *LuaState) void {
    switch (val) {
        .lua_table => |t| {
            if (t.meta_table) |old_mt| {
                old_mt.release(allocator);
            }
            t.meta_table = mt;
        },
        else => {
            const mt_key = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
            defer allocator.free(mt_key);

            const key = LuaString.create(allocator, mt_key);
            defer key.release(allocator);

            if (mt) |t| {
                ls.registry.put(.{ .string = key }, .{ .lua_table = t });
            } else {
                ls.registry.put(.{ .string = key }, LuaValue.LUA_NIL);
            }
        },
    }
}

pub fn getMetafield(allocator: std.mem.Allocator, val: LuaValue, fieldName: string, ls: *LuaState) LuaValue {
    if (getMetatable(allocator, val, ls)) |mt| {
        const key = LuaString.create(allocator, fieldName);
        defer key.release(allocator);
        return mt.get(.{ .string = key });
    }

    return LuaValue.LUA_NIL;
}

pub fn callMetamethod(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, mmName: string, ls: *LuaState) struct { LuaValue, bool } {
    var mm: LuaValue = undefined;
    mm = getMetafield(allocator, a, mmName, ls);
    if (std.meta.activeTag(mm) == .nil) {
        mm = getMetafield(allocator, b, mmName, ls);
        if (std.meta.activeTag(mm) == .nil) {
            return .{ LuaValue.LUA_NIL, false };
        }
    }

    if (ls.stack) |stack| {
        stack.check(4);
        stack.push(mm);
        stack.push(a.clone(allocator));
        stack.push(b.clone(allocator));
        ls.call(2, 1);
        return .{ stack.pop(), true };
    }

    @panic("callMetamethod failed");
}
