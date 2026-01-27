const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;

pub const Closure = struct {
    proto: *binchunk.Prototype,
    ref_count: u32,

    pub fn init(proto: *binchunk.Prototype) Closure {
        return .{
            .proto = proto,
            .ref_count = 1,
        };
    }

    pub fn retain(self: *Closure) void {
        self.ref_count += 1;
    }

    pub fn release(self: *Closure, allocator: std.mem.Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            allocator.destroy(self);
        }
    }
};
