const std = @import("std");

const LuaType = @import("../api/root.zig").Api.LuaType;
const LuaError = @import("../api/root.zig").Api.LuaError;
const number = @import("../number/root.zig").number;
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const LuaThread = @import("lua_object.zig").LuaThread;
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
            .obj => |obj| switch (obj.kind) {
                .closure => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn isStr(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => |obj| switch (obj.kind) {
                .string => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn isTable(self: *const LuaValue) bool {
        return switch (self.*) {
            .obj => |obj| switch (obj.kind) {
                .lua_table => true,
                else => false,
            },
            else => false,
        };
    }

    pub fn asUpval(self: *const LuaValue) *UpValue {
        return UpValue.fromObj(self.obj);
    }

    pub fn asClosure(self: *const LuaValue) *Closure {
        return Closure.fromObj(self.obj);
    }

    pub fn asTable(self: *const LuaValue) *LuaTable {
        return LuaTable.fromObj(self.obj);
    }

    pub fn asStr(self: *const LuaValue) *LuaString {
        return LuaString.fromObj(self.obj);
    }

    pub fn asThread(self: *const LuaValue) *LuaThread {
        return LuaThread.fromObj(self.obj);
    }

    pub fn mark(self: *const LuaValue) void {
        switch (self.*) {
            .obj => |obj| obj.markObject(),
            else => {},
        }
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
            .obj => |obj| switch (obj.kind) {
                .string => |_| std.hash.autoHash(&hasher, self.asStr().hash()),
                .lua_table => |_| std.hash.autoHash(&hasher, @intFromPtr(self.asTable())),
                .closure => |_| std.hash.autoHash(&hasher, @intFromPtr(self.asClosure())),
                .lua_state => |_| std.hash.autoHash(&hasher, @intFromPtr(self.asThread())),
                .upval => |_| std.hash.autoHash(&hasher, @intFromPtr(self.asUpval())),
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
            .obj => |obj| switch (obj.kind) {
                .string => |_| self.asStr().hash() == other.asStr().hash(),
                .lua_table => |_| self.asTable() == other.asTable(),
                .closure => |_| self.asClosure() == other.asClosure(),
                .lua_state => |_| self.asThread() == other.asThread(),
                .upval => |_| self.asUpval() == other.asUpval(),
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
        .obj => |obj| switch (obj.kind) {
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
        .obj => |obj| switch (obj.kind) {
            .string => |_| number.parseFloat(val.asStr().data()),
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
        .obj => |obj| switch (obj.kind) {
            .string => |_| _stringToInteger(val.asStr().data()),
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
        .obj => |obj| switch (obj.kind) {
            .lua_table => |_| {
                const t = val.asTable();
                t.meta_table = mt;
            },
            else => {
                const mt_s = std.fmt.allocPrint(allocator, "_MT{d}", .{@intFromEnum(typeOf(val))}) catch @panic("allocation failed");
                defer allocator.free(mt_s);

                const key = ls.gc.createLVString(mt_s);

                if (mt) |t| {
                    ls.registry.put(key, .{ .obj = &t.obj });
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
                ls.registry.put(key, .{ .obj = &t.obj });
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

pub fn callMetamethod(allocator: std.mem.Allocator, a: LuaValue, b: LuaValue, mmName: string, ls: *LuaState) LuaError!struct { LuaValue, bool } {
    var mm: LuaValue = undefined;
    mm = getMetafield(allocator, a, mmName, ls);
    if (mm == .nil) {
        mm = getMetafield(allocator, b, mmName, ls);
        if (mm == .nil) {
            return .{ LuaValue.LUA_NIL, false };
        }
    }

    if (ls.stack) |stack| {
        stack.check(4);
        try stack.push(mm);
        try stack.push(a);
        try stack.push(b);
        try ls.call(2, 1);
        return .{ try stack.pop(), true };
    }

    // @panic("callMetamethod failed");
    try ls.pushString("callMetamethod failed");
    return LuaError.Panic;
}
