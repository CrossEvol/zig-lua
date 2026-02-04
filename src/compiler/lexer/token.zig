const std = @import("std");

pub const TokenKind = enum {
    token_eof, // end-of-file
    token_vararg, // ...
    token_sep_semi, // ;
    token_sep_comma, // ,
    token_sep_dot, // .
    token_sep_colon, // :
    token_sep_label, // ::
    token_sep_lparen, // (
    token_sep_rparen, // )
    token_sep_lbrack, // [
    token_sep_rbrack, // ]
    token_sep_lcurly, // {
    token_sep_rcurly, // }
    token_op_assign, // =
    token_op_minus, // - (sub or unm)
    token_op_wave, // ~ (bnot or bxor)
    token_op_add, // +
    token_op_mul, // *
    token_op_div, // /
    token_op_idiv, // //
    token_op_pow, // ^
    token_op_mod, // %
    token_op_band, // &
    token_op_bor, // |
    token_op_shr, // >>
    token_op_shl, // <<
    token_op_concat, // ..
    token_op_lt, // <
    token_op_le, // <=
    token_op_gt, // >
    token_op_ge, // >=
    token_op_eq, // ==
    token_op_ne, // ~=
    token_op_len, // #
    token_op_and, // and
    token_op_or, // or
    token_op_not, // not
    token_kw_break, // break
    token_kw_do, // do
    token_kw_else, // else
    token_kw_elseif, // elseif
    token_kw_end, // end
    token_kw_false, // false
    token_kw_for, // for
    token_kw_function, // function
    token_kw_goto, // goto
    token_kw_if, // if
    token_kw_in, // in
    token_kw_local, // local
    token_kw_nil, // nil
    token_kw_repeat, // repeat
    token_kw_return, // return
    token_kw_then, // then
    token_kw_true, // true
    token_kw_until, // until
    token_kw_while, // while
    token_identifier, // identifier
    token_number, // number literal
    token_string, // string literal

};
pub const TOKEN_OP_UNM = TokenKind.token_op_minus; // unary minus
pub const TOKEN_OP_SUB = TokenKind.token_op_minus; // unary minus
pub const TOKEN_OP_BNOT = TokenKind.token_op_wave;
pub const TOKEN_OP_BXOR = TokenKind.token_op_wave;

pub const keywords = std.StaticStringMap(TokenKind).initComptime(.{
    .{ "and", TokenKind.token_op_and },
    .{ "break", TokenKind.token_kw_break },
    .{ "do", TokenKind.token_kw_do },
    .{ "else", TokenKind.token_kw_else },
    .{ "elseif", TokenKind.token_kw_elseif },
    .{ "end", TokenKind.token_kw_end },
    .{ "false", TokenKind.token_kw_false },
    .{ "for", TokenKind.token_kw_for },
    .{ "function", TokenKind.token_kw_function },
    .{ "goto", TokenKind.token_kw_goto },
    .{ "if", TokenKind.token_kw_if },
    .{ "in", TokenKind.token_kw_in },
    .{ "local", TokenKind.token_kw_local },
    .{ "nil", TokenKind.token_kw_nil },
    .{ "not", TokenKind.token_op_not },
    .{ "or", TokenKind.token_op_or },
    .{ "repeat", TokenKind.token_kw_repeat },
    .{ "return", TokenKind.token_kw_return },
    .{ "then", TokenKind.token_kw_then },
    .{ "true", TokenKind.token_kw_true },
    .{ "until", TokenKind.token_kw_until },
    .{ "while", TokenKind.token_kw_while },
});
