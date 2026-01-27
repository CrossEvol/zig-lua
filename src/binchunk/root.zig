const binary_chunk = @import("binary_chunk.zig");

pub const binchunk = struct {
    pub const Header = @import("binary_chunk.zig").Header;
    pub const Tag = @import("binary_chunk.zig").Tag;
    pub const Prototype = @import("binary_chunk.zig").Prototype;
    pub const Upvalue = @import("binary_chunk.zig").Upvalue;
    pub const LocVar = @import("binary_chunk.zig").LocVar;
    pub const undump = @import("binary_chunk.zig").undump;
    pub const reader = @import("reader.zig");
};
