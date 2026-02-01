const std = @import("std");
const testing = std.testing;
const expect = testing.expect;

const Object = @import("../state//lua_object.zig").Object;
const LuaString = @import("../state/lua_string.zig").LuaString;
const LuaValue = @import("../state/lua_value.zig").LuaValue;
const Header = @import("binary_chunk.zig").Header;
const LocVar = @import("binary_chunk.zig").LocVar;
const Prototype = @import("binary_chunk.zig").Prototype;
const Tag = @import("binary_chunk.zig").Tag;
const Upvalue = @import("binary_chunk.zig").Upvalue;

const byte = u8;
const uint = u32;
const string = []const u8;

pub const Reader = struct {
    data: []const byte,
    allocator: std.mem.Allocator,

    pub fn init(data: []const byte, allocator: std.mem.Allocator) Reader {
        return Reader{
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn readByte(self: *Reader) byte {
        const b = self.data[0];
        self.data = self.data[1..];
        return b;
    }

    fn readBytes(self: *Reader, n: uint) []const byte {
        const bytes = self.data[0..n];
        self.data = self.data[n..];
        return bytes;
    }

    fn peekBytes(self: *Reader, n: u32) []const byte {
        const bytes = self.data[0..n];
        return bytes;
    }

    fn readUint32(self: *Reader) u32 {
        const bytes = self.peekBytes(4);
        const i = std.mem.readInt(u32, bytes[0..4], .little);
        self.data = self.data[4..];
        return i;
    }

    fn readUint64(self: *Reader) u64 {
        const bytes = self.peekBytes(8);
        const i = std.mem.readInt(u64, bytes[0..8], .little);
        self.data = self.data[8..];
        return i;
    }

    fn readLuaInteger(self: *Reader) i64 {
        return @as(i64, @bitCast(self.readUint64()));
    }

    fn readLuaNumber(self: *Reader) f64 {
        return @as(f64, @bitCast(self.readUint64()));
    }

    fn readString(self: *Reader) string {
        var size = @as(uint, self.readByte());
        if (size == 0) {
            return "";
        }
        if (size == 0xFF) {
            size = @as(uint, @truncate(self.readUint64())); // size_t
        }
        const bytes = self.readBytes(size - 1);
        return @as(string, bytes);
    }

    pub fn checkHeader(self: *Reader) void {
        if (!std.mem.eql(u8, self.readBytes(4), Header.lua_signature)) {
            @panic("not a precompiled chunk!");
        }
        if (self.readByte() != Header.luac_version) {
            @panic("version mismatch!");
        }
        if (self.readByte() != Header.luac_format) {
            @panic("format mismatch!");
        }
        if (!std.mem.eql(u8, self.readBytes(6), Header.luac_data)) {
            @panic("corrupted!");
        }
        if (self.readByte() != Header.cint_size) {
            @panic("int size mismatch!");
        }
        if (self.readByte() != Header.csizet_size) {
            @panic("size_t size mismatch!");
        }
        if (self.readByte() != Header.instruction_size) {
            @panic("instruction size mismatch!");
        }
        if (self.readByte() != Header.lua_integer_size) {
            @panic("lua_Integer size mismatch!");
        }
        if (self.readByte() != Header.lua_number_size) {
            @panic("lua_Number size mismatch!");
        }
        if (self.readLuaInteger() != Header.luac_int) {
            @panic("endianness mismatch!");
        }
        if (self.readLuaNumber() != Header.luac_num) {
            @panic("float format mismatch!");
        }
    }

    pub fn readProto(self: *Reader, parent_source: string) *Prototype {
        var source = self.readString();
        if (std.mem.eql(u8, source, "")) {
            source = parent_source;
        }

        const proto = self.allocator.create(Prototype) catch @panic("allocation failed");
        proto.* = Prototype{
            .source = source,
            .line_defined = self.readUint32(),
            .last_line_defined = self.readUint32(),
            .num_params = self.readByte(),
            .is_vararg = self.readByte(),
            .max_stack_size = self.readByte(),
            .code = self.readCode(),
            .constants = self.readConstants(),
            .upvalues = self.readUpvalues(),
            .protos = self.readProtos(source),
            .line_info = self.readLineInfo(),
            .loc_vars = self.readLocVars(),
            .upvalue_names = self.readUpvalueNames(),
        };
        return proto;
    }

    pub fn readCode(self: *Reader) []const u32 {
        const count = self.readUint32();
        var code = std.ArrayList(u32).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            code.append(self.allocator, self.readUint32()) catch @panic("allocation failed");
        }
        return code.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readConstants(self: *Reader) []LuaValue {
        const count = self.readUint32();
        var constants = std.ArrayList(LuaValue).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            constants.append(self.allocator, self.readConstant()) catch @panic("allocation failed");
        }
        return constants.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readConstant(self: *Reader) LuaValue {
        return switch (self.readByte()) {
            @intFromEnum(Tag.nil) => LuaValue.nil,
            @intFromEnum(Tag.boolean) => LuaValue{ .bool = self.readByte() != 0 },
            @intFromEnum(Tag.integer) => LuaValue{ .int64 = self.readLuaInteger() },
            @intFromEnum(Tag.number) => LuaValue{ .float64 = self.readLuaNumber() },
            @intFromEnum(Tag.short_str), @intFromEnum(Tag.long_str) => {
                const lua_string = LuaString.create(self.allocator, self.readString());
                return .{ .obj = &lua_string.obj };
            },
            else => @panic("corrupted!"),
        };
    }

    pub fn readUpvalues(self: *Reader) []Upvalue {
        const count = self.readUint32();
        var upvalues = std.ArrayList(Upvalue).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            upvalues.append(self.allocator, Upvalue{
                .in_stack = self.readByte(),
                .idx = self.readByte(),
            }) catch @panic("allocation failed");
        }
        return upvalues.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readProtos(self: *Reader, parent_source: string) []const *Prototype {
        const count = self.readUint32();
        var protos = std.ArrayList(*Prototype).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            protos.append(self.allocator, self.readProto(parent_source)) catch @panic("allocation failed");
        }
        return protos.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readLineInfo(self: *Reader) []const uint {
        const count = self.readUint32();
        var line_info = std.ArrayList(uint).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            line_info.append(self.allocator, self.readUint32()) catch @panic("allocation failed");
        }
        return line_info.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readLocVars(self: *Reader) []const LocVar {
        const count = self.readUint32();
        var loc_vars = std.ArrayList(LocVar).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            loc_vars.append(self.allocator, LocVar{
                .var_name = self.readString(),
                .start_pc = self.readUint32(),
                .end_pc = self.readUint32(),
            }) catch @panic("allocation failed");
        }
        return loc_vars.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }

    pub fn readUpvalueNames(self: *Reader) []const string {
        const count = self.readUint32();
        var names = std.ArrayList(string).initCapacity(self.allocator, count) catch @panic("allocation failed");
        for (0..count) |_| {
            names.append(self.allocator, self.readString()) catch @panic("allocation failed");
        }
        return names.toOwnedSlice(self.allocator) catch @panic("allocation failed");
    }
};

test "readInt" {
    try expect(std.mem.readInt(u32, &[_]byte{ 12, 34, 56, 78 }, .big) == 203569230);
    std.debug.print("{}\n", .{@as(i64, 68)});
}
