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
#include "tui_fatal.h"

/* ── cell / slab / screen structs ─────────────────────────────── */

/* SGR style layout (Stage 10+):
 *
 *   cell_t.style_id: index into the screen's style_pool.  id=0 means
 *     "terminal default" — no fg/bg/attr overrides.  Non-zero IDs index
 *     style_pool_t.entries[id-1] which carries fg_mode/bg_mode (one of
 *     COLOR_MODE_DEFAULT/16/256/24BIT), the color value, and the attrs
 *     bitmask (BOLD|DIM|UNDERLINE|INVERSE|ITALIC|STRIKETHROUGH).
 *
 *   Downgrade: when screen.color_level < the mode requested, emit_sgr
 *     transparently downgrades (24bit→256→16) at render time.  The pool
 *     always stores the original (highest-fidelity) value.
 */
#define ATTR_BOLD          0x01u
#define ATTR_DIM           0x02u
#define ATTR_UNDERLINE     0x04u
#define ATTR_INVERSE       0x08u
#define ATTR_ITALIC        0x40u
#define ATTR_STRIKETHROUGH 0x80u
#define ATTR_STYLE_MASK    (ATTR_BOLD | ATTR_DIM | ATTR_UNDERLINE | ATTR_INVERSE \
                            | ATTR_ITALIC | ATTR_STRIKETHROUGH)

/* Color mode stored in style_entry_t.fg_mode / bg_mode. */
#define COLOR_MODE_DEFAULT  0u  /* terminal default color (SGR 39/49) */
#define COLOR_MODE_16       1u  /* ANSI 16-color (0..15) */
#define COLOR_MODE_256      2u  /* xterm 256-color (0..255) */
#define COLOR_MODE_24BIT    3u  /* 24-bit truecolor (0x00RRGGBB) */

/* Screen-level color depth limit. */
#define COLOR_LEVEL_16    0  /* ANSI 16-color only */
#define COLOR_LEVEL_256   1  /* up to xterm 256-color */
#define COLOR_LEVEL_24BIT 2  /* full 24-bit truecolor */

typedef struct {
    union {
        uint8_t inline_bytes[8];
        struct {
            uint32_t slab_off;
            uint16_t slab_len;
            uint8_t  _pad[2];
        } ext;
    } u;
    uint8_t  len;       /* 1..8 inline, 0xFF slab, 0 WIDE_TAIL */
    uint8_t  width;     /* 0 tail, 1 narrow, 2 wide head */
    uint16_t style_id;  /* style pool index; 0 = default (no style) */
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

/* ── style_entry_t / style_pool_t ─────────────────────────────────
 *
 * style_id=0 is the implicit default style (all-default fg/bg, no attrs).
 * style_id N > 0 refers to pool->entries[N-1].  The pool grows
 * monotonically during the session — no per-frame reset — so prev-buffer
 * style_ids remain valid across frame boundaries (required for diff). */
typedef struct {
    uint32_t fg_val;   /* color value (meaning depends on fg_mode) */
    uint32_t bg_val;   /* color value (meaning depends on bg_mode) */
    uint8_t  fg_mode;  /* COLOR_MODE_* */
    uint8_t  bg_mode;  /* COLOR_MODE_* */
    uint8_t  attrs;    /* ATTR_BOLD | ATTR_DIM | … (no DEFAULT bits) */
    uint8_t  _pad;
} style_entry_t;  /* 12 bytes */

typedef struct {
    style_entry_t *entries;  /* entries[i] → style_id (i+1) */
    uint32_t       count;
    uint32_t       cap;
} style_pool_t;

#define ROW_POOL_GEN 4

typedef struct {
    uint8_t *buf;
    uint32_t cap;
} row_buf_t;

typedef struct {
    row_buf_t bufs[ROW_POOL_GEN];
    int       gen;
} row_pool_t;

/* Rendering mode constants. */
#define SCREEN_MODE_ALT  0   /* CUP-based (default, alt-screen compatible) */
#define SCREEN_MODE_MAIN 1   /* relative-move + cursor-restore (main screen) */

typedef struct {
    int w, h;
    cell_t *next;
    cell_t *prev;
    slab_t  next_slab;
    slab_t  prev_slab;
    int     prev_valid;
    row_pool_t rows;
    /* rendering mode and virtual cursor state (main-screen mode only) */
    int  mode;              /* SCREEN_MODE_ALT or SCREEN_MODE_MAIN */
    int  virt_x, virt_y;   /* virtual cursor after cursor_restore (0-based) */
    int  display_x, display_y; /* declared TextInput cursor (0-based; -1 = none) */
    int  has_display;       /* 1 if display_x/y is valid */
    /* Damage tracking: rightmost column written per row in next/prev buffers.
     * -1 means the row was not touched this frame (skip in incremental diff). */
    int *dirty_xmax;        /* next buffer: max x written per row */
    int *prev_xmax;         /* prev buffer: max x written last diff */
    /* effective_h used in the last committed frame (main-screen mode only).
     * Used to detect when content grows and new rows must be claimed via \r\n
     * rather than CUD (which clamps at the terminal bottom). */
    int  prev_effective_h;
    /* Set to 1 whenever next is known-clean: fill_space'd, slab reset, and
     * dirty_xmax initialized. Cleared by put_cell on first write. Allows
     * clear() to be a no-op when next is already blank (e.g. right after diff
     * or resize), avoiding a redundant O(w*h) fill_space each frame. */
    int  next_clean;
    int  color_level;    /* COLOR_LEVEL_* — limits SGR output depth */
    style_pool_t pool;   /* persistent style pool (never reset between frames) */
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
    c->len      = 1;
    c->width    = 1;
    c->style_id = 0;
}

static void
fill_space(cell_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        cell_t *c = &buf[i];
        memset(c, 0, sizeof(*c));
        c->u.inline_bytes[0] = ' ';
        c->len   = 1;
        c->width = 1;
        /* style_id already 0 from memset → terminal default */
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
    if (a->style_id != b->style_id) return 0;
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

/* ── style pool helpers ────────────────────────────────────────── */

static const style_entry_t STYLE_DEFAULT_ENTRY = {0u, 0u, 0u, 0u, 0u, 0u};

static const style_entry_t *
pool_get(const style_pool_t *p, uint16_t id) {
    if (id == 0 || (uint32_t)(id - 1) >= p->count)
        return &STYLE_DEFAULT_ENTRY;
    return &p->entries[id - 1];
}

static uint16_t
style_intern(style_pool_t *p,
             uint8_t fg_mode, uint32_t fg_val,
             uint8_t bg_mode, uint32_t bg_val,
             uint8_t attrs) {
    /* id=0 is the implicit all-default; avoid storing it. */
    if (fg_mode == COLOR_MODE_DEFAULT &&
        bg_mode == COLOR_MODE_DEFAULT && attrs == 0)
        return 0;
    /* Linear scan — pool typically stays well under 200 entries. */
    for (uint32_t i = 0; i < p->count; i++) {
        const style_entry_t *e = &p->entries[i];
        if (e->fg_mode == fg_mode && e->fg_val == fg_val &&
            e->bg_mode == bg_mode && e->bg_val == bg_val &&
            e->attrs   == attrs)
            return (uint16_t)(i + 1);
    }
    /* Grow pool if needed. */
    if (p->count >= p->cap) {
        uint32_t ncap = p->cap ? p->cap * 2 : 64;
        if (ncap > 65534u) ncap = 65534u;  /* cap at max uint16_t - 1 */
        style_entry_t *ne = (style_entry_t *)realloc(p->entries,
                                                      ncap * sizeof(style_entry_t));
        if (!ne) return 0;  /* OOM: fall back to default */
        p->entries = ne;
        p->cap = ncap;
    }
    uint16_t id = (uint16_t)(p->count + 1);
    style_entry_t *e = &p->entries[p->count++];
    e->fg_mode = fg_mode; e->fg_val  = fg_val;
    e->bg_mode = bg_mode; e->bg_val  = bg_val;
    e->attrs   = attrs;   e->_pad    = 0;
    return id;
}

static void
pool_free(style_pool_t *p) {
    free(p->entries);
    p->entries = NULL;
    p->count = p->cap = 0;
}

/* ── Color downgrade helpers ───────────────────────────────────── */

/* Expand xterm-256 palette index to approximate (r, g, b). */
static void
xterm256_to_rgb(uint8_t idx, uint8_t *r, uint8_t *g, uint8_t *b) {
    if (idx < 16) {
        static const uint8_t ansi16[16][3] = {
            {  0,  0,  0}, {128,  0,  0}, {  0,128,  0}, {128,128,  0},
            {  0,  0,128}, {128,  0,128}, {  0,128,128}, {192,192,192},
            {128,128,128}, {255,  0,  0}, {  0,255,  0}, {255,255,  0},
            {  0,  0,255}, {255,  0,255}, {  0,255,255}, {255,255,255},
        };
        *r = ansi16[idx][0]; *g = ansi16[idx][1]; *b = ansi16[idx][2];
    } else if (idx < 232) {
        /* 6×6×6 color cube: values 0,95,135,175,215,255. */
        static const uint8_t cv[6] = {0, 95, 135, 175, 215, 255};
        uint8_t i6 = idx - 16;
        *r = cv[i6 / 36]; *g = cv[(i6 / 6) % 6]; *b = cv[i6 % 6];
    } else {
        /* 24-step grayscale ramp: 8..238, step 10. */
        uint8_t v = (uint8_t)(8 + (idx - 232) * 10);
        *r = *g = *b = v;
    }
}

/* Nearest ANSI 16-color for an RGB value. */
static uint8_t
rgb_to_ansi16(uint8_t r, uint8_t g, uint8_t b) {
    static const uint8_t ansi16[16][3] = {
        {  0,  0,  0}, {128,  0,  0}, {  0,128,  0}, {128,128,  0},
        {  0,  0,128}, {128,  0,128}, {  0,128,128}, {192,192,192},
        {128,128,128}, {255,  0,  0}, {  0,255,  0}, {255,255,  0},
        {  0,  0,255}, {255,  0,255}, {  0,255,255}, {255,255,255},
    };
    uint8_t best = 0;
    int best_d = 0x7FFFFFFF;
    for (int i = 0; i < 16; i++) {
        int dr = (int)r - ansi16[i][0];
        int dg = (int)g - ansi16[i][1];
        int db = (int)b - ansi16[i][2];
        int d = dr*dr + dg*dg + db*db;
        if (d < best_d) { best_d = d; best = (uint8_t)i; }
    }
    return best;
}

/* Nearest xterm-256 index for an RGB value. */
static uint8_t
rgb_to_xterm256(uint8_t r, uint8_t g, uint8_t b) {
    /* 6×6×6 color cube: component values 0,95,135,175,215,255. */
    static const uint8_t CV[6] = {0, 95, 135, 175, 215, 255};
    /* Find nearest cube dimension index for each channel. */
    int ri = 0, gi = 0, bi = 0;
    for (int i = 1; i < 6; i++) {
        if (abs((int)r - CV[i]) < abs((int)r - CV[ri])) ri = i;
        if (abs((int)g - CV[i]) < abs((int)g - CV[gi])) gi = i;
        if (abs((int)b - CV[i]) < abs((int)b - CV[bi])) bi = i;
    }
    uint8_t cube_idx = (uint8_t)(16 + 36*ri + 6*gi + bi);
    int cdr = (int)r - CV[ri], cdg = (int)g - CV[gi], cdb = (int)b - CV[bi];
    int cube_d = cdr*cdr + cdg*cdg + cdb*cdb;
    /* Compare against nearest grayscale ramp entry (232..255 = 8..238 step 10). */
    int gray_avg = ((int)r + g + b) / 3;
    int gray_i = (gray_avg - 8) / 10;
    if (gray_i < 0) gray_i = 0;
    if (gray_i > 23) gray_i = 23;
    uint8_t gv = (uint8_t)(8 + gray_i * 10);
    int gdr = (int)r - gv, gdg = (int)g - gv, gdb = (int)b - gv;
    int gray_d = gdr*gdr + gdg*gdg + gdb*gdb;
    return (gray_d < cube_d) ? (uint8_t)(232 + gray_i) : cube_idx;
}

/* xterm-256 index → nearest ANSI 16-color index. */
static uint8_t
xterm256_to_ansi16(uint8_t idx) {
    uint8_t r, g, b;
    xterm256_to_rgb(idx, &r, &g, &b);
    return rgb_to_ansi16(r, g, b);
}

/* ── Effective-style computation ────────────────────────────────── */

/* Effective (post-downgrade) style; used by emit_sgr for comparison
 * and emission.  Stores mode+val per channel so comparison is uniform. */
typedef struct {
    uint8_t  fg_mode;
    uint32_t fg_val;
    uint8_t  bg_mode;
    uint32_t bg_val;
    uint8_t  attrs;
} eff_style_t;

static eff_style_t
compute_eff(const style_entry_t *s, int color_level) {
    eff_style_t e;
    e.attrs = s->attrs;

    /* FG channel */
    if (s->fg_mode == COLOR_MODE_DEFAULT) {
        e.fg_mode = COLOR_MODE_DEFAULT; e.fg_val = 0;
    } else if (color_level >= COLOR_LEVEL_24BIT) {
        e.fg_mode = s->fg_mode; e.fg_val = s->fg_val;
    } else if (color_level == COLOR_LEVEL_256) {
        if (s->fg_mode == COLOR_MODE_24BIT) {
            e.fg_mode = COLOR_MODE_256;
            e.fg_val = rgb_to_xterm256((s->fg_val>>16)&0xFF,
                                       (s->fg_val>>8)&0xFF, s->fg_val&0xFF);
        } else { e.fg_mode = s->fg_mode; e.fg_val = s->fg_val; }
    } else { /* COLOR_LEVEL_16 */
        if (s->fg_mode == COLOR_MODE_24BIT) {
            e.fg_mode = COLOR_MODE_16;
            e.fg_val = rgb_to_ansi16((s->fg_val>>16)&0xFF,
                                     (s->fg_val>>8)&0xFF, s->fg_val&0xFF);
        } else if (s->fg_mode == COLOR_MODE_256) {
            e.fg_mode = COLOR_MODE_16;
            e.fg_val = xterm256_to_ansi16((uint8_t)s->fg_val);
        } else { e.fg_mode = s->fg_mode; e.fg_val = s->fg_val; }
    }

    /* BG channel (identical logic) */
    if (s->bg_mode == COLOR_MODE_DEFAULT) {
        e.bg_mode = COLOR_MODE_DEFAULT; e.bg_val = 0;
    } else if (color_level >= COLOR_LEVEL_24BIT) {
        e.bg_mode = s->bg_mode; e.bg_val = s->bg_val;
    } else if (color_level == COLOR_LEVEL_256) {
        if (s->bg_mode == COLOR_MODE_24BIT) {
            e.bg_mode = COLOR_MODE_256;
            e.bg_val = rgb_to_xterm256((s->bg_val>>16)&0xFF,
                                       (s->bg_val>>8)&0xFF, s->bg_val&0xFF);
        } else { e.bg_mode = s->bg_mode; e.bg_val = s->bg_val; }
    } else {
        if (s->bg_mode == COLOR_MODE_24BIT) {
            e.bg_mode = COLOR_MODE_16;
            e.bg_val = rgb_to_ansi16((s->bg_val>>16)&0xFF,
                                     (s->bg_val>>8)&0xFF, s->bg_val&0xFF);
        } else if (s->bg_mode == COLOR_MODE_256) {
            e.bg_mode = COLOR_MODE_16;
            e.bg_val = xterm256_to_ansi16((uint8_t)s->bg_val);
        } else { e.bg_mode = s->bg_mode; e.bg_val = s->bg_val; }
    }
    return e;
}

static screen_t *
check_screen(lua_State *L, int idx) {
    return (screen_t *)luaL_checkudata(L, idx, SCREEN_MT);
}

/* Style packing lives in Lua (tui/sgr.lua:pack_bytes). Callers pass the
 * two packed bytes (fg_bg, attrs) directly; this module consumes them
 * unchanged. See ATTR_* macros above for the bit layout. */

/* Initialize dirty_xmax array to -1 (all rows clean). */
static void
dirty_xmax_init(int *arr, int h) {
    /* memset with 0xFF gives 0xFFFFFFFF = -1 for 32-bit int (two's complement). */
    memset(arr, 0xFF, (size_t)h * sizeof(int));
}

/* ── Lua API: new / size / resize / invalidate / clear / __gc ── */

static int
l_new(lua_State *L) {
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
        TUI_FATAL(L, "screen.new: out of memory");
    }
    fill_space(s->next, (int)ncells);
    fill_space(s->prev, (int)ncells);
    s->dirty_xmax = (int *)malloc((size_t)s->h * sizeof(int));
    s->prev_xmax  = (int *)malloc((size_t)s->h * sizeof(int));
    if (!s->dirty_xmax || !s->prev_xmax) {
        free(s->next); free(s->prev);
        free(s->dirty_xmax); free(s->prev_xmax);
        s->next = s->prev = NULL;
        s->dirty_xmax = s->prev_xmax = NULL;
        TUI_FATAL(L, "screen.new: out of memory");
    }
    dirty_xmax_init(s->dirty_xmax, s->h);
    dirty_xmax_init(s->prev_xmax, s->h);
    s->prev_valid = 0;
    s->next_clean = 1;
    s->mode = SCREEN_MODE_ALT;
    s->virt_x = 0; s->virt_y = 0;
    s->display_x = -1; s->display_y = -1;
    s->has_display = 0;

    luaL_getmetatable(L, SCREEN_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int
l_size(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    lua_pushinteger(L, s->w);
    lua_pushinteger(L, s->h);
    return 2;
}

static int
l_resize(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    lua_Integer w = luaL_checkinteger(L, 2);
    lua_Integer h = luaL_checkinteger(L, 3);
    luaL_argcheck(L, w > 0 && w < 100000, 2, "width out of range");
    luaL_argcheck(L, h > 0 && h < 100000, 3, "height out of range");

    size_t ncells = (size_t)w * (size_t)h;
    cell_t *nn = (cell_t *)realloc(s->next, ncells * sizeof(cell_t));
    cell_t *np = (cell_t *)realloc(s->prev, ncells * sizeof(cell_t));
    if (!nn || !np) TUI_FATAL(L, "screen.resize: out of memory");
    s->next = nn;
    s->prev = np;
    s->w = (int)w;
    s->h = (int)h;
    /* Realloc damage tracking arrays (height may have changed). */
    int *nd = (int *)realloc(s->dirty_xmax, (size_t)s->h * sizeof(int));
    int *pd = (int *)realloc(s->prev_xmax,  (size_t)s->h * sizeof(int));
    if (!nd || !pd) TUI_FATAL(L, "screen.resize: out of memory");
    s->dirty_xmax = nd;
    s->prev_xmax  = pd;
    dirty_xmax_init(s->dirty_xmax, s->h);
    dirty_xmax_init(s->prev_xmax,  s->h);
    fill_space(s->next, (int)ncells);
    fill_space(s->prev, (int)ncells);
    slab_reset(&s->next_slab);
    slab_reset(&s->prev_slab);
    /* row pool buffers invalidated: drop them so next rows() reallocates. */
    row_pool_free(&s->rows);
    s->prev_valid = 0;
    s->next_clean = 1;
    return 0;
}

static int
l_invalidate(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    s->prev_valid = 0;
    return 0;
}

static int
l_clear(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    if (!s->next_clean) {
        fill_space(s->next, s->w * s->h);
        slab_reset(&s->next_slab);
        dirty_xmax_init(s->dirty_xmax, s->h);
        s->next_clean = 1;
    }
    return 0;
}

/* ── Lua API: put ─────────────────────────────────────────────── */

/* Internal cell writer used by l_put / draw_line / put_border.
 * x,y 0-based. Length-0 strings are rejected. Returns 1 on success, 0 OOB.
 * Uses inline_bytes for len <= 8; falls through to next_slab for longer
 * grapheme clusters (up to UINT16_MAX bytes; practical limit is 255 per
 * slab_len field width is fine; we allow up to 16-bit).
 *
 * style_id is written as-is; wide-char tail gets the same style_id so
 * cell_eq is stable pair-wise. */
static int
put_cell(screen_t *s, int x, int y,
         const char *str, size_t slen, int cw,
         uint16_t style_id) {
    if (x < 0 || y < 0 || x >= s->w || y >= s->h) return 0;
    if (cw == 2 && x + 1 >= s->w) return 0;
    if (slen == 0 || slen > 256u) return 0;  /* cap grapheme cluster at 256B */

    s->next_clean = 0;

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
    c->width    = (uint8_t)cw;
    c->style_id = style_id;

    /* Track rightmost column written for damage-based row skipping in diff. */
    {
        int rx = x + cw - 1;
        if (rx > s->dirty_xmax[y]) s->dirty_xmax[y] = rx;
    }

    if (cw == 2) {
        cell_t *tail = cell_at(s->next, s->w, x + 1, y);
        memset(tail, 0, sizeof(*tail));
        tail->len      = 0;  /* WIDE_TAIL */
        tail->width    = 0;
        /* Tail keeps the head's style so a diff over (head,tail) is
         * consistent when the style changes but bytes don't. */
        tail->style_id = style_id;
    }
    return 1;
}

static int
l_put(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    size_t slen;
    const char *str = luaL_checklstring(L, 4, &slen);
    int cw = (int)luaL_checkinteger(L, 5);

    if (cw != 1 && cw != 2) TUI_FATAL(L, "screen.put: width must be 1 or 2");

    uint16_t style_id = (uint16_t)luaL_optinteger(L, 6, 0);
    put_cell(s, x, y, str, slen, cw, style_id);
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
l_put_border(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    int w = (int)luaL_checkinteger(L, 4);
    int h = (int)luaL_checkinteger(L, 5);
    const char *style = luaL_optstring(L, 6, "single");

    uint16_t style_id = (uint16_t)luaL_optinteger(L, 7, 0);

    if (w < 2 || h < 2) return 0;
    const border_glyphs_t *g = border_lookup(style);

    put_cell(s, x,           y,           g->tl, 3, 1, style_id);
    put_cell(s, x + w - 1,   y,           g->tr, 3, 1, style_id);
    put_cell(s, x,           y + h - 1,   g->bl, 3, 1, style_id);
    put_cell(s, x + w - 1,   y + h - 1,   g->br, 3, 1, style_id);
    for (int i = 1; i < w - 1; i++) {
        put_cell(s, x + i,   y,           g->hh, 3, 1, style_id);
        put_cell(s, x + i,   y + h - 1,   g->hh, 3, 1, style_id);
    }
    for (int i = 1; i < h - 1; i++) {
        put_cell(s, x,       y + i,       g->vv, 3, 1, style_id);
        put_cell(s, x + w - 1, y + i,     g->vv, 3, 1, style_id);
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
l_draw_line(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    size_t tlen;
    const char *text = luaL_checklstring(L, 4, &tlen);
    int max_w = (int)luaL_optinteger(L, 5, s->w);

    uint16_t style_id = (uint16_t)luaL_optinteger(L, 6, 0);

    int cx = x;
    int stop = x + max_w;
    size_t i = 0;
    while (i < tlen) {
        size_t i0 = i, clen;
        int cw;
        grapheme_next((const unsigned char *)text, tlen, &i, &clen, &cw);
        if (cw <= 0) continue;  /* controls / lone 0-width: skip */
        if (cx + cw > stop) break;
        put_cell(s, cx, y, text + i0, clen, cw, style_id);
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
 * 0..7 → 30..37 (normal), 8..15 → 90..97 (bright). */
static int
sgr_color_param(uint8_t nibble, int base) {
    if (nibble < 8) return base + (int)nibble;
    return base + 60 + (int)(nibble - 8);
}

/* Emit a SGR sequence to transition terminal state from cur_id to next_id.
 * Uses the screen's style pool and color_level to downgrade if needed.
 * Pure incremental: only changed attributes produce parameters.
 * cur_id is updated in-place.  No-op when effective styles are identical. */
static void
emit_sgr(bytes_t *b,
         const style_pool_t *pool, int color_level,
         uint16_t *cur_id, uint16_t next_id) {
    if (*cur_id == next_id) return;

    const style_entry_t *cur_se = pool_get(pool, *cur_id);
    const style_entry_t *nxt_se = pool_get(pool, next_id);

    eff_style_t cur_e = compute_eff(cur_se, color_level);
    eff_style_t nxt_e = compute_eff(nxt_se, color_level);

    /* If effective (post-downgrade) states are identical, skip. */
    if (cur_e.fg_mode == nxt_e.fg_mode && cur_e.fg_val == nxt_e.fg_val &&
        cur_e.bg_mode == nxt_e.bg_mode && cur_e.bg_val == nxt_e.bg_val &&
        cur_e.attrs   == nxt_e.attrs) {
        *cur_id = next_id;
        return;
    }

    /* Truecolor SGR params can be "\x1b[38;2;255;255;255;48;2;255;255;255;" + attrs
     * — allocate 256 bytes to be safe. */
    char tmp[256];
    int n = 0;
    int first = 1;
    n += snprintf(tmp + n, sizeof(tmp) - n, "\x1b[");

    #define EMIT_P(lit) do {                                                  \
        if (first) { n += snprintf(tmp+n, sizeof(tmp)-n, "%s", lit); first=0; } \
        else        { n += snprintf(tmp+n, sizeof(tmp)-n, ";%s", lit); }      \
    } while (0)
    #define EMIT_N(num) do {                                                  \
        if (first) { n += snprintf(tmp+n, sizeof(tmp)-n, "%d", (num)); first=0; } \
        else        { n += snprintf(tmp+n, sizeof(tmp)-n, ";%d", (num)); }    \
    } while (0)
    #define EMIT_F(fmt, ...) do {                                             \
        if (first) { n += snprintf(tmp+n, sizeof(tmp)-n, fmt, __VA_ARGS__); first=0; } \
        else        { n += snprintf(tmp+n, sizeof(tmp)-n, ";" fmt, __VA_ARGS__); }     \
    } while (0)

    /* --- bold / dim (share 22m for turn-off) --- */
    uint8_t cur_bd = cur_e.attrs & (ATTR_BOLD | ATTR_DIM);
    uint8_t nxt_bd = nxt_e.attrs & (ATTR_BOLD | ATTR_DIM);
    if (cur_bd != nxt_bd) {
        uint8_t turned_off = cur_bd & ~nxt_bd;
        if (turned_off) {
            EMIT_P("22");
            if (nxt_bd & ATTR_BOLD) EMIT_P("1");
            if (nxt_bd & ATTR_DIM)  EMIT_P("2");
        } else {
            uint8_t turned_on = nxt_bd & ~cur_bd;
            if (turned_on & ATTR_BOLD) EMIT_P("1");
            if (turned_on & ATTR_DIM)  EMIT_P("2");
        }
    }

    /* --- underline --- */
    if ((cur_e.attrs ^ nxt_e.attrs) & ATTR_UNDERLINE) {
        if (nxt_e.attrs & ATTR_UNDERLINE) EMIT_P("4");
        else                              EMIT_P("24");
    }

    /* --- inverse --- */
    if ((cur_e.attrs ^ nxt_e.attrs) & ATTR_INVERSE) {
        if (nxt_e.attrs & ATTR_INVERSE) EMIT_P("7");
        else                            EMIT_P("27");
    }

    /* --- italic --- */
    if ((cur_e.attrs ^ nxt_e.attrs) & ATTR_ITALIC) {
        if (nxt_e.attrs & ATTR_ITALIC) EMIT_P("3");
        else                           EMIT_P("23");
    }

    /* --- strikethrough --- */
    if ((cur_e.attrs ^ nxt_e.attrs) & ATTR_STRIKETHROUGH) {
        if (nxt_e.attrs & ATTR_STRIKETHROUGH) EMIT_P("9");
        else                                  EMIT_P("29");
    }

    /* --- fg --- */
    if (cur_e.fg_mode != nxt_e.fg_mode || cur_e.fg_val != nxt_e.fg_val) {
        if (nxt_e.fg_mode == COLOR_MODE_DEFAULT) {
            EMIT_P("39");
        } else if (nxt_e.fg_mode == COLOR_MODE_16) {
            EMIT_N(sgr_color_param((uint8_t)nxt_e.fg_val, 30));
        } else if (nxt_e.fg_mode == COLOR_MODE_256) {
            EMIT_F("38;5;%u", (unsigned)nxt_e.fg_val);
        } else { /* COLOR_MODE_24BIT */
            EMIT_F("38;2;%u;%u;%u",
                   (nxt_e.fg_val >> 16) & 0xFF,
                   (nxt_e.fg_val >>  8) & 0xFF,
                    nxt_e.fg_val        & 0xFF);
        }
    }

    /* --- bg --- */
    if (cur_e.bg_mode != nxt_e.bg_mode || cur_e.bg_val != nxt_e.bg_val) {
        if (nxt_e.bg_mode == COLOR_MODE_DEFAULT) {
            EMIT_P("49");
        } else if (nxt_e.bg_mode == COLOR_MODE_16) {
            EMIT_N(sgr_color_param((uint8_t)nxt_e.bg_val, 40));
        } else if (nxt_e.bg_mode == COLOR_MODE_256) {
            EMIT_F("48;5;%u", (unsigned)nxt_e.bg_val);
        } else { /* COLOR_MODE_24BIT */
            EMIT_F("48;2;%u;%u;%u",
                   (nxt_e.bg_val >> 16) & 0xFF,
                   (nxt_e.bg_val >>  8) & 0xFF,
                    nxt_e.bg_val        & 0xFF);
        }
    }

    #undef EMIT_P
    #undef EMIT_N
    #undef EMIT_F

    if (!first) {
        n += snprintf(tmp + n, sizeof(tmp) - n, "m");
        bytes_append(b, tmp, (size_t)n);
    }

    *cur_id = next_id;
}

/* Reset SGR state to terminal default.  No-op when cur_id is already 0. */
static void
reset_sgr(bytes_t *b, uint16_t *cur_id) {
    if (*cur_id == 0) return;
    bytes_append_cstr(b, "\x1b[0m");
    *cur_id = 0;
}

/* Segment-merge diff: adjacent changed cells within MERGE_GAP unchanged
 * cells still merge into a single CUP + content run. Emitting unchanged
 * bytes for the gap is cheaper than a second CUP sequence (~6-9 bytes). */
#define MERGE_GAP 3

/* ── Cursor-movement helpers for main-screen mode ────────────────── */

/* Emit CSI n <cmd>. Omits the parameter when n == 1 (e.g. "\x1b[B"
 * not "\x1b[1B") to match common terminal conventions. */
static void
bytes_append_csi_n(bytes_t *b, int n, char cmd) {
    char tmp[32];
    int len;
    if (n == 1) len = snprintf(tmp, sizeof(tmp), "\x1b[%c",    cmd);
    else        len = snprintf(tmp, sizeof(tmp), "\x1b[%d%c", n, cmd);
    bytes_append(b, tmp, (size_t)len);
}

/* Relative cursor move from (from_x, from_y) to (to_x, to_y).
 * Implements Ink's moveCursorTo algorithm.  Coordinates are 0-based.
 * width = screen width (used to detect the pending-wrap state). */
static void
emit_relative_move(bytes_t *b,
                   int from_x, int from_y,
                   int to_x,   int to_y,
                   int width) {
    int dy = to_y - from_y;
    int dx = to_x - from_x;
    if (from_x >= width || dy != 0) {
        /* Cross-row or pending-wrap: CR resolves wrap, then vertical + forward. */
        bytes_append(b, "\r", 1);
        if      (dy > 0) bytes_append_csi_n(b,  dy, 'B');
        else if (dy < 0) bytes_append_csi_n(b, -dy, 'A');
        if (to_x > 0)    bytes_append_csi_n(b, to_x, 'C');
    } else {
        /* Same row, no wrap: horizontal only. */
        if      (dx > 0) bytes_append_csi_n(b,  dx, 'C');
        else if (dx < 0) bytes_append_csi_n(b, -dx, 'D');
    }
}

/* ── Alt-screen diff (existing behavior, preserved verbatim) ─────── */

static void
diff_alt(screen_t *s, bytes_t *out) {
    uint16_t cur_style_id = 0;

    if (!s->prev_valid) {
        /* first-frame / invalidated: clear-screen + full redraw. */
        bytes_append_cstr(out, "\x1b[H\x1b[2J\x1b[0m");
        for (int y = 0; y < s->h; y++) {
            bytes_append_cup(out, y, 0);
            for (int x = 0; x < s->w; x++) {
                const cell_t *c = cell_at(s->next, s->w, x, y);
                if (c->len == 0) continue;  /* WIDE_TAIL: skip */
                emit_sgr(out, &s->pool, s->color_level, &cur_style_id, c->style_id);
                const uint8_t *p; size_t n;
                cell_bytes(c, &s->next_slab, &p, &n);
                bytes_append(out, p, n);
            }
            reset_sgr(out, &cur_style_id);
        }
    } else {
        for (int y = 0; y < s->h; y++) {
            int dx = s->dirty_xmax[y];
            int px = s->prev_xmax[y];
            if (dx < 0 && px < 0) continue;
            int x_end = (dx > px ? dx : px) + 1;
            int run_start = -1;
            int last_change = -1;

            for (int x = 0; x < x_end; x++) {
                const cell_t *cn = cell_at(s->next, s->w, x, y);
                const cell_t *cp = cell_at(s->prev, s->w, x, y);
                int changed = !cell_eq(cn, &s->next_slab, cp, &s->prev_slab);
                if (cn->len == 0) changed = 0;

                if (!changed) continue;

                if (run_start < 0) {
                    bytes_append_cup(out, y, x);
                    emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                    const uint8_t *p; size_t n;
                    cell_bytes(cn, &s->next_slab, &p, &n);
                    bytes_append(out, p, n);
                    run_start = x;
                    last_change = x;
                    if (cn->width == 2) x++;
                } else {
                    int gap = x - last_change - 1;
                    if (gap <= MERGE_GAP) {
                        for (int k = last_change + 1; k < x; k++) {
                            const cell_t *bc = cell_at(s->next, s->w, k, y);
                            if (bc->len == 0) continue;
                            emit_sgr(out, &s->pool, s->color_level, &cur_style_id, bc->style_id);
                            const uint8_t *bp; size_t bn;
                            cell_bytes(bc, &s->next_slab, &bp, &bn);
                            bytes_append(out, bp, bn);
                        }
                        emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(out, p, n);
                        last_change = x;
                        if (cn->width == 2) x++;
                    } else {
                        bytes_append_cup(out, y, x);
                        emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(out, p, n);
                        run_start = x;
                        last_change = x;
                        if (cn->width == 2) x++;
                    }
                }
            }
        }
    }

    reset_sgr(out, &cur_style_id);

    /* swap next/prev (both cells and slabs) so next frame diffs against this. */
    cell_t *tc = s->prev; s->prev = s->next; s->next = tc;
    slab_t tmp_slab = s->prev_slab;
    s->prev_slab = s->next_slab;
    s->next_slab = tmp_slab;
    slab_reset(&s->next_slab);
    /* Refill the freshly-promoted `next` (old prev, carries stale cells)
     * with spaces, and mark it clean so the next clear() call is a no-op. */
    fill_space(s->next, s->w * s->h);
    s->next_clean = 1;
    /* Swap dirty tracking: prev_xmax = what was just rendered; reset dirty_xmax. */
    {
        int *tmp = s->prev_xmax;
        s->prev_xmax  = s->dirty_xmax;
        s->dirty_xmax = tmp;
        dirty_xmax_init(s->dirty_xmax, s->h);
    }
    s->prev_valid = 1;
}

/* ── Main-screen diff (relative moves + cursor restore) ──────────── */

static void
diff_main(screen_t *s, bytes_t *out, int force_clear, int effective_h) {
    uint16_t cur_style_id = 0;
    int virt_x = s->virt_x;
    int virt_y = s->virt_y;

    /* Clamp effective_h: must be in [1, s->h]. */
    if (effective_h < 1 || effective_h > s->h) effective_h = s->h;

    /* first_render: true only when terminal cursor position is unknown.
     * After force_clear, the cursor is at (0,0) so we can use relative moves.
     * first_render uses \r\n to scroll rows into existence safely. */
    int first_render = (!s->prev_valid && !force_clear);

    /* Preamble: return physical cursor from display position to virt position. */
    if (s->has_display) {
        emit_relative_move(out, s->display_x, s->display_y,
                           virt_x, virt_y, s->w);
    }
    s->has_display = 0;

    /* Frame header. */
    if (force_clear) {
        /* Resize: clear screen, home cursor. */
        bytes_append_cstr(out, "\x1b[H\x1b[2J\x1b[0m");
        virt_x = 0; virt_y = 0;
        s->prev_valid = 0;
    } else if (first_render) {
        /* First frame: ensure column 0 without advancing a line.
         * The shell already left the cursor on a fresh line; adding \n
         * would create a spurious blank row before the TUI content. */
        bytes_append(out, "\r", 1);
        virt_x = 0; virt_y = 0;
    }

    /* Content rendering. */

    /* Growth extension: when content height increases on an incremental frame,
     * the new rows at the bottom haven't been claimed yet. CUD clamps at the
     * terminal bottom and won't create new lines; \r\n will scroll if needed.
     * Emit one \r\n per new row from the current bottom to claim them. */
    if (s->prev_valid && !force_clear && effective_h > s->prev_effective_h) {
        /* virt_x/virt_y is currently (0, prev_effective_h-1) after preamble. */
        int grow = effective_h - s->prev_effective_h;
        for (int i = 0; i < grow; i++) {
            bytes_append(out, "\r\n", 2);
        }
        virt_x = 0;
        virt_y = effective_h - 1;
    }

    if (first_render) {
        /* First render: advance rows with \r\n so the viewport scrolls to
         * make room. Only claim effective_h rows — don't scroll blank rows
         * into existence. CUD is NOT used here because the cursor may be at
         * the terminal bottom; CUD clamps and would collapse all rows. */
        for (int y = 0; y < effective_h; y++) {
            if (y > 0) {
                bytes_append(out, "\r\n", 2);
                virt_x = 0;
                virt_y = y;
            }
            for (int x = 0; x < s->w; x++) {
                const cell_t *c = cell_at(s->next, s->w, x, y);
                if (c->len == 0) continue;  /* WIDE_TAIL: skip */
                if (x > virt_x) {
                    bytes_append_csi_n(out, x - virt_x, 'C');
                } else if (x < virt_x) {
                    bytes_append(out, "\r", 1);
                    if (x > 0) bytes_append_csi_n(out, x, 'C');
                }
                virt_x = x;
                emit_sgr(out, &s->pool, s->color_level, &cur_style_id, c->style_id);
                const uint8_t *p; size_t n;
                cell_bytes(c, &s->next_slab, &p, &n);
                bytes_append(out, p, n);
                virt_x += c->width;
            }
            reset_sgr(out, &cur_style_id);
        }
        virt_y = effective_h - 1;
    } else if (!s->prev_valid) {
        /* Full redraw after force_clear: cursor is at (0,0), safe to use
         * emit_relative_move for all cells. Only redraw effective_h rows;
         * rows beyond are already blank from the terminal clear. */
        for (int y = 0; y < effective_h; y++) {
            for (int x = 0; x < s->w; x++) {
                const cell_t *c = cell_at(s->next, s->w, x, y);
                if (c->len == 0) continue;
                emit_relative_move(out, virt_x, virt_y, x, y, s->w);
                virt_x = x; virt_y = y;
                emit_sgr(out, &s->pool, s->color_level, &cur_style_id, c->style_id);
                const uint8_t *p; size_t n;
                cell_bytes(c, &s->next_slab, &p, &n);
                bytes_append(out, p, n);
                virt_x += c->width;
            }
            reset_sgr(out, &cur_style_id);
        }
    } else {
        /* Segment-merge incremental diff with relative moves instead of CUP.
         * Skip rows untouched in both next and prev; within dirty rows only
         * scan up to the rightmost relevant column. */
        for (int y = 0; y < s->h; y++) {
            int dx = s->dirty_xmax[y];
            int px = s->prev_xmax[y];
            if (dx < 0 && px < 0) continue;
            int x_end = (dx > px ? dx : px) + 1;
            int run_start = -1;
            int last_change = -1;

            for (int x = 0; x < x_end; x++) {
                const cell_t *cn = cell_at(s->next, s->w, x, y);
                const cell_t *cp = cell_at(s->prev, s->w, x, y);
                int changed = !cell_eq(cn, &s->next_slab, cp, &s->prev_slab);
                if (cn->len == 0) changed = 0;

                if (!changed) continue;

                if (run_start < 0) {
                    /* open new run */
                    emit_relative_move(out, virt_x, virt_y, x, y, s->w);
                    virt_x = x; virt_y = y;
                    emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                    const uint8_t *p; size_t n;
                    cell_bytes(cn, &s->next_slab, &p, &n);
                    bytes_append(out, p, n);
                    virt_x = x + cn->width;
                    run_start = x;
                    last_change = x;
                    if (cn->width == 2) x++;
                } else {
                    int gap = x - last_change - 1;
                    if (gap <= MERGE_GAP) {
                        /* bridge: emit unchanged cells; cursor ends up at x */
                        for (int k = last_change + 1; k < x; k++) {
                            const cell_t *bc = cell_at(s->next, s->w, k, y);
                            if (bc->len == 0) continue;
                            emit_sgr(out, &s->pool, s->color_level, &cur_style_id, bc->style_id);
                            const uint8_t *bp; size_t bn;
                            cell_bytes(bc, &s->next_slab, &bp, &bn);
                            bytes_append(out, bp, bn);
                        }
                        virt_x = x;
                        emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(out, p, n);
                        virt_x = x + cn->width;
                        last_change = x;
                        if (cn->width == 2) x++;
                    } else {
                        /* gap too big: new run */
                        emit_relative_move(out, virt_x, virt_y, x, y, s->w);
                        virt_x = x; virt_y = y;
                        emit_sgr(out, &s->pool, s->color_level, &cur_style_id, cn->style_id);
                        const uint8_t *p; size_t n;
                        cell_bytes(cn, &s->next_slab, &p, &n);
                        bytes_append(out, p, n);
                        virt_x = x + cn->width;
                        run_start = x;
                        last_change = x;
                        if (cn->width == 2) x++;
                    }
                }
            }
        }
    }

    /* Final SGR reset. */
    reset_sgr(out, &cur_style_id);

    /* Cursor restore: move to (0, effective_h-1) — the last claimed row.
     * Never scrolls. Subsequent frames start here and use CUU to reach row 0. */
    emit_relative_move(out, virt_x, virt_y, 0, effective_h - 1, s->w);
    s->virt_x = 0;
    s->virt_y = effective_h - 1;
    s->prev_effective_h = effective_h;

    /* Swap buffers (same as diff_alt). */
    cell_t *tc = s->prev; s->prev = s->next; s->next = tc;
    slab_t tmp_slab = s->prev_slab;
    s->prev_slab = s->next_slab;
    s->next_slab = tmp_slab;
    slab_reset(&s->next_slab);
    fill_space(s->next, s->w * s->h);
    s->next_clean = 1;
    /* Swap dirty tracking arrays. */
    {
        int *tmp = s->prev_xmax;
        s->prev_xmax  = s->dirty_xmax;
        s->dirty_xmax = tmp;
        dirty_xmax_init(s->dirty_xmax, s->h);
    }
    s->prev_valid = 1;
}

/* ── Lua API: diff ───────────────────────────────────────────────── */

static int
l_diff(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int force_clear = lua_toboolean(L, 2);  /* optional; false when absent */
    /* Optional effective height (content rows). 0 or absent → use s->h. */
    int effective_h = (int)luaL_optinteger(L, 3, 0);
    bytes_t out = {0};

    if (s->mode == SCREEN_MODE_MAIN)
        diff_main(s, &out, force_clear, effective_h);
    else
        diff_alt(s, &out);

    if (out.size == 0)
        lua_pushlstring(L, "", 0);
    else
        lua_pushlstring(L, (const char *)out.buf, out.size);
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
l_rows(lua_State *L) {
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
        if (!nb) TUI_FATAL(L, "screen.rows: out of memory");
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

/* ── Lua API: set_mode / cursor_pos / set_display_cursor ─────────── */

static int
l_set_mode(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    const char *mode = luaL_checkstring(L, 2);
    if (strcmp(mode, "main") == 0) {
        s->mode = SCREEN_MODE_MAIN;
    } else if (strcmp(mode, "alt") == 0) {
        s->mode = SCREEN_MODE_ALT;
    } else {
        return TUI_FATAL(L, "screen.set_mode: unknown mode '%s'", mode);
    }
    /* Reset virtual cursor state when switching modes. */
    s->virt_x = 0; s->virt_y = 0;
    s->display_x = -1; s->display_y = -1;
    s->has_display = 0;
    return 0;
}

/* Returns x, y — the virtual cursor position after the last cursor_restore.
 * Lua uses this to compute a relative move for the TextInput cursor. */
static int
l_cursor_pos(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    lua_pushinteger(L, s->virt_x);
    lua_pushinteger(L, s->virt_y);
    return 2;
}

/* Records where the TextInput cursor was placed (0-based).
 * Pass x=-1, y=-1 to clear (no declared cursor). */
static int
l_set_display_cursor(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    if (x < 0 || y < 0) {
        s->has_display = 0;
        s->display_x = -1; s->display_y = -1;
    } else {
        s->has_display = 1;
        s->display_x = x;
        s->display_y = y;
    }
    return 0;
}

static int
l_gc(lua_State *L) {
    screen_t *s = (screen_t *)luaL_checkudata(L, 1, SCREEN_MT);
    free(s->next); s->next = NULL;
    free(s->prev); s->prev = NULL;
    slab_free(&s->next_slab);
    slab_free(&s->prev_slab);
    row_pool_free(&s->rows);
    pool_free(&s->pool);
    free(s->dirty_xmax); s->dirty_xmax = NULL;
    free(s->prev_xmax);  s->prev_xmax  = NULL;
    return 0;
}

/* ── Lua API: cells ──────────────────────────────────────────────
 * cells(ud, row) -> array of {char, width, bold, dim, underline,
 *                              inverse, italic, strikethrough, fg, bg}
 * row is 1-based.  Wide-tail slots are skipped so the output array has
 * one entry per visible column position (head cells only).
 *
 * fg/bg format (new):
 *   nil            → terminal default
 *   integer 0..15  → 16-color index
 *   integer 16..255 → 256-color index
 *   string "#RRGGBB" → 24-bit truecolor */
static int
l_cells(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int row = (int)luaL_checkinteger(L, 2);
    if (row < 1 || row > s->h)
        return luaL_error(L, "screen.cells: row %d out of range [1,%d]", row, s->h);

    /* Use the committed prev buffer; fall back to next if no diff yet. */
    const cell_t *cells = s->prev_valid ? s->prev : s->next;
    const slab_t *slab  = s->prev_valid ? &s->prev_slab : &s->next_slab;
    int y = row - 1;

    lua_createtable(L, s->w, 0);
    int col = 1;
    for (int x = 0; x < s->w; x++) {
        const cell_t *c = cell_at((cell_t *)cells, s->w, x, y);
        if (c->len == 0) continue;  /* WIDE_TAIL: skip */

        const style_entry_t *se = pool_get(&s->pool, c->style_id);

        lua_createtable(L, 0, 10);

        const uint8_t *p; size_t n;
        cell_bytes(c, slab, &p, &n);
        lua_pushlstring(L, (const char *)p, n);
        lua_setfield(L, -2, "char");

        lua_pushinteger(L, c->width);
        lua_setfield(L, -2, "width");

        lua_pushboolean(L, (se->attrs & ATTR_BOLD)          != 0);
        lua_setfield(L, -2, "bold");
        lua_pushboolean(L, (se->attrs & ATTR_DIM)           != 0);
        lua_setfield(L, -2, "dim");
        lua_pushboolean(L, (se->attrs & ATTR_UNDERLINE)     != 0);
        lua_setfield(L, -2, "underline");
        lua_pushboolean(L, (se->attrs & ATTR_INVERSE)       != 0);
        lua_setfield(L, -2, "inverse");
        lua_pushboolean(L, (se->attrs & ATTR_ITALIC)        != 0);
        lua_setfield(L, -2, "italic");
        lua_pushboolean(L, (se->attrs & ATTR_STRIKETHROUGH) != 0);
        lua_setfield(L, -2, "strikethrough");

        /* fg */
        if (se->fg_mode == COLOR_MODE_DEFAULT) {
            lua_pushnil(L);
        } else if (se->fg_mode == COLOR_MODE_24BIT) {
            char hex[8];
            snprintf(hex, sizeof(hex), "#%06X", se->fg_val & 0xFFFFFFu);
            lua_pushstring(L, hex);
        } else {
            lua_pushinteger(L, (lua_Integer)se->fg_val);
        }
        lua_setfield(L, -2, "fg");

        /* bg */
        if (se->bg_mode == COLOR_MODE_DEFAULT) {
            lua_pushnil(L);
        } else if (se->bg_mode == COLOR_MODE_24BIT) {
            char hex[8];
            snprintf(hex, sizeof(hex), "#%06X", se->bg_val & 0xFFFFFFu);
            lua_pushstring(L, hex);
        } else {
            lua_pushinteger(L, (lua_Integer)se->bg_val);
        }
        lua_setfield(L, -2, "bg");

        lua_rawseti(L, -2, col);
        col++;
    }
    return 1;
}

/* ── Lua API: intern_style / set_color_level ─────────────────────
 *
 * intern_style(ud, fg_mode, fg_val, bg_mode, bg_val, attrs) -> style_id
 *   fg_mode / bg_mode: 0=default 1=16-color 2=256-color 3=24bit
 *   fg_val / bg_val:   integer color value (0xRRGGBB for 24bit, 0..255 etc.)
 *   attrs:             ATTR_* bitmask (no FG/BG DEFAULT bits)
 *   returns: uint16 style_id for use with put/put_border/draw_line
 *
 * set_color_level(ud, level)
 *   level: 0=16-color 1=256-color 2=24bit-truecolor
 */
static int
l_intern_style(lua_State *L) {
    screen_t *s  = check_screen(L, 1);
    uint8_t  fg_mode = (uint8_t)luaL_checkinteger(L, 2);
    uint32_t fg_val  = (uint32_t)luaL_checkinteger(L, 3);
    uint8_t  bg_mode = (uint8_t)luaL_checkinteger(L, 4);
    uint32_t bg_val  = (uint32_t)luaL_checkinteger(L, 5);
    uint8_t  attrs   = (uint8_t)luaL_checkinteger(L, 6);
    uint16_t id = style_intern(&s->pool, fg_mode, fg_val, bg_mode, bg_val, attrs);
    lua_pushinteger(L, (lua_Integer)id);
    return 1;
}

static int
l_set_color_level(lua_State *L) {
    screen_t *s = check_screen(L, 1);
    int level = (int)luaL_checkinteger(L, 2);
    if (level < COLOR_LEVEL_16 || level > COLOR_LEVEL_24BIT)
        return luaL_error(L, "screen.set_color_level: level must be 0, 1, or 2");
    s->color_level = level;
    return 0;
}

/* ── registration ─────────────────────────────────────────────── */

static const luaL_Reg screen_lib[] = {
    {"new",        l_new},
    {"size",       l_size},
    {"resize",     l_resize},
    {"invalidate", l_invalidate},
    {"clear",      l_clear},
    {"put",        l_put},
    {"put_border", l_put_border},
    {"draw_line",  l_draw_line},
    {"diff",       l_diff},
    {"rows",       l_rows},
    {"cells",      l_cells},
    {"set_mode",          l_set_mode},
    {"cursor_pos",        l_cursor_pos},
    {"set_display_cursor", l_set_display_cursor},
    {"intern_style",      l_intern_style},
    {"set_color_level",   l_set_color_level},
    {NULL, NULL},
};

int
tui_open_screen(lua_State *L) {
    /* metatable for the screen userdata */
    if (luaL_newmetatable(L, SCREEN_MT)) {
        lua_pushcfunction(L, l_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);

    luaL_newlib(L, screen_lib);
    return 1;
}
