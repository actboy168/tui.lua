/*
 * screen.c — cell buffer + double-buffered ANSI diff renderer.
 *
 * Exposed Lua API (registered under `tui_core.screen`):
 *
 *     ud = screen.new(w, h)
 *     w, h = screen.size(ud)
 *              screen.resize(ud, w, h)
 *              screen.invalidate(ud)
 *              screen.clear(ud)
 *              screen.put(ud, x, y, s, cw)            -- grapheme cluster + width
 *              screen.put_border(ud, x, y, w, h, style)
 *              screen.draw_line(ud, x, y, text, max_w)
 *     ansi =  screen.diff(ud)
 *     rows =  screen.rows(ud)                         -- array of h strings
 *
 * Design notes: see docs/roadmap.md "渲染后端下沉到 C" section.
 *
 * Stage 9 skeleton scope (this file, first pass):
 *   - cell_t 12-byte with inline[8] / slab union
 *   - screen_t double-buffer + slab pair + row ring pool fields
 *   - new / size / resize / invalidate / clear / __gc
 *   - put (INLINE path only; slab path returns error for now)
 *   - diff (first-frame full-redraw + naive per-cell comparison, no merge)
 *   - rows (naive lua_pushlstring, ring pool + pushexternalstring come later)
 *   - put_border / draw_line / segment-merge / slab path: later steps
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "wcwidth.h"

/* ── cell / slab / screen structs ─────────────────────────────── */

/* SGR attribute layout (Stage 10):
 *
 *   fg_bg:  high nibble = fg (0..15 = ANSI 16-color), low nibble = bg (0..15).
 *           Values 0..7 map to normal 30-37 / 40-47; 8..15 map to bright
 *           90-97 / 100-107. Default (no-color) is tracked by the is_default
 *           bits in `attrs` — fg_bg bits are ignored when that bit is set.
 *
 *   attrs:  bit0 bold     bit1 dim       bit2 underline  bit3 inverse
 *           bit4 fg_def   bit5 bg_def    bit6..7 reserved
 *           When bit4/bit5 is set, the corresponding nibble in fg_bg must
 *           be treated as "terminal default" regardless of its value. The
 *           default-filled cell is `attrs = ATTR_DEFAULT_STYLE` = 0x30.
 */
#define ATTR_BOLD       0x01u
#define ATTR_DIM        0x02u
#define ATTR_UNDERLINE  0x04u
#define ATTR_INVERSE    0x08u
#define ATTR_FG_DEFAULT 0x10u
#define ATTR_BG_DEFAULT 0x20u
#define ATTR_STYLE_MASK (ATTR_BOLD | ATTR_DIM | ATTR_UNDERLINE | ATTR_INVERSE)
#define ATTR_DEFAULT    (ATTR_FG_DEFAULT | ATTR_BG_DEFAULT)

typedef struct {
    union {
        uint8_t inline_bytes[8];
        struct {
            uint32_t slab_off;
            uint16_t slab_len;
            uint8_t  _pad[2];
        } ext;
    } u;
    uint8_t len;    /* 1..8 inline, 0xFF slab, 0 WIDE_TAIL */
    uint8_t width;  /* 0 tail, 1 narrow, 2 wide head */
    uint8_t fg_bg;  /* high nibble fg, low nibble bg (see ATTR_*_DEFAULT) */
    uint8_t attrs;  /* ATTR_* bitmask */
} cell_t;

/* Compile-time guard: must stay 12 bytes / 4-byte alignment. */
#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(cell_t) == 12, "cell_t must be 12 bytes");
#endif

typedef struct {
    uint8_t *buf;
    uint32_t size;
    uint32_t cap;
} slab_t;

#define ROW_POOL_GEN 4

typedef struct {
    uint8_t *buf;
    uint32_t cap;
} row_buf_t;

typedef struct {
    row_buf_t bufs[ROW_POOL_GEN];
    int       gen;
} row_pool_t;

typedef struct {
    int w, h;
    cell_t *next;
    cell_t *prev;
    slab_t  next_slab;
    slab_t  prev_slab;
    int     prev_valid;
    row_pool_t rows;
} screen_t;

#define SCREEN_MT "tui_core.screen"

/* ── helpers ──────────────────────────────────────────────────── */

static inline cell_t *
cell_at(cell_t *buf, int w, int x, int y) {
    return &buf[y * w + x];
}

static inline void
cell_set_space(cell_t *c) {
    c->u.inline_bytes[0] = ' ';
    c->len   = 1;
    c->width = 1;
    c->fg_bg = 0;
    c->attrs = ATTR_DEFAULT;
}

static void
fill_space(cell_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        cell_t *c = &buf[i];
        /* zero the 12 bytes deterministically, then set space. */
        memset(c, 0, sizeof(*c));
        c->u.inline_bytes[0] = ' ';
        c->len = 1;
        c->width = 1;
        c->attrs = ATTR_DEFAULT;
    }
}

static inline void
cell_bytes(const cell_t *c, const slab_t *slab,
           const uint8_t **out_p, size_t *out_len) {
    if (c->len == 0xFF) {
        *out_p   = slab->buf + c->u.ext.slab_off;
        *out_len = c->u.ext.slab_len;
    } else {
        *out_p   = c->u.inline_bytes;
        *out_len = c->len;
    }
}

static inline int
cell_eq(const cell_t *a, const slab_t *slab_a,
        const cell_t *b, const slab_t *slab_b) {
    if (a->len != b->len || a->width != b->width) return 0;
    if (a->len == 0)    return 1;                  /* both WIDE_TAIL */
    if (a->fg_bg != b->fg_bg || a->attrs != b->attrs) return 0;
    if (a->len == 0xFF) {
        if (a->u.ext.slab_len != b->u.ext.slab_len) return 0;
        return memcmp(slab_a->buf + a->u.ext.slab_off,
                      slab_b->buf + b->u.ext.slab_off,
                      a->u.ext.slab_len) == 0;
    }
    return memcmp(a->u.inline_bytes, b->u.inline_bytes, a->len) == 0;
}

static inline void
slab_reset(slab_t *s) { s->size = 0; }

static uint32_t
slab_push(slab_t *s, const uint8_t *p, uint32_t n) {
    if (s->size + n > s->cap) {
        uint32_t need = s->size + n;
        uint32_t ncap = s->cap ? s->cap * 2 : 256;
        while (ncap < need) ncap *= 2;
        uint8_t *nb = (uint8_t *)realloc(s->buf, ncap);
        if (!nb) return 0xFFFFFFFFu;  /* caller must handle */
        s->buf = nb;
        s->cap = ncap;
    }
    uint32_t off = s->size;
    memcpy(s->buf + off, p, n);
    s->size += n;
    return off;
}

static void
slab_free(slab_t *s) {
    free(s->buf);
    s->buf = NULL;
    s->size = 0;
    s->cap = 0;
}

static void
row_pool_free(row_pool_t *p) {
    for (int i = 0; i < ROW_POOL_GEN; i++) {
        free(p->bufs[i].buf);
        p->bufs[i].buf = NULL;
        p->bufs[i].cap = 0;
    }
    p->gen = 0;
}

static screen_t *
check_screen(lua_State *L, int idx) {
    return (screen_t *)luaL_checkudata(L, idx, SCREEN_MT);
}

/* Style packing lives in Lua (tui/sgr.lua:pack_bytes). Callers pass the
 * two packed bytes (fg_bg, attrs) directly; this module consumes them
 * unchanged. See ATTR_* macros above for the bit layout. */

/* ── Lua API: new / size / resize / invalidate / clear / __gc ── */

static int
lnew(lua_State *L) {
    lua_Integer w = luaL_checkinteger(L, 1);
    lua_Integer h = luaL_checkinteger(L, 2);
    luaL_argcheck(L, w > 0 && w < 100000, 1, "width out of range");
    luaL_argcheck(L, h > 0 && h < 100000, 2, "height out of range");

    screen_t *s = (screen_t *)lua_newuserdatauv(L, sizeof(screen_t), 0);
    memset(s, 0, sizeof(*s));
    s->w = (int)w;
    s->h = (int)h;
    size_t ncells = (size_t)s->w * (size_t)s->h;
    s->next = (cell_t *)calloc(ncells, sizeof(cell_t));
    s->prev = (cell_t *)calloc(ncells, sizeof(cell_t));
    if (!s->next || !s->prev) {
        free(s->next); free(s->prev);
        s->next = s->prev = NULL;
        luaL_error(L, "screen.new: out of memory");
    }
    fill_space(s->next, (int)ncells);
    fill_space(s->prev, (int)ncells);
    s->prev_valid = 0;

    luaL_getmetatable(L, SCREEN_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int
lsize(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    lua_pushinteger(L, s->w);
    lua_pushinteger(L, s->h);
    return 2;
}

static int
lresize(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    lua_Integer w = luaL_checkinteger(L, 2);
    lua_Integer h = luaL_checkinteger(L, 3);
    luaL_argcheck(L, w > 0 && w < 100000, 2, "width out of range");
    luaL_argcheck(L, h > 0 && h < 100000, 3, "height out of range");

    size_t ncells = (size_t)w * (size_t)h;
    cell_t *nn = (cell_t *)realloc(s->next, ncells * sizeof(cell_t));
    cell_t *np = (cell_t *)realloc(s->prev, ncells * sizeof(cell_t));
    if (!nn || !np) luaL_error(L, "screen.resize: out of memory");
    s->next = nn;
    s->prev = np;
    s->w = (int)w;
    s->h = (int)h;
    fill_space(s->next, (int)ncells);
    fill_space(s->prev, (int)ncells);
    slab_reset(&s->next_slab);
    slab_reset(&s->prev_slab);
    /* row pool buffers invalidated: drop them so next rows() reallocates. */
    row_pool_free(&s->rows);
    s->prev_valid = 0;
    return 0;
}

static int
linvalidate(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    s->prev_valid = 0;
    return 0;
}

static int
lclear(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    fill_space(s->next, s->w * s->h);
    slab_reset(&s->next_slab);
    return 0;
}

/* ── Lua API: put ─────────────────────────────────────────────── */

/* Internal cell writer used by lput / draw_line / put_border.
 * x,y 0-based. Length-0 strings are rejected. Returns 1 on success, 0 OOB.
 * Uses inline_bytes for len <= 8; falls through to next_slab for longer
 * grapheme clusters (up to UINT16_MAX bytes; practical limit is 255 per
 * slab_len field width is fine; we allow up to 16-bit).
 *
 * style parameters (fg_bg, attrs) are written as-is; wide-char tail gets
 * the same style so cell_eq is stable pair-wise. */
static int
put_cell(screen_t *s, int x, int y,
         const char *str, size_t slen, int cw,
         uint8_t fg_bg, uint8_t attrs) {
    if (x < 0 || y < 0 || x >= s->w || y >= s->h) return 0;
    if (cw == 2 && x + 1 >= s->w) return 0;
    if (slen == 0 || slen > 256u) return 0;  /* cap grapheme cluster at 256B */

    cell_t *c = cell_at(s->next, s->w, x, y);
    memset(c, 0, sizeof(*c));

    if (slen <= 8) {
        memcpy(c->u.inline_bytes, str, slen);
        c->len = (uint8_t)slen;
    } else {
        uint32_t off = slab_push(&s->next_slab,
                                 (const uint8_t *)str, (uint32_t)slen);
        if (off == 0xFFFFFFFFu) return 0;  /* OOM — drop silently */
        c->u.ext.slab_off = off;
        c->u.ext.slab_len = (uint16_t)slen;
        c->len = 0xFF;
    }
    c->width = (uint8_t)cw;
    c->fg_bg = fg_bg;
    c->attrs = attrs;

    if (cw == 2) {
        cell_t *tail = cell_at(s->next, s->w, x + 1, y);
        memset(tail, 0, sizeof(*tail));
        tail->len   = 0;  /* WIDE_TAIL */
        tail->width = 0;
        /* Tail keeps the head's style so a diff over (head,tail) is
         * consistent when the style changes but bytes don't. */
        tail->fg_bg = fg_bg;
        tail->attrs = attrs;
    }
    return 1;
}

static int
lput(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    size_t slen;
    const char *str = luaL_checklstring(L, 4, &slen);
    int cw = (int)luaL_checkinteger(L, 5);

    if (cw != 1 && cw != 2) luaL_error(L, "screen.put: width must be 1 or 2");

    uint8_t fg_bg = (uint8_t)luaL_optinteger(L, 6, 0);
    uint8_t attrs = (uint8_t)luaL_optinteger(L, 7, ATTR_DEFAULT);
    put_cell(s, x, y, str, slen, cw, fg_bg, attrs);
    return 0;
}

/* ── Lua API: put_border ──────────────────────────────────────── */

/* 6 UTF-8 glyphs per style: tl, tr, bl, br, h, v.
 * Each is 3 bytes, terminated with NUL for easy reuse. Keep them literal
 * to avoid any charset surprises from the source file encoding. */
typedef struct {
    const char tl[4], tr[4], bl[4], br[4], hh[4], vv[4];
} border_glyphs_t;

static const border_glyphs_t BORDER_SINGLE = {
    {(char)0xE2,(char)0x94,(char)0x8C,0}, /* ┌ */
    {(char)0xE2,(char)0x94,(char)0x90,0}, /* ┐ */
    {(char)0xE2,(char)0x94,(char)0x94,0}, /* └ */
    {(char)0xE2,(char)0x94,(char)0x98,0}, /* ┘ */
    {(char)0xE2,(char)0x94,(char)0x80,0}, /* ─ */
    {(char)0xE2,(char)0x94,(char)0x82,0}, /* │ */
};
static const border_glyphs_t BORDER_DOUBLE = {
    {(char)0xE2,(char)0x95,(char)0x94,0}, /* ╔ */
    {(char)0xE2,(char)0x95,(char)0x97,0}, /* ╗ */
    {(char)0xE2,(char)0x95,(char)0x9A,0}, /* ╚ */
    {(char)0xE2,(char)0x95,(char)0x9D,0}, /* ╝ */
    {(char)0xE2,(char)0x95,(char)0x90,0}, /* ═ */
    {(char)0xE2,(char)0x95,(char)0x91,0}, /* ║ */
};
static const border_glyphs_t BORDER_ROUND = {
    {(char)0xE2,(char)0x95,(char)0xAD,0}, /* ╭ */
    {(char)0xE2,(char)0x95,(char)0xAE,0}, /* ╮ */
    {(char)0xE2,(char)0x95,(char)0xB0,0}, /* ╰ */
    {(char)0xE2,(char)0x95,(char)0xAF,0}, /* ╯ */
    {(char)0xE2,(char)0x94,(char)0x80,0}, /* ─ */
    {(char)0xE2,(char)0x94,(char)0x82,0}, /* │ */
};
static const border_glyphs_t BORDER_BOLD = {
    {(char)0xE2,(char)0x94,(char)0x8F,0}, /* ┏ */
    {(char)0xE2,(char)0x94,(char)0x93,0}, /* ┓ */
    {(char)0xE2,(char)0x94,(char)0x97,0}, /* ┗ */
    {(char)0xE2,(char)0x94,(char)0x9B,0}, /* ┛ */
    {(char)0xE2,(char)0x94,(char)0x81,0}, /* ━ */
    {(char)0xE2,(char)0x94,(char)0x83,0}, /* ┃ */
};
static const border_glyphs_t BORDER_SINGLE_DOUBLE = {
    {(char)0xE2,(char)0x94,(char)0x8D,0}, /* ┍ */
    {(char)0xE2,(char)0x94,(char)0x91,0}, /* ┑ */
    {(char)0xE2,(char)0x94,(char)0x95,0}, /* ┕ */
    {(char)0xE2,(char)0x94,(char)0x99,0}, /* ┙ */
    {(char)0xE2,(char)0x94,(char)0x80,0}, /* ─ */
    {(char)0xE2,(char)0x95,(char)0x91,0}, /* ║ */
};
static const border_glyphs_t BORDER_DOUBLE_SINGLE = {
    {(char)0xE2,(char)0x95,(char)0x8E,0}, /* ╎ */
    {(char)0xE2,(char)0x95,(char)0x8F,0}, /* ╏ */
    {(char)0xE2,(char)0x95,(char)0x8A,0}, /* ╊ */
    {(char)0xE2,(char)0x95,(char)0x8B,0}, /* ╋ */
    {(char)0xE2,(char)0x95,(char)0x90,0}, /* ═ */
    {(char)0xE2,(char)0x94,(char)0x82,0}, /* │ */
};
static const border_glyphs_t BORDER_CLASSIC = {
    {(char)0x2B,0,0,0},                   /* + */
    {(char)0x2B,0,0,0},                   /* + */
    {(char)0x2B,0,0,0},                   /* + */
    {(char)0x2B,0,0,0},                   /* + */
    {(char)0x2D,0,0,0},                   /* - hh */
    {(char)0x7C,0,0,0},                   /* | vv */
};

static const border_glyphs_t *
border_lookup(const char *name) {
    if (!name) return &BORDER_SINGLE;
    if (strcmp(name, "single") == 0) return &BORDER_SINGLE;
    if (strcmp(name, "double") == 0) return &BORDER_DOUBLE;
    if (strcmp(name, "round")  == 0) return &BORDER_ROUND;
    if (strcmp(name, "bold")   == 0) return &BORDER_BOLD;
    if (strcmp(name, "singleDouble") == 0) return &BORDER_SINGLE_DOUBLE;
    if (strcmp(name, "doubleSingle") == 0) return &BORDER_DOUBLE_SINGLE;
    if (strcmp(name, "classic") == 0) return &BORDER_CLASSIC;
    return &BORDER_SINGLE;  /* default */
}

static int
lput_border(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    int w = (int)luaL_checkinteger(L, 4);
    int h = (int)luaL_checkinteger(L, 5);
    const char *style = luaL_optstring(L, 6, "single");

    uint8_t fg_bg = (uint8_t)luaL_optinteger(L, 7, 0);
    uint8_t attrs = (uint8_t)luaL_optinteger(L, 8, ATTR_DEFAULT);

    if (w < 2 || h < 2) return 0;
    const border_glyphs_t *g = border_lookup(style);

    put_cell(s, x,           y,           g->tl, 3, 1, fg_bg, attrs);
    put_cell(s, x + w - 1,   y,           g->tr, 3, 1, fg_bg, attrs);
    put_cell(s, x,           y + h - 1,   g->bl, 3, 1, fg_bg, attrs);
    put_cell(s, x + w - 1,   y + h - 1,   g->br, 3, 1, fg_bg, attrs);
    for (int i = 1; i < w - 1; i++) {
        put_cell(s, x + i,   y,           g->hh, 3, 1, fg_bg, attrs);
        put_cell(s, x + i,   y + h - 1,   g->hh, 3, 1, fg_bg, attrs);
    }
    for (int i = 1; i < h - 1; i++) {
        put_cell(s, x,       y + i,       g->vv, 3, 1, fg_bg, attrs);
        put_cell(s, x + w - 1, y + i,     g->vv, 3, 1, fg_bg, attrs);
    }
    return 0;
}

/* ── Lua API: draw_line ───────────────────────────────────────── */

/* Walks a UTF-8 string one grapheme cluster at a time, calls grapheme_next
 * to get the cluster's byte span and display width, writes each cluster as
 * one cell. Combining marks, ZWJ sequences, VS16 emoji promotion, regional
 * indicator pairs and Hangul L/V/T conjoining are all fused into a single
 * cell — see wcwidth.h for the UAX#29 subset actually covered. Zero-width
 * base clusters (lone combining marks, controls) are skipped. */
static int
ldraw_line(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    size_t tlen;
    const char *text = luaL_checklstring(L, 4, &tlen);
    int max_w = (int)luaL_optinteger(L, 5, s->w);

    uint8_t fg_bg = (uint8_t)luaL_optinteger(L, 6, 0);
    uint8_t attrs = (uint8_t)luaL_optinteger(L, 7, ATTR_DEFAULT);

    int cx = x;
    int stop = x + max_w;
    size_t i = 0;
    while (i < tlen) {
        size_t i0 = i, clen;
        int cw;
        grapheme_next((const unsigned char *)text, tlen, &i, &clen, &cw);
        if (cw <= 0) continue;  /* controls / lone 0-width: skip */
        if (cx + cw > stop) break;
        put_cell(s, cx, y, text + i0, clen, cw, fg_bg, attrs);
        cx += cw;
    }
    return 0;
}

/* ── Lua API: diff (Stage 9 skeleton: full redraw + naive per-cell) ── */

/* growable byte buffer for ANSI output */
typedef struct {
    uint8_t *buf;
    size_t  size;
    size_t  cap;
} bytes_t;

static void
bytes_reserve(bytes_t *b, size_t need) {
    if (b->size + need <= b->cap) return;
    size_t ncap = b->cap ? b->cap : 256;
    while (ncap < b->size + need) ncap *= 2;
    b->buf = (uint8_t *)realloc(b->buf, ncap);
    b->cap = ncap;
}

static void
bytes_append(bytes_t *b, const void *p, size_t n) {
    bytes_reserve(b, n);
    memcpy(b->buf + b->size, p, n);
    b->size += n;
}

static void
bytes_append_cstr(bytes_t *b, const char *s) {
    bytes_append(b, s, strlen(s));
}

/* 1-based y/x into "\x1b[y;xH" (ESC = 0x1B) */
static void
bytes_append_cup(bytes_t *b, int y, int x) {
    char tmp[32];
    int n = snprintf(tmp, sizeof(tmp), "\x1b[%d;%dH", y + 1, x + 1);
    bytes_append(b, tmp, (size_t)n);
}

/* Map a 4-bit color nibble (0..15) to its ANSI SGR fg/bg parameter.
 * 0..7 → 30..37 (normal), 8..15 → 90..97 (bright). Caller passes the base
 * (30 for fg normal, 40 for bg normal); bright offset is +60 (standard). */
static int
sgr_color_param(uint8_t nibble, int base) {
    if (nibble < 8) return base + (int)nibble;
    return base + 60 + (int)(nibble - 8);
}

/* Emit a SGR sequence to transition terminal state from (cur_fg_bg,cur_attrs)
 * to (next_fg_bg, next_attrs). Stage 11: pure incremental diff — only the
 * attributes that actually changed produce parameters, using the standard
 * "off" codes (22/24/27/39/49) for turning properties off.
 *
 * `cur_fg_bg / cur_attrs` are updated in place. If the state already
 * matches, nothing is emitted (zero-byte early return).
 *
 * Bold/dim share the 22m off-code: per ECMA-48, "22" clears BOTH bold and
 * dim intensity. If we need to turn one off while keeping the other on,
 * we emit ";22" first (clearing both) and then re-emit the survivor. */
static void
emit_sgr(bytes_t *b,
         uint8_t *cur_fg_bg, uint8_t *cur_attrs,
         uint8_t next_fg_bg, uint8_t next_attrs) {
    if (*cur_fg_bg == next_fg_bg && *cur_attrs == next_attrs) return;

    char tmp[96];
    int n = 0;
    int first = 1;
    n += snprintf(tmp + n, sizeof(tmp) - n, "\x1b[");

    /* Helper macro: emit ";p" or "p" depending on whether we've already
     * written a parameter. Assumes `first`, `tmp`, `n`, `sizeof(tmp)` in scope. */
    #define EMIT_PARAM(lit) do {                                           \
        if (first) {                                                        \
            n += snprintf(tmp + n, sizeof(tmp) - n, "%s", lit);             \
            first = 0;                                                      \
        } else {                                                            \
            n += snprintf(tmp + n, sizeof(tmp) - n, ";%s", lit);             \
        }                                                                   \
    } while (0)
    #define EMIT_PARAM_NUM(num) do {                                       \
        if (first) {                                                        \
            n += snprintf(tmp + n, sizeof(tmp) - n, "%d", (num));           \
            first = 0;                                                      \
        } else {                                                            \
            n += snprintf(tmp + n, sizeof(tmp) - n, ";%d", (num));           \
        }                                                                   \
    } while (0)

    /* --- bold / dim (share 22m for turn-off) --- */
    uint8_t cur_bd = *cur_attrs & (ATTR_BOLD | ATTR_DIM);
    uint8_t nxt_bd = next_attrs & (ATTR_BOLD | ATTR_DIM);
    if (cur_bd != nxt_bd) {
        uint8_t turned_off = cur_bd & ~nxt_bd;
        if (turned_off) {
            /* 22m clears both bold and dim, then re-add survivors. */
            EMIT_PARAM("22");
            if (nxt_bd & ATTR_BOLD) EMIT_PARAM("1");
            if (nxt_bd & ATTR_DIM)  EMIT_PARAM("2");
        } else {
            /* Only additions — turn on the new ones. */
            uint8_t turned_on = nxt_bd & ~cur_bd;
            if (turned_on & ATTR_BOLD) EMIT_PARAM("1");
            if (turned_on & ATTR_DIM)  EMIT_PARAM("2");
        }
    }

    /* --- underline --- */
    if ((*cur_attrs ^ next_attrs) & ATTR_UNDERLINE) {
        if (next_attrs & ATTR_UNDERLINE) EMIT_PARAM("4");
        else                             EMIT_PARAM("24");
    }

    /* --- inverse --- */
    if ((*cur_attrs ^ next_attrs) & ATTR_INVERSE) {
        if (next_attrs & ATTR_INVERSE) EMIT_PARAM("7");
        else                           EMIT_PARAM("27");
    }

    /* --- fg --- */
    {
        uint8_t cur_def = *cur_attrs & ATTR_FG_DEFAULT;
        uint8_t nxt_def = next_attrs & ATTR_FG_DEFAULT;
        uint8_t cur_fg  = (uint8_t)((*cur_fg_bg >> 4) & 0x0F);
        uint8_t nxt_fg  = (uint8_t)((next_fg_bg >> 4) & 0x0F);
        if (cur_def != nxt_def) {
            if (nxt_def) EMIT_PARAM("39");
            else         EMIT_PARAM_NUM(sgr_color_param(nxt_fg, 30));
        } else if (!nxt_def && cur_fg != nxt_fg) {
            EMIT_PARAM_NUM(sgr_color_param(nxt_fg, 30));
        }
    }

    /* --- bg --- */
    {
        uint8_t cur_def = *cur_attrs & ATTR_BG_DEFAULT;
        uint8_t nxt_def = next_attrs & ATTR_BG_DEFAULT;
        uint8_t cur_bg  = (uint8_t)(*cur_fg_bg & 0x0F);
        uint8_t nxt_bg  = (uint8_t)(next_fg_bg & 0x0F);
        if (cur_def != nxt_def) {
            if (nxt_def) EMIT_PARAM("49");
            else         EMIT_PARAM_NUM(sgr_color_param(nxt_bg, 40));
        } else if (!nxt_def && cur_bg != nxt_bg) {
            EMIT_PARAM_NUM(sgr_color_param(nxt_bg, 40));
        }
    }

    #undef EMIT_PARAM
    #undef EMIT_PARAM_NUM

    /* If nothing actually differed (shouldn't happen given guard above, but
     * defensively): drop the bare "\x1b[" without emitting a final 'm'. */
    if (first) {
        /* No params written — don't emit a bare "ESC[m" (which means ESC[0m
         * in most terminals, a surprise reset). */
    } else {
        n += snprintf(tmp + n, sizeof(tmp) - n, "m");
        bytes_append(b, tmp, (size_t)n);
    }

    *cur_fg_bg = next_fg_bg;
    *cur_attrs = next_attrs;
}

/* Reset SGR state if currently non-default. Used at line boundaries so
 * unchanged trailing whitespace on the next row doesn't inherit color. */
static void
reset_sgr(bytes_t *b, uint8_t *cur_fg_bg, uint8_t *cur_attrs) {
    if (*cur_attrs == ATTR_DEFAULT && *cur_fg_bg == 0) return;
    bytes_append_cstr(b, "\x1b[0m");
    *cur_fg_bg = 0;
    *cur_attrs = ATTR_DEFAULT;
}

/* Segment-merge diff: adjacent changed cells within MERGE_GAP unchanged
 * cells still merge into a single CUP + content run. Emitting unchanged
 * bytes for the gap is cheaper than a second CUP sequence (~6-9 bytes). */
#define MERGE_GAP 3

static int
ldiff(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    bytes_t out = {0};
    uint8_t cur_fg_bg = 0;
    uint8_t cur_attrs = ATTR_DEFAULT;

    if (!s->prev_valid) {
        /* first-frame / invalidated: clear-screen + full redraw.
         * The trailing ESC[0m is a hard SGR baseline so (cur_fg_bg,
         * cur_attrs) = (0, ATTR_DEFAULT) is trustworthy going forward. */
        bytes_append_cstr(&out, "\x1b[H\x1b[2J\x1b[0m");
        for (int y = 0; y < s->h; y++) {
            bytes_append_cup(&out, y, 0);
            for (int x = 0; x < s->w; x++) {
                const cell_t *c = cell_at(s->next, s->w, x, y);
                if (c->len == 0) continue;  /* WIDE_TAIL: skip */
                emit_sgr(&out, &cur_fg_bg, &cur_attrs, c->fg_bg, c->attrs);
                const uint8_t *p; size_t n;
                cell_bytes(c, &s->next_slab, &p, &n);
                bytes_append(&out, p, n);
            }
            /* No row-end reset: SGR state carries across CUP per ECMA-48,
             * and the next row's first changed cell will emit the exact
             * delta. Trailing spaces on a full-redraw row inherit whatever
             * style the last cell set — which is what the user intended. */
        }
    } else {
        /* Per-row segment-merge. Scan each row left-to-right tracking a
         * "run" of cells that belong to the current emitted segment. A new
         * changed cell either extends the current run (possibly jumping
         * over up to MERGE_GAP unchanged cells whose bytes we include to
         * bridge the gap) or terminates the current run and starts a new
         * one after emitting a fresh CUP. */
        for (int y = 0; y < s->h; y++) {
            int run_start = -1;      /* x of first changed cell in current run */
            int last_change = -1;    /* x of last changed cell emitted so far */

            /* helper lambda substitute: flush current run if pending. */
            for (int x = 0; x < s->w; x++) {
                const cell_t *cn = cell_at(s->next, s->w, x, y);
                const cell_t *cp = cell_at(s->prev, s->w, x, y);
                int changed = !cell_eq(cn, &s->next_slab, cp, &s->prev_slab);
                /* Treat WIDE_TAIL as "not independently changed" — its head
                 * drives the comparison. Also, never start a run AT a tail. */
                if (cn->len == 0) changed = 0;

                if (!changed) continue;

                if (run_start < 0) {
                    /* open new run */
                    bytes_append_cup(&out, y, x);
                    emit_sgr(&out, &cur_fg_bg, &cur_attrs,
                             cn->fg_bg, cn->attrs);
                    const uint8_t *p; size_t n;
                    cell_bytes(cn, &s->next_slab, &p, &n);
                    bytes_append(&out, p, n);
                    run_start = x;
                    last_change = x;
                    /* skip over wide-char tail so we don't double-emit */
                    if (cn->width == 2) x++;  /* outer loop will ++ again; */
                } else {
                    int gap = x - last_change - 1;
                    if (gap <= MERGE_GAP) {
                        /* bridge: emit the unchanged cells between
                         * last_change+1 .. x-1 (using next_slab since after
                         * the swap that happens post-diff, these are the
                         * bytes the terminal should hold). Skip WIDE_TAIL.
                         * Honor per-cell style during the bridge too. */
                        for (int k = last_change + 1; k < x; k++) {
                            const cell_t *bc = cell_at(s->next, s->w, k, y);
                            if (bc->len == 0) continue;
                            emit_sgr(&out, &cur_fg_bg, &cur_attrs,
                                     bc->fg_bg, bc->attrs);
                            const uint8_t *bp; size_t bn;
                            cell_bytes(bc, &s->next_slab, &bp, &bn);
                            bytes_append(&out, bp, bn);
                        }
                        emit_sgr(&out, &cur_fg_bg, &cur_attrs,
                                 cn->fg_bg, cn->attrs);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(&out, p, n);
                        last_change = x;
                        if (cn->width == 2) x++;
                    } else {
                        /* gap too big: close old run, open new one */
                        bytes_append_cup(&out, y, x);
                        emit_sgr(&out, &cur_fg_bg, &cur_attrs,
                                 cn->fg_bg, cn->attrs);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(&out, p, n);
                        run_start = x;
                        last_change = x;
                        if (cn->width == 2) x++;
                    }
                }
            }

            /* No row-end reset: SGR state carries across rows, and the
             * next row's changed cells will emit deltas against the
             * current state via emit_sgr. */
        }
    }

    /* Final safety: if any SGR state is still non-default, reset it so
     * post-diff terminal output (status line, etc.) stays uncolored. */
    reset_sgr(&out, &cur_fg_bg, &cur_attrs);

    /* swap next/prev (both cells and slabs) so next frame diffs against this. */
    cell_t *tc = s->prev; s->prev = s->next; s->next = tc;
    slab_t tmp_slab = s->prev_slab;
    s->prev_slab = s->next_slab;
    s->next_slab = tmp_slab;
    slab_reset(&s->next_slab);
    /* Refill the freshly-promoted `next` (old prev, carries stale cells)
     * with spaces. Caller's next paint pass will clear() again which
     * produces the same state; doing it here lets `rows()` and repeated
     * `diff()` calls behave deterministically when paint isn't re-run. */
    fill_space(s->next, s->w * s->h);
    s->prev_valid = 1;

    if (out.size == 0) {
        lua_pushlstring(L, "", 0);
    } else {
        lua_pushlstring(L, (const char *)out.buf, out.size);
    }
    free(out.buf);
    return 1;
}

/* ── Lua API: rows (ring-buffer pool + lua_pushexternalstring) ─────
 *
 * rows() hands Lua N strings (one per row) without per-call malloc. Each
 * call rotates through a ring of ROW_POOL_GEN=4 buffers; the buffer of the
 * current generation is reallocated-in-place as needed, filled, and its
 * interior slices are handed to Lua via lua_pushexternalstring.
 *
 * lua_pushexternalstring contract (Lua 5.5): s[len] == '\0' is required;
 * when falloc is NULL, Lua never frees s and the caller (this C module)
 * is responsible for the buffer's lifetime. The ring buffer gives us that
 * lifetime: row strings returned by rows() remain valid until the fourth
 * subsequent rows() call reuses the same generation.
 *
 * Documented limitation: callers must NOT cache row strings across ≥ 4
 * rows() invocations. Test harness and snapshot use reads rows within a
 * single frame window, which is safe. Docs + roadmap call this out. */
static int
lrows(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    /* After a paint+diff cycle, `prev` holds the committed frame; when no
     * diff has happened yet, `next` holds the in-progress frame. */
    const cell_t *cells = s->prev_valid ? s->prev : s->next;
    const slab_t *slab  = s->prev_valid ? &s->prev_slab : &s->next_slab;

    row_pool_t *pool = &s->rows;
    row_buf_t *rb = &pool->bufs[pool->gen];

    /* Worst-case size: every cell 4 bytes (max UTF-8 code point) + 1 NUL
     * per row. Slab clusters can exceed this bound — accommodate via a
     * pre-pass that computes exact size needed. */
    size_t need = 1; /* final safety NUL */
    for (int y = 0; y < s->h; y++) {
        for (int x = 0; x < s->w; x++) {
            const cell_t *c = &cells[y * s->w + x];
            if (c->len == 0) continue;          /* WIDE_TAIL */
            if (c->len == 0xFF) need += c->u.ext.slab_len;
            else                need += c->len;
        }
        need += 1;  /* row-terminating NUL required by pushexternalstring */
    }

    if (rb->cap < need) {
        size_t ncap = rb->cap ? rb->cap * 2 : 256;
        while (ncap < need) ncap *= 2;
        uint8_t *nb = (uint8_t *)realloc(rb->buf, ncap);
        if (!nb) luaL_error(L, "screen.rows: out of memory");
        rb->buf = nb;
        rb->cap = (uint32_t)ncap;
    }

    lua_createtable(L, s->h, 0);

    size_t off = 0;
    for (int y = 0; y < s->h; y++) {
        size_t row_start = off;
        for (int x = 0; x < s->w; x++) {
            const cell_t *c = &cells[y * s->w + x];
            if (c->len == 0) continue;
            const uint8_t *p; size_t n;
            cell_bytes(c, slab, &p, &n);
            memcpy(rb->buf + off, p, n);
            off += n;
        }
        size_t row_len = off - row_start;
        rb->buf[off] = '\0';  /* NUL required by lua_pushexternalstring */
        off += 1;
        lua_pushexternalstring(L,
                               (const char *)(rb->buf + row_start),
                               row_len,
                               NULL,    /* Lua never frees; C owns buffer */
                               NULL);
        lua_rawseti(L, -2, y + 1);
    }

    pool->gen = (pool->gen + 1) % ROW_POOL_GEN;
    return 1;
}

/* ── __gc ─────────────────────────────────────────────────────── */

static int
lgc(lua_State *L) {
    screen_t *s = (screen_t *)luaL_checkudata(L, 1, SCREEN_MT);
    free(s->next); s->next = NULL;
    free(s->prev); s->prev = NULL;
    slab_free(&s->next_slab);
    slab_free(&s->prev_slab);
    row_pool_free(&s->rows);
    return 0;
}

/* ── registration ─────────────────────────────────────────────── */

static const luaL_Reg screen_lib[] = {
    {"new",        lnew},
    {"size",       lsize},
    {"resize",     lresize},
    {"invalidate", linvalidate},
    {"clear",      lclear},
    {"put",        lput},
    {"put_border", lput_border},
    {"draw_line",  ldraw_line},
    {"diff",       ldiff},
    {"rows",       lrows},
    {NULL, NULL},
};

int
luaopen_screen(lua_State *L) {
    /* metatable for the screen userdata */
    if (luaL_newmetatable(L, SCREEN_MT)) {
        lua_pushcfunction(L, lgc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);

    luaL_newlib(L, screen_lib);
    return 1;
}
