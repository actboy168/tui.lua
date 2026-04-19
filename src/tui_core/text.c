/*
 * text.c — Soft-wrap UTF-8 strings to a display-column budget.
 *
 * Exposes one Lua function under tui_core.text:
 *
 *   wrap(s, max_cols) -> { line1, line2, ... }
 *
 * Walks grapheme clusters (via grapheme_next) so combining marks, ZWJ
 * sequences, VS16-promoted emoji, RI flags and Hangul jamo occupy the
 * column budget consistently with screen.draw_line. Breaks on whitespace
 * when possible; falls back to a hard break when no whitespace fits.
 * Hard newlines in the input always split.
 *
 * Rationale for living in C:
 *   - Layout re-wraps the same text whenever width changes, so this is on
 *     the hot path.
 *   - Walking bytes one grapheme cluster at a time from Lua would require
 *     one C→Lua→C round trip per cluster; doing the whole scan in C is an
 *     order of magnitude cheaper.
 *   - Implementation is pure UTF-8 + wcwidth — no product logic lives here.
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "wcwidth.h"

/* Growable byte buffer for building the "current line" before flushing it
 * to the result table. Reused across lines so we only allocate on outliers. */
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

/* Trim one trailing space/tab byte if present. Safe for UTF-8 because
 * ' ' and '\t' are single-byte ASCII and never appear as trailing bytes
 * of a multibyte sequence. */
static void
buf_trim_trailing_space(buf_t *b) {
    if (b->len > 0) {
        char c = b->data[b->len - 1];
        if (c == ' ' || c == '\t') b->len -= 1;
    }
}

static int
is_space_byte(unsigned char c) { return c == ' ' || c == '\t'; }

/* text.wrap(s, max_cols) -> table of line strings. */
static int
l_wrap(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_Integer max_cols = luaL_optinteger(L, 2, 0);

    /* Empty / no-budget fast paths — match Lua reference behavior. */
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

    /* Column tracking. We must also remember the state at the last
     * whitespace boundary so we can retroactively split there. */
    int col = 0;
    /* Byte offset inside `cur` where the wrap-candidate whitespace was
     * appended (offset of the space's first byte). -1 = no candidate. */
    ptrdiff_t last_space_off = -1;
    /* Column count *before* the whitespace was added. Used to recompute
     * the tail column after we split. */
    int last_space_col = 0;

    size_t i = 0;
    const unsigned char *us = (const unsigned char *)s;

    while (i < n) {
        size_t cstart = i;
        size_t clen;
        int cw;
        grapheme_next(us, n, &i, &clen, &cw);
        if (clen == 0) break;

        /* Hard newline: flush current line (keeping any trailing space so
         * the user's explicit newline boundary is crisp). */
        if (clen == 1 && s[cstart] == '\n') {
            line_idx += 1;
            push_buf(L, &cur, line_idx);
            col = 0;
            last_space_off = -1;
            last_space_col = 0;
            continue;
        }

        if (cw < 0) cw = 0;

        /* Remember this position if the cluster is a wrap-candidate space.
         * We record the byte offset *before* the space is appended. */
        int is_space = (clen == 1 && is_space_byte((unsigned char)s[cstart]));
        if (is_space) {
            last_space_off = (ptrdiff_t)cur.len;
            last_space_col = col;
        }

        if (col + cw > max_cols) {
            if (last_space_off > 0) {
                /* Split at the last whitespace: head = everything up to
                 * but not including the space (and trim a trailing space
                 * from head just in case the space was the last byte).
                 * Tail = bytes after the space, becomes the next line's
                 * prefix. */
                size_t head_end = (size_t)last_space_off;
                /* Head line. */
                lua_pushlstring(L, cur.data, head_end);
                /* Tail may be empty — that's fine. */
                size_t tail_start = head_end + 1;  /* skip the space byte */
                size_t tail_len   = cur.len - tail_start;
                line_idx += 1;
                lua_rawseti(L, -2, line_idx);

                /* Rebuild cur as the tail bytes. */
                if (tail_len > 0) {
                    memmove(cur.data, cur.data + tail_start, tail_len);
                }
                cur.len = tail_len;

                /* Tail column = (col at split) - (col up through the space).
                 * Everything after the space advanced col by (col -
                 * (last_space_col + 1)) so that's the new tail width. */
                col = col - (last_space_col + 1);
                last_space_off = -1;
                last_space_col = 0;
            } else {
                /* Hard break with no whitespace candidate. Flush cur and
                 * restart. Current cluster will be appended fresh below. */
                line_idx += 1;
                push_buf(L, &cur, line_idx);
                col = 0;
                last_space_off = -1;
                last_space_col = 0;
            }
        }

        if (!buf_append(&cur, s + cstart, clen)) {
            free(cur.data);
            return luaL_error(L, "tui_core.text.wrap: out of memory");
        }
        col += cw;
    }

    /* Final line — always emit, even if empty, so callers see at least one. */
    line_idx += 1;
    push_buf(L, &cur, line_idx);

    free(cur.data);
    return 1;
}

static const luaL_Reg lib[] = {
    { "wrap", l_wrap },
    { NULL, NULL },
};

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

    size_t head_end   = head_bytes(s, n, head_bud);
    size_t tail_start = tail_start_bytes(s, n, total_w, tail_bud);

    buf_t out = {0};
    buf_append(&out, s, head_end);
    buf_append(&out, ELLIPSIS, ELLIPSIS_LEN);
    if (tail_start < n)
        buf_append(&out, s + tail_start, n - tail_start);
    lua_pushlstring(L, out.data ? out.data : "", out.len);
    free(out.data);
    return 1;
}

static const luaL_Reg lib2[] = {
    { "wrap",            l_wrap            },
    { "wrap_hard",       l_wrap_hard       },
    { "truncate",        l_truncate        },
    { "truncate_start",  l_truncate_start  },
    { "truncate_middle", l_truncate_middle },
    { NULL, NULL },
};

LUAMOD_API int
luaopen_tui_core_text(lua_State *L) {
    luaL_newlib(L, lib2);
    return 1;
}
