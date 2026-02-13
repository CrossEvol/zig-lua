const std = @import("std");

const binchunk = @import("../binchunk/root.zig");
const Closure = @import("closure.zig").Closure;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaTable = @import("lua_table.zig").LuaTable;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;
const ObjectKind = @import("lua_object.zig").ObjectKind;
const UpValue = @import("closure.zig").UpValue;
const ZigFunction = @import("closure.zig").ZigFunction;

const GC_HEAP_GROW_FACTOR = 2;

pub const GC = struct {
    allocator: std.mem.Allocator,
    objects: ?*Object, // List of all objects
    bytes_allocated: usize,
    next_gc: usize,
    gray_stack: std.ArrayList(*Object),
    lua_state: ?*const LuaState,

    pub fn init(allocator: std.mem.Allocator) GC {
        return .{
            .allocator = allocator,
            .objects = null,
            .bytes_allocated = 0,
            .next_gc = 1024 * 1024,
            .gray_stack = std.ArrayList(*Object).initCapacity(allocator, 32) catch @panic("allocation failed"),
            .lua_state = null,
        };
    }

    pub fn deinit(self: *GC) void {
        var obj = self.objects;
        while (obj) |o| {
            const next = o.next;
            defer {
                o.deinit(self.allocator);
                o.destroy(self.allocator);
            }
            obj = next;
        }
        self.objects = null;

        // free gray_stack array-list buffer
        self.gray_stack.deinit(self.allocator);
    }

    fn verifyBytesAllocated(self: *GC, comptime T: type) void {
        self.bytes_allocated += @sizeOf(T);
        if (self.bytes_allocated > self.next_gc) {
            // std.debug.print("gc start, bytes_allocated = {}\n", .{self.bytes_allocated});
            self.collectGarbage();
        }
    }

    // Factory methods
    pub fn createLVTable(self: *GC, n_arr: i32, n_rec: i32) LuaValue {
        const lua_table = self.allocator.create(LuaTable) catch @panic("allocation failed for table");
        lua_table.* = LuaTable.init(self.allocator, n_arr, n_rec);
        self.verifyBytesAllocated(LuaTable);
        lua_table.obj.next = self.objects;
        self.objects = &lua_table.obj;
        return .{ .obj = lua_table.asObj() };
    }

    pub fn createLVString(self: *GC, s: []const u8) LuaValue {
        const lua_string = self.allocator.create(LuaString) catch @panic("allocation failed for string");
        lua_string.* = LuaString.init(self.allocator, s);
        self.verifyBytesAllocated(LuaString);
        lua_string.obj.next = self.objects;
        self.objects = &lua_string.obj;
        return .{ .obj = lua_string.asObj() };
    }

    pub fn createOpenObjUpValue(self: *GC, val: *LuaValue) LuaValue {
        const upval = UpValue.createOpen(self.allocator, val);
        self.verifyBytesAllocated(UpValue);
        upval.obj.next = self.objects;
        self.objects = &upval.obj;
        return .{ .obj = upval.asObj() };
    }

    pub fn createClosedObjUpValue(self: *GC, val: *const LuaValue) LuaValue {
        const upval = UpValue.createClosed(self.allocator, val.*);
        self.verifyBytesAllocated(UpValue);
        upval.obj.next = self.objects;
        self.objects = &upval.obj;
        return .{ .obj = upval.asObj() };
    }

    pub fn createLVLuaClosure(self: *GC, proto: *binchunk.Prototype) LuaValue {
        const closure = self.allocator.create(Closure) catch @panic("allocation failed for closure");
        closure.* = Closure.initLuaClosure(self.allocator, proto);
        self.verifyBytesAllocated(Closure);
        closure.obj.next = self.objects;
        self.objects = &closure.obj;
        return .{ .obj = closure.asObj() };
    }

    pub fn createLVZigClosure(self: *GC, f: ZigFunction, n_upvals: i32) LuaValue {
        const closure = self.allocator.create(Closure) catch @panic("allocation failed for closure");
        closure.* = Closure.initZigClosure(self.allocator, f, n_upvals);
        self.verifyBytesAllocated(Closure);
        closure.obj.next = self.objects;
        self.objects = &closure.obj;
        return .{ .obj = closure.asObj() };
    }

    pub fn createLVLuaState(self: *GC, registry: ?*LuaTable) LuaValue {
        const lua_state = if (registry) |r|
            LuaState.createWithRegistry(self, r) catch @panic("allocation failed for closure")
        else
            LuaState.create(self) catch @panic("allocation failed for closure");
        self.verifyBytesAllocated(LuaState);
        lua_state.obj.next = self.objects;
        self.objects = &lua_state.obj;
        return .{ .obj = lua_state.asObj() };
    }

    fn markRoots(self: *GC) void {
        self.lua_state.?.mark();
    }

    fn sweep(self: *GC) void {
        var prev: ?*Object = null;
        var object = self.objects;
        while (object) |curr| {
            if (curr.marked) {
                curr.marked = false;
                prev = curr;
                object = curr.next;
            } else {
                const next = curr.next;
                object = next;
                if (prev) |p| {
                    p.next = object;
                } else {
                    self.objects = next;
                }

                switch (curr.kind) {
                    .string => self.bytes_allocated -= @sizeOf(LuaString),
                    .lua_table => self.bytes_allocated -= @sizeOf(LuaTable),
                    .closure => self.bytes_allocated -= @sizeOf(Closure),
                    .lua_state => self.bytes_allocated -= @sizeOf(LuaState),
                    .upval => self.bytes_allocated -= @sizeOf(UpValue),
                    .none => {},
                }
                defer {
                    curr.deinit(self.allocator);
                    curr.destroy(self.allocator);
                }
            }
        }

        self.next_gc = self.bytes_allocated * GC_HEAP_GROW_FACTOR;
    }

    // Core GC methods
    pub fn collectGarbage(self: *GC) void {
        self.markRoots();
        self.sweep();
    }
};
