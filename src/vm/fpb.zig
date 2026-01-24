// converts an integer to a "floating point byte", represented as
// (eeeeexxx), where the real value is (1xxx) * 2^(eeeee - 1) if
// eeeee != 0 and (xxx) otherwise.
pub fn intToFb(i: i32) i32 {
    var e: i32 = 0; // exponent
    var x = i;
    if (x < 8) {
        return x;
    }
    while (x >= (8 << 4)) { // coarse steps
        x = (x + 0xf) >> 4; // v = ceil(v / 16)
        e += 4;
    }
    while (x >= (8 << 1)) { // fine steps
        x = (x + 1) >> 1; // v = ceil(v / 2)
        e += 1;
    }
    return ((e + 1) << 3) | (x - 8);
}

// converts back
pub fn fbToInt(x: i32) i32 {
    if (x < 8) {
        return x;
    } else {
        const exponent: u5 = @intCast((x >> 3) - 1);
        return ((x & 7) + 8) << exponent;
    }
}

test "fpb conversion" {
    const std = @import("std");
    const expect = std.testing.expect;

    try expect(intToFb(0) == 0);
    try expect(intToFb(7) == 7);
    try expect(intToFb(8) == 8);
    try expect(intToFb(15) == 15);
    try expect(intToFb(16) == 16);

    try expect(fbToInt(0) == 0);
    try expect(fbToInt(7) == 7);
    try expect(fbToInt(8) == 8);
    try expect(fbToInt(16) == 16);

    // Test round trip for some values
    var i: i32 = 0;
    while (i < 1000) : (i += 1) {
        const fb = intToFb(i);
        const back = fbToInt(fb);
        try expect(back >= i); // Because intToFb is ceiling-based
    }
}
