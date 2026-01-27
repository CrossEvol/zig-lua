const math = @import("math.zig");
const parser = @import("parser.zig");

pub const number = struct {
    pub const FloatToInteger = math.FloatToInteger;
    pub const IMod = math.IMod;
    pub const FMod = math.FMod;
    pub const IFloorDiv = math.IFloorDiv;
    pub const FFloorDiv = math.FFloorDiv;
    pub const ShiftLeft = math.ShiftLeft;
    pub const ShiftRight = math.ShiftRight;
    pub const parseInteger = parser.parseInteger;
    pub const parseFloat = parser.parseFloat;
};
