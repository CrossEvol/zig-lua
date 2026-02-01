const std = @import("std");

const Object = @import("lua_object.zig").Object;

pub const LuaString = struct {
    obj: Object,
    bytes: []const u8,
    hash64: u64, // cached hash for faster table lookups

    pub fn create(allocator: std.mem.Allocator, s: []const u8) *LuaString {
        const self = allocator.create(LuaString) catch @panic("allocation failed");
        self.* = .{
            .obj = Object.init(.string),
            .bytes = allocator.dupe(u8, s) catch @panic("allocation failed"),
            .hash64 = computeHash(s),
        };
        return self;
    }

    pub fn init(allocator: std.mem.Allocator, s: []const u8) LuaString {
        return .{
            .obj = Object.init(.string),
            .bytes = allocator.dupe(u8, s) catch @panic("allocation failed"),
            .hash64 = computeHash(s),
        };
    }

    pub fn deinit(self: *LuaString, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }

    // Cast from generic object -> LuaString(**Downcast**)
    pub fn fromObj(obj: *Object) *LuaString {
        return @alignCast(@fieldParentPtr("obj", obj));
    }

    // Cast from LuaString -> generic object(**Upcast**)
    pub fn asObj(self: *LuaString) *Object {
        return &self.obj;
    }

    pub fn data(self: *LuaString) []const u8 {
        return self.bytes;
    }

    pub fn hash(self: *LuaString) u64 {
        return self.hash64;
    }

    pub fn len(self: *LuaString) usize {
        return self.bytes.len;
    }

    fn computeHash(s: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(s);
        return hasher.final();
    }
};
