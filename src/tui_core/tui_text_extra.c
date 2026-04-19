/*
 * text_extra.c — Auxiliary text-processing functions:
 *   wrap_hard, truncate, truncate_start, truncate_middle.
 *
 * Kept separate from the hot-path text.c (which only contains `wrap`) so
 * that LTCG/LTO keeps text.c's inlining budget unaffected by the larger
 * code in this file.
 *
 * `tui_open_text_extra` expects the tui_core.text table to already
 * be on the top of the Lua stack; it adds its functions to that table and
 * returns 0 (does not push a new value).
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "wcwidth.h"

/* Local growable buffer — same layout as text.c's buf_t; separate static
 * copies are intentional so each TU can be optimised independently. */
typedef struct {
    char   *data;
    size_t  len;
    size_t  cap;
} buf_t;

static void
buf_reset(buf_t *b) { b->len = 0; }

static int
buf_reserve(buf_t *b, size_t extra) {
    if (b->len + extra <= b->cap) return 1;
    size_t ncap = b->cap ? b->cap * 2 : 128;
    while (ncap < b->len + extra) ncap *= 2;
    char *nd = (char *)realloc(b->data, ncap);
    if (!nd) return 0;
    b->data = nd;
    b->cap  = ncap;
    return 1;
}

static int
buf_append(buf_t *b, const char *src, size_t n) {
    if (!buf_reserve(b, n)) return 0;
    memcpy(b->data + b->len, src, n);
    b->len += n;
    return 1;
}

static void
push_buf(lua_State *L, buf_t *b, int idx) {
    lua_pushlstring(L, b->data ? b->data : "", b->len);
    lua_rawseti(L, -2, idx);
    buf_reset(b);
}

/* UTF-8 encoding of U+2026 HORIZONTAL ELLIPSIS (display width 1). */
#define ELLIPSIS     "\xe2\x80\xa6"
#define ELLIPSIS_LEN 3u

/* text.wrap_hard(s, max_cols) -> table of line strings.
 * Like wrap() but always hard-breaks at the column boundary — no whitespace
 * detection. Suitable for code blocks or text where all characters matter. */
static int
l_wrap_hard(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_Integer max_cols = luaL_optinteger(L, 2, 0);

    if (n == 0) {
        lua_createtable(L, 1, 0);
        lua_pushliteral(L, "");
        lua_rawseti(L, -2, 1);
        return 1;
    }
    if (max_cols <= 0) {
        lua_createtable(L, 1, 0);
        lua_pushlstring(L, s, n);
        lua_rawseti(L, -2, 1);
        return 1;
    }

    lua_createtable(L, 0, 0);
    int line_idx = 0;
    buf_t cur = {0};
    int col = 0;
    size_t i = 0;
    const unsigned char *us = (const unsigned char *)s;

    while (i < n) {
        size_t cstart = i;
        size_t clen;
        int cw;
        grapheme_next(us, n, &i, &clen, &cw);
        if (clen == 0) break;

        if (clen == 1 && s[cstart] == '\n') {
            line_idx += 1;
            push_buf(L, &cur, line_idx);
            col = 0;
            continue;
        }

        if (cw < 0) cw = 0;

        if (col + cw > max_cols) {
            line_idx += 1;
            push_buf(L, &cur, line_idx);
            col = 0;
        }

        if (!buf_append(&cur, s + cstart, clen)) {
            free(cur.data);
            return luaL_error(L, "tui_core.text.wrap_hard: out of memory");
        }
        col += cw;
    }

    line_idx += 1;
    push_buf(L, &cur, line_idx);
    free(cur.data);
    return 1;
}

/* Total display width of s[0..n). */
static int
str_display_width(const unsigned char *us, size_t n) {
    size_t i = 0;
    int w = 0;
    while (i < n) {
        size_t clen;
        int cw;
        grapheme_next(us, n, &i, &clen, &cw);
        if (clen == 0) break;
        if (cw > 0) w += cw;
    }
    return w;
}

/* Walk forward in s[0..n) consuming up to `budget` display columns.
 * Returns the byte offset just after the last full cluster that fits. */
static size_t
head_bytes(const char *s, size_t n, int budget) {
    const unsigned char *us = (const unsigned char *)s;
    int col = 0;
    size_t i = 0, last_i = 0;
    while (i < n) {
        size_t clen;
        int cw;
        grapheme_next(us, n, &i, &clen, &cw);
        if (clen == 0) break;
        if (cw < 0) cw = 0;
        if (col + cw > budget) break;
        col += cw;
        last_i = i;
    }
    return last_i;
}

/* Walk forward in s[0..n) until the width from byte offset *pos to end
 * is <= budget.  Returns the byte offset where that suffix begins. */
static size_t
tail_start_bytes(const char *s, size_t n, int total_w, int budget) {
    const unsigned char *us = (const unsigned char *)s;
    int col = 0;
    size_t i = 0;
    while (i < n) {
        if (total_w - col <= budget) return i;
        size_t clen;
        int cw;
        grapheme_next(us, n, &i, &clen, &cw);
        if (clen == 0) break;
        if (cw < 0) cw = 0;
        col += cw;
    }
    return n;
}

/* text.truncate(s, max_cols) -> string
 * Truncates from the end: if s is wider than max_cols, keeps a head that
 * fits in max_cols-1 columns and appends U+2026 HORIZONTAL ELLIPSIS. */
static int
l_truncate(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_Integer max_cols = luaL_optinteger(L, 2, 0);
    const unsigned char *us = (const unsigned char *)s;

    if (max_cols <= 0 || str_display_width(us, n) <= (int)max_cols) {
        lua_pushlstring(L, s, n);
        return 1;
    }

    int budget = (int)max_cols - 1;
    size_t head_end = head_bytes(s, n, budget);

    buf_t out = {0};
    buf_append(&out, s, head_end);
    buf_append(&out, ELLIPSIS, ELLIPSIS_LEN);
    lua_pushlstring(L, out.data ? out.data : "", out.len);
    free(out.data);
    return 1;
}

/* text.truncate_start(s, max_cols) -> string
 * Truncates from the start: if s is wider than max_cols, prepends U+2026 and
 * keeps a tail that fits in max_cols-1 columns. */
static int
l_truncate_start(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_Integer max_cols = luaL_optinteger(L, 2, 0);
    const unsigned char *us = (const unsigned char *)s;

    int total_w = str_display_width(us, n);
    if (max_cols <= 0 || total_w <= (int)max_cols) {
        lua_pushlstring(L, s, n);
        return 1;
    }

    int budget = (int)max_cols - 1;
    size_t tail_start = tail_start_bytes(s, n, total_w, budget);

    buf_t out = {0};
    buf_append(&out, ELLIPSIS, ELLIPSIS_LEN);
    buf_append(&out, s + tail_start, n - tail_start);
    lua_pushlstring(L, out.data ? out.data : "", out.len);
    free(out.data);
    return 1;
}

/* text.truncate_middle(s, max_cols) -> string
 * Truncates from the middle: keeps a head of floor((max_cols-1)/2) columns,
 * appends U+2026, then keeps a tail of ceil((max_cols-1)/2) columns. */
static int
l_truncate_middle(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_Integer max_cols = luaL_optinteger(L, 2, 0);
    const unsigned char *us = (const unsigned char *)s;

    int total_w = str_display_width(us, n);
    if (max_cols <= 0 || total_w <= (int)max_cols) {
        lua_pushlstring(L, s, n);
        return 1;
    }

    int budget    = (int)max_cols - 1;
    int head_bud  = budget / 2;
    int tail_bud  = budget - head_bud;

    size_t hend       = head_bytes(s, n, head_bud);
    size_t tstart     = tail_start_bytes(s, n, total_w, tail_bud);

    buf_t out = {0};
    buf_append(&out, s, hend);
    buf_append(&out, ELLIPSIS, ELLIPSIS_LEN);
    if (tstart < n)
        buf_append(&out, s + tstart, n - tstart);
    lua_pushlstring(L, out.data ? out.data : "", out.len);
    free(out.data);
    return 1;
}

static const luaL_Reg extra_lib[] = {
    { "wrap_hard",       l_wrap_hard       },
    { "truncate",        l_truncate        },
    { "truncate_start",  l_truncate_start  },
    { "truncate_middle", l_truncate_middle },
    { NULL, NULL },
};

/* Add extra text functions to the table already on top of the stack.
 * Called by tui_core.c after tui_open_text pushes the base table. */
int
tui_open_text_extra(lua_State *L) {
    luaL_setfuncs(L, extra_lib, 0);
    return 0;
}
