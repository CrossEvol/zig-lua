const std = @import("std");

const AstPkg = @import("../ast/root.zig");
const Block = AstPkg.Block;
const LexerPkg = @import("../lexer/root.zig");
const Lexer = LexerPkg.Lexer;
const LexerError = LexerPkg.LexerError;
const parseBlock = @import("parse_block.zig").parseBlock;

const string = []const u8;

pub const ParserError = LexerError || error{ OutOfMemory, InvalidUtf8 };

pub fn parse(allocator: std.mem.Allocator, chunk: string, chunk_name: string) !Block {
    var lexer = Lexer.init(allocator, chunk, chunk_name);
    defer lexer.deinit();

    const block = try parseBlock(&lexer);
    _ = try lexer.nextTokenOfKind(.token_eof);
    return block;
}
