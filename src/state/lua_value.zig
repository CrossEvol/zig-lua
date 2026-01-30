const std = @import("std");

const LuaType = @import("../api/root.zig").Api.LuaType;
const number = @import("../number/root.zig").number;
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const Object = @import("lua_object.zig").Object;
const UpValue = @import("closure.zig").UpValue;

const string = []const u8;

pub const LuaValueTag = enum {
    nil,
    bool,
    int64,
    float64,
    obj,
};

pub const LuaValue = union(LuaValueTag) {
    nil: void,
    bool: bool,
    int64: i64,
    float64: f64,
    obj: *Object,

    pub const LUA_NIL = LuaValue{ .nil = {} };

    pub const LUA_NIL_REF = &LUA_NIL;

    pub fn deinit(self: *LuaValue, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    pub fn isNil(self: *const LuaValue) bool {
        return switch (self.*) {
            .nil => true,
            else => false,
        };
    }

    pub fn isObj(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => true,
            else => false,
        };
    }

    pub fn isClosure(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => |obj| switch (obj.*.as) {
                .closure => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn isStr(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => |obj| switch (obj.*.as) {
                .string => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn isTable(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => |obj| switch (obj.*.as) {
                .lua_table => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn asUpval(self: *const LuaValue) *UpValue {
        return self.*.obj.*.as.upval;
    }

    pub fn asClosure(self: *const LuaValue) *Closure {
        return self.*.obj.*.as.closure;
    }

    pub fn asTable(self: *const LuaValue) *LuaTable {
        return self.*.obj.*.as.lua_table;
    }

    pub fn asStr(self: *const LuaValue) *LuaString {
        return self.*.obj.*.as.string;
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
            .obj => |obj| switch (obj.*.as) {
                .string => |s| std.hash.autoHash(&hasher, s.hash()),
                .lua_table => |t| std.hash.autoHash(&hasher, @intFromPtr(t)),
                .closure => |c| std.hash.autoHash(&hasher, @intFromPtr(c)),
                .lua_state => |s| std.hash.autoHash(&hasher, @intFromPtr(s)),
                .upval => |uv| std.hash.autoHash(&hasher, @intFromPtr(uv)),
                else => unreachable,
            },
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
            .obj => |obj| switch (obj.*.as) {
                .string => |s| s.hash() == other.obj.*.as.string.hash(),
                .lua_table => |t| t == other.obj.*.as.lua_table,
                .closure => |c| c == other.obj.*.as.closure,
                .lua_state => |s| s == other.obj.*.as.lua_state,
                else => unreachable,
            },
        };
    }
};

pub fn typeOf(val: LuaValue) LuaType {
    return switch (val) {
        .nil => .lua_t_nil,
        .bool => .lua_t_boolean,
        .int64, .float64 => .lua_t_number,
        .obj => |obj| switch (obj.*.as) {
            .string => .lua_t_string,
            .lua_table => .lua_t_table,
            .closure => .lua_t_function,
            else => @panic("todo!"),
        },
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
        .obj => |obj| switch (obj.*.as) {
            .string => |x| number.parseFloat(x.data()),
            else => .{ 0, false },
        },
        else => .{ 0, false },
    };
}

// http://www.lua.org/manual/5.3/manual.html#3.4.3
pub fn convertToInteger(val: LuaValue) struct { i64, bool } {
    return switch (val) {
        .int64 => |x| .{ x, true },
        .float64 => |x| number.FloatToInteger(x),
        .obj => |obj| switch (obj.*.as) {
            .string => |x| _stringToInteger(x.data()),
            else => .{ 0, false },
        },
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
    const ok = val.isTable();
    if (ok) {
        const t = val.asTable();
        return t.meta_table;
    }

    const mt_s = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
    defer allocator.free(mt_s);

    const key = ls.gc.createLVString(mt_s);
    const mt = (ls.registry.get(key));
    if (!mt.isNil()) {
        return mt.asTable();
    }
    return null;
}

pub fn setMetatable(allocator: std.mem.Allocator, val: LuaValue, mt: ?*LuaTable, ls: *LuaState) void {
    switch (val) {
        .obj => |obj| switch (obj.*.as) {
            .lua_table => |t| {
                t.meta_table = mt;
            },
            else => {
                const mt_s = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
                defer allocator.free(mt_s);

                const key = ls.gc.createLVString(mt_s);

                if (mt) |t| {
                    const lv_table = ls.gc.allocateObject(.{ .lua_table = t });
                    ls.registry.put(key, lv_table);
                } else {
                    ls.registry.put(key, LuaValue.LUA_NIL);
                }
            },
        },
        else => {
            const mt_s = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
            defer allocator.free(mt_s);

            const key = ls.gc.createLVString(mt_s);

            if (mt) |t| {
                const lv_table = ls.gc.allocateObject(.{ .lua_table = t });
                ls.registry.put(key, lv_table);
            } else {
                ls.registry.put(key, LuaValue.LUA_NIL);
            }
        },
    }
}

pub fn getMetafield(allocator: std.mem.Allocator, val: LuaValue, fieldName: string, ls: *LuaState) LuaValue {
    if (getMetatable(allocator, val, ls)) |mt| {
        const key = ls.gc.createLVString(fieldName);
        return mt.get(key);
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
        stack.push(a);
        stack.push(b);
        ls.call(2, 1);
        return .{ stack.pop(), true };
    }

    @panic("callMetamethod failed");
}
