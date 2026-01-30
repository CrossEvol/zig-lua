const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;
const UpValue = @import("closure.zig").UpValue;
const ZigFunction = @import("closure.zig").ZigFunction;

const GC_HEAP_GROW_FACTOR = 2;

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*Object, // List of all objects
    bytes_allocated: usize,
    next_gc: usize,
    gray_stack: std.ArrayList(*Object),

    pub fn init(allocator: std.mem.Allocator) GC {
        return .{
            .allocator = allocator,
            .objects = null,
            .bytes_allocated = 1024 * 1024,
            .next_gc = 0,
            .gray_stack = std.ArrayList(*Object).initCapacity(allocator, 32) catch @panic("allocation failed"),
        };
    }

    pub fn deinit(self: *GC) void {
        var obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            o.deinit(self.allocator);
            self.allocator.destroy(o);
            obj = next;
        }
        self.objects = null;

        // free gray_stack arraylist buffer
        self.gray_stack.deinit(self.allocator);
    }

    pub fn allocateObject(self: *GC, as: Object.AS) LuaValue {
        const object = self.allocator.create(Object) catch @panic("allocation failed for object");
        object.* = .{
            .next = self.objects,
            .marked = false,
            .as = as,
        };
        self.objects = object;
        return .{ .obj = object };
    }

    // Factory methods
    pub fn createLVTable(self: *GC, n_arr: i32, n_rec: i32) LuaValue {
        const lua_table = self.allocator.create(LuaTable) catch @panic("allocation failed for table");
        lua_table.* = LuaTable.init(self.allocator, n_arr, n_rec);
        return self.allocateObject(.{ .lua_table = lua_table });
    }

    pub fn createLVString(self: *GC, s: []const u8) LuaValue {
        const lua_string = self.allocator.create(LuaString) catch @panic("allocation failed for string");
        lua_string.* = LuaString.init(self.allocator, s);
        return self.allocateObject(.{ .string = lua_string });
    }

    pub fn createOpenObjUpValue(self: *GC, val: *LuaValue) LuaValue {
        const upval = UpValue.createOpen(self.allocator, val);
        return self.allocateObject(.{ .upval = upval });
    }

    pub fn createClosedObjUpValue(self: *GC, val: *const LuaValue) LuaValue {
        const upval = UpValue.createClosed(self.allocator, val.*);
        return self.allocateObject(.{ .upval = upval });
    }

    pub fn createLVLuaClosure(self: *GC, proto: *binchunk.Prototype) LuaValue {
        const closure = self.allocator.create(Closure) catch @panic("allocation failed for closure");
        closure.* = Closure.initLuaClosure(self.allocator, proto);
        return self.allocateObject(.{ .closure = closure });
    }

    pub fn createLVZigClosure(self: *GC, f: ZigFunction, n_upvals: i32) LuaValue {
        const closure = self.allocator.create(Closure) catch @panic("allocation failed for closure");
        closure.* = Closure.initZigClosure(self.allocator, f, n_upvals);
        return self.allocateObject(.{ .closure = closure });
    }

    // Core GC methods
    pub fn collectGarbage(self: *GC, roots: *LuaState) void {
        _ = self;
        _ = roots;
    }
};
