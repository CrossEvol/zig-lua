const std = @import("std");
const math = std.math;

const number = @import("../number/root.zig").number;
const LuaState = @import("lua_state.zig").LuaState;
const LuaString = @import("lua_string.zig").LuaString;
const LuaValue = @import("lua_value.zig").LuaValue;
const Object = @import("lua_object.zig").Object;

const string = []const u8;

pub const LuaTable = struct {
    obj: Object,
    allocator: std.mem.Allocator,
    meta_table: ?*LuaTable,
    arr: std.ArrayList(LuaValue),
    map: std.HashMap(
        LuaValue,
        LuaValue,
        LuaValueContext,
        std.hash_map.default_max_load_percentage,
    ),
    keys: ?std.HashMap(
        LuaValue,
        LuaValue,
        LuaValueContext,
        std.hash_map.default_max_load_percentage,
    ), // used by next()
    last_key: LuaValue, // used by next()
    changed: bool, // used by next()

    pub fn markEntries(self: *LuaTable) void {
        if (self.meta_table) |mt| {
            mt.asObj().markObject();
        }

        for (self.arr.items) |*item| {
            item.mark();
        }

        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.key_ptr.*.mark();
            entry.value_ptr.*.mark();
        }

        if (self.keys) |keys| {
            it = keys.iterator();
            while (it.next()) |entry| {
                entry.key_ptr.*.mark();
                entry.value_ptr.*.mark();
            }
        }
    }

    pub fn init(allocator: std.mem.Allocator, n_arr: i32, n_rec: i32) LuaTable {
        const arr = std.ArrayList(LuaValue).initCapacity(
            allocator,
            @intCast(if (n_arr > 0) n_arr else 0),
        ) catch @panic("allocation failed!");

        var map = std.HashMap(
            LuaValue,
            LuaValue,
            LuaValueContext,
            std.hash_map.default_max_load_percentage,
        ).init(allocator);
        if (n_rec > 0) {
            map.ensureTotalCapacity(@intCast(n_rec)) catch @panic("allocation failed!");
        }

        return .{
            .obj = Object.init(.lua_table),
            .allocator = allocator,
            .meta_table = null,
            .arr = arr,
            .map = map,
            .keys = null,
            .last_key = LuaValue.LUA_NIL,
            .changed = false,
        };
    }

    pub fn deinit(self: *LuaTable) void {
        // free array partition
        self.arr.deinit(self.allocator);

        // free hashmap partition
        self.map.deinit();

        // free keys
        if (self.keys) |*keys| {
            keys.deinit();
        }
    }

    // Cast from generic object -> LuaTable(**Downcast**)
    pub fn fromObj(obj: *Object) *LuaTable {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from LuaTable -> generic object(**Upcast**)
    pub fn asObj(self: *LuaTable) *Object {
        return &self.obj;
    }

    /// Get a value from the table.
    /// Return a clone (new ownership) of the value.
    /// The caller is responsible for calling .deinit() on the returned value.
    pub fn get(self: *LuaTable, key: LuaValue) LuaValue {
        const k1 = _floatToInteger(key);
        if (k1 == .int64) {
            const idx = k1.int64;
            if (idx >= 1 and idx <= @as(i64, @intCast(self.arr.items.len))) {
                return self.arr.items[@as(usize, @intCast(idx - 1))];
            }
        }
        if (self.map.get(k1)) |v| {
            return v;
        } else {
            return LuaValue.LUA_NIL;
        }
    }

    /// Put a key-value pair into the table.
    /// Clones both key and value to ensure the table has full ownership
    /// of its internal data. The caller still owns the passed arguments.
    pub fn put(self: *LuaTable, key: LuaValue, val: LuaValue) void {
        if (key == .nil) {
            @panic("table index is nil!");
        }
        if (key == .float64 and math.isNan(key.float64)) {
            @panic("table index is NaN!");
        }

        self.changed = true;

        const k = _floatToInteger(key);
        if (k == .int64) {
            const idx = k.int64;
            if (idx >= 1) {
                const arr_len: i64 = @intCast(self.arr.items.len);
                if (idx <= arr_len) {
                    self.arr.items[@as(usize, @intCast(idx - 1))] = val;
                    if (idx == arr_len and val == .nil) {
                        self._shrinkArray();
                    }
                    return;
                }
                if (idx == arr_len + 1) {
                    if (self.map.fetchRemove(k)) |_| {}
                    if (val != .nil) {
                        self.arr.append(self.allocator, val) catch @panic("allocation failed!");
                        self._expandArray();
                    }
                    return;
                }
            }
        }
        if (val != .nil) {
            if (self.map.capacity() == 0) {
                self.map.ensureTotalCapacity(8) catch @panic("allocation failed!");
            }
            // Check if key already exists and free old value if so
            if (self.map.fetchRemove(k)) |_| {}
            self.map.put(k, val) catch @panic("table-put failed!");
        } else {
            if (self.map.fetchRemove(k)) |_| {}
        }
    }

    pub fn hasMetaField(self: *LuaTable, fieldName: string, ls: *LuaState) bool {
        if (self.meta_table) |mt| {
            const key = ls.gc.createLVString(fieldName);
            return mt.get(key) != .nil;
        } else {
            return false;
        }
    }

    pub fn len(self: *LuaTable) usize {
        return self.arr.items.len;
    }

    fn _floatToInteger(key: LuaValue) LuaValue {
        if (key == .float64) {
            const i, const ok = number.FloatToInteger(key.float64);
            if (ok) {
                return .{ .int64 = i };
            }
        }

        return key;
    }

    fn _shrinkArray(self: *LuaTable) void {
        // find the first non-nil element from back to front
        var i = self.arr.items.len;
        while (i > 0) {
            i -= 1;
            if (self.arr.items[i] != .nil) {
                const new_len = i + 1;
                self.arr.shrinkRetainingCapacity(new_len);
                return;
            }
        }

        self.arr.clearRetainingCapacity();
    }

    fn _expandArray(self: *LuaTable) void {
        // move the continuous element indices from map to array
        var idx: i64 = @intCast(self.arr.items.len + 1);

        while (true) {
            const key = LuaValue{ .int64 = idx };

            if (self.map.fetchRemove(key)) |kv| {
                self.arr.append(self.allocator, kv.value) catch {
                    self.map.put(kv.key, kv.value) catch @panic("allocation failed!");
                    break;
                };

                idx += 1;
            } else {
                break;
            }
        }
    }

    pub fn nextKey(self: *LuaTable, key: LuaValue) LuaValue {
        if (self.keys == null or (key == .nil and self.changed)) {
            self.initKeys();
            self.changed = false;
        }

        const next_key = self.keys.?.get(key) orelse LuaValue.LUA_NIL;
        if (next_key == .nil and key != .nil and !key.eql(self.last_key)) {
            @panic("invalid key to 'next'");
        }
        return next_key;
    }

    fn initKeys(self: *LuaTable) void {
        if (self.keys) |*keys| {
            keys.deinit();
        }
        const keys = std.HashMap(
            LuaValue,
            LuaValue,
            LuaValueContext,
            std.hash_map.default_max_load_percentage,
        ).init(self.allocator);
        self.keys = keys;

        var key = LuaValue.LUA_NIL;
        for (0.., self.arr.items) |i, v| {
            if (v != .nil) {
                const next_key: LuaValue = .{ .int64 = @intCast(i + 1) };
                self.keys.?.put(key, next_key) catch @panic("allocation failed!");
                key = next_key;
            }
        }
        var it = self.map.iterator();
        while (it.next()) |entry| {
            const k = entry.key_ptr.*;
            const v = entry.value_ptr.*;
            if (v != .nil) {
                self.keys.?.put(key, k) catch @panic("allocation failed!");
                key = k;
            }
        }
        self.last_key = key;
    }
};

const LuaValueContext = struct {
    pub fn hash(_: LuaValueContext, key: LuaValue) u64 {
        return key.hash();
    }

    pub fn eql(_: LuaValueContext, a: LuaValue, b: LuaValue) bool {
        return LuaValue.eql(a, b);
    }
};
