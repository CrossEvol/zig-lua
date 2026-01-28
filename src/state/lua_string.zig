const std = @import("std");

pub const LuaString = struct {
    bytes: []const u8,
    ref_count: u32,
    hash64: u64, // cached hash for faster table lookups

    pub fn create(allocator: std.mem.Allocator, s: []const u8) *LuaString {
        const self = allocator.create(LuaString) catch @panic("allocation failed");
        self.* = .{
            .bytes = allocator.dupe(u8, s) catch @panic("allocation failed"),
            .ref_count = 1,
            .hash64 = computeHash(s),
        };
        return self;
    }

    pub fn retain(self: *LuaString) void {
        self.ref_count += 1;
    }

    pub fn release(self: *LuaString, allocator: std.mem.Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            allocator.free(self.bytes);
            allocator.destroy(self);
        }
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
