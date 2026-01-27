const std = @import("std");

const binchunk = @import("../binchunk/root.zig").binchunk;
const LuaState = @import("lua_state.zig").LuaState;

pub const ZigFunction = *const fn (*LuaState) i32;

pub const Closure = struct {
    proto: ?*binchunk.Prototype, // lua closure
    zig_func: ?ZigFunction, // go closure
    ref_count: u32,

    pub fn init(proto: *binchunk.Prototype) Closure {
        return .{
            .proto = proto,
            .zig_func = null,
            .ref_count = 1,
        };
    }

    pub fn initZigClosure(f: ZigFunction) Closure {
        return .{
            .proto = null,
            .zig_func = f,
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
