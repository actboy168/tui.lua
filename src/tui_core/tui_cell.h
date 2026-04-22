/*
 * tui_cell.h — shared cell / style / slab / bytes type definitions
 * and helper functions for tui_screen.c and tui_vterm.c.
 */

#ifndef TUI_CELL_H
#define TUI_CELL_H

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* ── SGR attribute bitmask ───────────────────────────────────── */

#define ATTR_BOLD          0x01u
#define ATTR_DIM           0x02u
#define ATTR_UNDERLINE     0x04u
#define ATTR_INVERSE       0x08u
#define ATTR_ITALIC        0x40u
#define ATTR_STRIKETHROUGH 0x80u
#define ATTR_STYLE_MASK    (ATTR_BOLD | ATTR_DIM | ATTR_UNDERLINE | ATTR_INVERSE \
                            | ATTR_ITALIC | ATTR_STRIKETHROUGH)

/* ── Color mode / level ─────────────────────────────────────── */

#define COLOR_MODE_DEFAULT  0u
#define COLOR_MODE_16       1u
#define COLOR_MODE_256      2u
#define COLOR_MODE_24BIT    3u

#define COLOR_LEVEL_16    0
#define COLOR_LEVEL_256   1
#define COLOR_LEVEL_24BIT 2

/* ── cell_t — 12-byte display cell ──────────────────────────── */

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
    uint16_t style_id;  /* style pool index; 0 = default */
} cell_t;

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(cell_t) == 12, "cell_t must be 12 bytes");
#endif

/* ── slab_t — variable-length byte store ────────────────────── */

typedef struct {
    uint8_t *buf;
    uint32_t size;
    uint32_t cap;
} slab_t;

/* ── style_entry_t / style_pool_t ───────────────────────────── */

typedef struct {
    uint32_t fg_val;
    uint32_t bg_val;
    uint8_t  fg_mode;
    uint8_t  bg_mode;
    uint8_t  attrs;
    uint8_t  _pad;
} style_entry_t;

typedef struct {
    style_entry_t *entries;
    uint32_t       count;
    uint32_t       cap;
} style_pool_t;

/* ── Shared helpers ─────────────────────────────────────────── */

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

static inline void
fill_space(cell_t *buf, int n) {
    for (int i = 0; i < n; i++) {
        cell_t *c = &buf[i];
        memset(c, 0, sizeof(*c));
        c->u.inline_bytes[0] = ' ';
        c->len   = 1;
        c->width = 1;
    }
}

static inline void
cell_bytes(const cell_t *c, const slab_t *slab,
           const uint8_t **out, uint32_t *out_len) {
    if (c->len == 0xFF) {
        *out     = slab->buf + c->u.ext.slab_off;
        *out_len = c->u.ext.slab_len;
    } else {
        *out     = c->u.inline_bytes;
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

static inline uint32_t
slab_push(slab_t *s, const uint8_t *p, uint32_t n) {
    if (s->size + n > s->cap) {
        uint32_t need = s->size + n;
        uint32_t ncap = s->cap ? s->cap * 2 : 256;
        while (ncap < need) ncap *= 2;
        uint8_t *nb = (uint8_t *)realloc(s->buf, ncap);
        if (!nb) return 0xFFFFFFFFu;
        s->buf = nb;
        s->cap = ncap;
    }
    uint32_t off = s->size;
    memcpy(s->buf + off, p, n);
    s->size += n;
    return off;
}

static inline void
slab_free(slab_t *s) {
    free(s->buf);
    s->buf = NULL;
    s->size = 0;
    s->cap = 0;
}

static inline const style_entry_t *
pool_get(const style_pool_t *p, uint16_t id) {
    static const style_entry_t DEFAULT = {0, 0, 0, 0, 0, 0};
    if (id == 0 || (uint32_t)(id - 1) >= p->count)
        return &DEFAULT;
    return &p->entries[id - 1];
}

static inline uint16_t
style_intern(style_pool_t *p,
             uint8_t fg_mode, uint32_t fg_val,
             uint8_t bg_mode, uint32_t bg_val,
             uint8_t attrs) {
    if (fg_mode == COLOR_MODE_DEFAULT &&
        bg_mode == COLOR_MODE_DEFAULT && attrs == 0)
        return 0;
    for (uint32_t i = 0; i < p->count; i++) {
        const style_entry_t *e = &p->entries[i];
        if (e->fg_mode == fg_mode && e->fg_val == fg_val &&
            e->bg_mode == bg_mode && e->bg_val == bg_val &&
            e->attrs   == attrs)
            return (uint16_t)(i + 1);
    }
    if (p->count >= p->cap) {
        uint32_t ncap = p->cap ? p->cap * 2 : 64;
        if (ncap > 65534u) ncap = 65534u;
        style_entry_t *ne = (style_entry_t *)realloc(p->entries,
                                                      ncap * sizeof(style_entry_t));
        if (!ne) return 0;
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

static inline void
pool_free(style_pool_t *p) {
    free(p->entries);
    p->entries = NULL;
    p->count = p->cap = 0;
}

#endif /* TUI_CELL_H */
