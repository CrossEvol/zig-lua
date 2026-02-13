const std = @import("std");
const Thread = std.Thread;

pub const Channel = struct {
    mutex: Thread.Mutex,
    cond: Thread.Condition,
    value: i32,
    ready: bool,

    pub fn create(allocator: std.mem.Allocator) !*Channel {
        const ch = try allocator.create(Channel);
        ch.* = .{
            .mutex = .{},
            .cond = .{},
            .value = 0,
            .ready = false,
        };
        return ch;
    }

    pub fn send(self: *Channel, val: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.value = val;
        self.ready = true;
        self.cond.signal();
    }

    pub fn recv(self: *Channel) i32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (!self.ready) {
            self.cond.wait(&self.mutex);
        }
        self.ready = false;
        return self.value;
    }
};
