const std = @import("std");

const string = []const u8;

pub fn parseInteger(str: string) struct { i64, bool } {
    if (std.fmt.parseInt(i64, str, 10)) |val| {
        return .{ val, true };
    } else |_| {
        return .{ 0, false };
    }
}

pub fn parseFloat(str: string) struct { f64, bool } {
    if (std.fmt.parseFloat(f64, str)) |val| {
        return .{ val, true };
    } else |_| {
        return .{ 0.0, false };
    }
}
