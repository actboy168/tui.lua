/*
 * tui_vterm.c — Virtual Terminal Emulator in C.
 *
 * Reuses cell_t and style_pool_t from tui_cell.h for zero-allocation
 * per-cell storage. ANSI sequences are parsed byte-by-byte in C.
 *
 * Registered as `tui_core.vterm`.
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>

#include "tui_cell.h"

#define VTERM_MT "tui_core.vterm"

/* ── vterm_t ─────────────────────────────────────────────────── */

typedef struct {
    int cols, rows;
    int cursor_col, cursor_row;  /* 1-based */
    int cursor_visible;
    int cursor_style;  /* 0=block, 1=underline, 2=bar */
    int wrap_pending;
    int scroll_top, scroll_bottom;  /* 1-based, inclusive */
    cell_t *cells;
    slab_t cell_slab;
    style_pool_t pool;
    style_entry_t current_style;
    uint16_t write_style_id;
    struct {
        int col, row, visible;
        style_entry_t style;
        uint16_t style_id;
    } saved_cursor;
    struct {
        int raw;
        int mouse;
        int bracketed_paste;
        int focus_events;
        int kkp;
        int alternate_screen;
        int synchronized_output;
    } mode;
    char *title;
    /* Parser state */
    int parser_state;
    uint8_t parser_buf[64];
    int parser_buf_len;
    uint8_t parser_intermediate[8];
    int parser_intermediate_len;
    uint8_t parser_osc[4096];
    int parser_osc_len;
    uint8_t parser_final;
    /* UTF-8 state */
    uint8_t utf8_buf[4];
    int utf8_needed;
    int utf8_have;
} vterm_t;

/* Parser states */
enum {
    PS_GROUND,
    PS_ESC,
    PS_CSI_ENTRY,
    PS_CSI_PARAM,
    PS_CSI_INTERMEDIATE,
    PS_OSC_STRING,
    PS_OSC_ESC,
    PS_DCS_STRING,
    PS_DCS_ESC,
};

/* ── helpers ─────────────────────────────────────────────────── */

static inline cell_t *
vt_cell_at(vterm_t *vt, int col, int row) {
    return &vt->cells[(row - 1) * vt->cols + (col - 1)];
}

static void
vt_fill_row(vterm_t *vt, int row) {
    cell_t *r = vt_cell_at(vt, 1, row);
    for (int c = 0; c < vt->cols; c++) {
        cell_set_space(&r[c]);
    }
}

static void
vt_fill_screen(vterm_t *vt) {
    for (int r = 1; r <= vt->rows; r++) {
        vt_fill_row(vt, r);
    }
}

static void
vt_scroll_up(vterm_t *vt, int n) {
    if (n <= 0) return;
    int top = vt->scroll_top;
    int bottom = vt->scroll_bottom;
    int height = bottom - top + 1;
    if (n > height) n = height;
    int row_size = vt->cols * sizeof(cell_t);
    cell_t *top_ptr = vt_cell_at(vt, 1, top);
    memmove(top_ptr, top_ptr + n * vt->cols, (size_t)(height - n) * row_size);
    for (int r = bottom - n + 1; r <= bottom; r++) {
        vt_fill_row(vt, r);
    }
}

static void
vt_scroll_down(vterm_t *vt, int n) {
    if (n <= 0) return;
    int top = vt->scroll_top;
    int bottom = vt->scroll_bottom;
    int height = bottom - top + 1;
    if (n > height) n = height;
    int row_size = vt->cols * sizeof(cell_t);
    cell_t *top_ptr = vt_cell_at(vt, 1, top);
    memmove(top_ptr + n * vt->cols, top_ptr, (size_t)(height - n) * row_size);
    for (int r = top; r < top + n; r++) {
        vt_fill_row(vt, r);
    }
}

static void
vt_put_cell(vterm_t *vt, int col, int row, const uint8_t *bytes, int len, int width) {
    if (row < 1 || row > vt->rows || col < 1 || col > vt->cols) return;
    cell_t *c = vt_cell_at(vt, col, row);
    if (len <= 8) {
        memcpy(c->u.inline_bytes, bytes, len);
        c->len = (uint8_t)len;
    } else {
        uint32_t off = slab_push(&vt->cell_slab, bytes, len);
        if (off == 0xFFFFFFFFu) {
            c->len = 1;
            c->u.inline_bytes[0] = '?';
        } else {
            c->u.ext.slab_off = off;
            c->u.ext.slab_len = (uint16_t)len;
            c->len = 0xFF;
        }
    }
    c->width = (uint8_t)width;
    c->style_id = vt->write_style_id;
}

static void
vt_write_char(vterm_t *vt, const uint8_t *bytes, int len) {
    if (vt->wrap_pending) {
        vt->wrap_pending = 0;
        if (vt->cursor_row == vt->scroll_bottom) {
            vt_scroll_up(vt, 1);
        } else if (vt->cursor_row < vt->rows) {
            vt->cursor_row++;
        }
        vt->cursor_col = 1;
    }
    int w = (len == 1 && bytes[0] < 0x80) ? 1 : 2;  /* simplified width */
    vt_put_cell(vt, vt->cursor_col, vt->cursor_row, bytes, len, w);
    if (w == 2 && vt->cursor_col + 1 <= vt->cols) {
        /* Set WIDE_TAIL for the second column */
        cell_t *tail = vt_cell_at(vt, vt->cursor_col + 1, vt->cursor_row);
        tail->len = 0;
        tail->width = 0;
        tail->style_id = vt->write_style_id;
    }
    vt->cursor_col += w;
    if (vt->cursor_col > vt->cols) {
        vt->wrap_pending = 1;
        vt->cursor_col = vt->cols;
    }
}

static void
vt_update_style_id(vterm_t *vt) {
    vt->write_style_id = style_intern(&vt->pool,
        vt->current_style.fg_mode, vt->current_style.fg_val,
        vt->current_style.bg_mode, vt->current_style.bg_val,
        vt->current_style.attrs);
}

static void
vt_reset_style(vterm_t *vt) {
    vt->current_style.fg_mode = COLOR_MODE_DEFAULT;
    vt->current_style.bg_mode = COLOR_MODE_DEFAULT;
    vt->current_style.fg_val = 0;
    vt->current_style.bg_val = 0;
    vt->current_style.attrs = 0;
    vt->current_style._pad = 0;
    vt->write_style_id = 0;
}

static void
vt_reset(vterm_t *vt) {
    vt->cursor_col = 1;
    vt->cursor_row = 1;
    vt->cursor_visible = 1;
    vt->cursor_style = 0;
    vt->wrap_pending = 0;
    vt->scroll_top = 1;
    vt->scroll_bottom = vt->rows;
    vt_reset_style(vt);
    vt->saved_cursor.col = 1;
    vt->saved_cursor.row = 1;
    vt->saved_cursor.visible = 1;
    vt->saved_cursor.style = vt->current_style;
    vt->saved_cursor.style_id = 0;
    vt->mode.raw = 0;
    vt->mode.mouse = 0;
    vt->mode.bracketed_paste = 0;
    vt->mode.focus_events = 0;
    vt->mode.kkp = 0;
    vt->mode.alternate_screen = 0;
    vt->mode.synchronized_output = 0;
    free(vt->title);
    vt->title = NULL;
    slab_reset(&vt->cell_slab);
    pool_free(&vt->pool);
    vt_fill_screen(vt);
}

/* ── SGR handler ─────────────────────────────────────────────── */

static void
handle_sgr(vterm_t *vt, int *params, int nparams) {
    if (nparams == 0) {
        vt_reset_style(vt);
        return;
    }
    int i = 0;
    while (i < nparams) {
        int code = params[i];
        switch (code) {
        case 0:  vt_reset_style(vt); break;
        case 1:  vt->current_style.attrs |= ATTR_BOLD; break;
        case 2:  vt->current_style.attrs |= ATTR_DIM; break;
        case 3:  vt->current_style.attrs |= ATTR_ITALIC; break;
        case 4:  vt->current_style.attrs |= ATTR_UNDERLINE; break;
        case 5:  /* blink - no attr */ break;
        case 7:  vt->current_style.attrs |= ATTR_INVERSE; break;
        case 8:  /* hidden - no attr */ break;
        case 9:  vt->current_style.attrs |= ATTR_STRIKETHROUGH; break;
        case 21: vt->current_style.attrs |= ATTR_UNDERLINE; break;
        case 22: vt->current_style.attrs &= ~(ATTR_BOLD | ATTR_DIM); break;
        case 23: vt->current_style.attrs &= ~ATTR_ITALIC; break;
        case 24: vt->current_style.attrs &= ~ATTR_UNDERLINE; break;
        case 25: /* blink off */ break;
        case 27: vt->current_style.attrs &= ~ATTR_INVERSE; break;
        case 28: /* hidden off */ break;
        case 29: vt->current_style.attrs &= ~ATTR_STRIKETHROUGH; break;
        case 30: case 31: case 32: case 33:
        case 34: case 35: case 36: case 37:
            vt->current_style.fg_mode = COLOR_MODE_16;
            vt->current_style.fg_val = (uint32_t)(code - 30);
            break;
        case 38:
            if (i + 1 < nparams) {
                if (params[i + 1] == 2 && i + 4 < nparams) {
                    vt->current_style.fg_mode = COLOR_MODE_24BIT;
                    vt->current_style.fg_val =
                        ((uint32_t)params[i + 2] << 16) |
                        ((uint32_t)params[i + 3] << 8) |
                        (uint32_t)params[i + 4];
                    i += 4;
                } else if (params[i + 1] == 5 && i + 2 < nparams) {
                    vt->current_style.fg_mode = COLOR_MODE_256;
                    vt->current_style.fg_val = (uint32_t)params[i + 2];
                    i += 2;
                }
            }
            break;
        case 39:
            vt->current_style.fg_mode = COLOR_MODE_DEFAULT;
            vt->current_style.fg_val = 0;
            break;
        case 40: case 41: case 42: case 43:
        case 44: case 45: case 46: case 47:
            vt->current_style.bg_mode = COLOR_MODE_16;
            vt->current_style.bg_val = (uint32_t)(code - 40);
            break;
        case 48:
            if (i + 1 < nparams) {
                if (params[i + 1] == 2 && i + 4 < nparams) {
                    vt->current_style.bg_mode = COLOR_MODE_24BIT;
                    vt->current_style.bg_val =
                        ((uint32_t)params[i + 2] << 16) |
                        ((uint32_t)params[i + 3] << 8) |
                        (uint32_t)params[i + 4];
                    i += 4;
                } else if (params[i + 1] == 5 && i + 2 < nparams) {
                    vt->current_style.bg_mode = COLOR_MODE_256;
                    vt->current_style.bg_val = (uint32_t)params[i + 2];
                    i += 2;
                }
            }
            break;
        case 49:
            vt->current_style.bg_mode = COLOR_MODE_DEFAULT;
            vt->current_style.bg_val = 0;
            break;
        case 90: case 91: case 92: case 93:
        case 94: case 95: case 96: case 97:
            vt->current_style.fg_mode = COLOR_MODE_16;
            vt->current_style.fg_val = (uint32_t)(code - 90 + 8);
            break;
        case 100: case 101: case 102: case 103:
        case 104: case 105: case 106: case 107:
            vt->current_style.bg_mode = COLOR_MODE_16;
            vt->current_style.bg_val = (uint32_t)(code - 100 + 8);
            break;
        }
        i++;
    }
    vt_update_style_id(vt);
}

/* ── CSI actions ─────────────────────────────────────────────── */

static void
csi_cup(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int row = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int col = (nparams > 1 && params[1] > 0) ? params[1] : 1;
    if (row < 1) row = 1; if (row > vt->rows) row = vt->rows;
    if (col < 1) col = 1; if (col > vt->cols) col = vt->cols;
    vt->cursor_row = row;
    vt->cursor_col = col;
    vt->wrap_pending = 0;
}

static void
csi_cuu(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_row -= n;
    if (vt->cursor_row < 1) vt->cursor_row = 1;
    vt->wrap_pending = 0;
}

static void
csi_cud(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_row += n;
    if (vt->cursor_row > vt->rows) vt->cursor_row = vt->rows;
    vt->wrap_pending = 0;
}

static void
csi_cuf(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_col += n;
    if (vt->cursor_col > vt->cols) vt->cursor_col = vt->cols;
    vt->wrap_pending = 0;
}

static void
csi_cub(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_col -= n;
    if (vt->cursor_col < 1) vt->cursor_col = 1;
    vt->wrap_pending = 0;
}

static void
csi_cnl(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_row += n;
    if (vt->cursor_row > vt->rows) vt->cursor_row = vt->rows;
    vt->cursor_col = 1;
    vt->wrap_pending = 0;
}

static void
csi_cpl(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt->cursor_row -= n;
    if (vt->cursor_row < 1) vt->cursor_row = 1;
    vt->cursor_col = 1;
    vt->wrap_pending = 0;
}

static void
csi_cha(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    if (n < 1) n = 1; if (n > vt->cols) n = vt->cols;
    vt->cursor_col = n;
    vt->wrap_pending = 0;
}

static void
csi_vpa(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    if (n < 1) n = 1; if (n > vt->rows) n = vt->rows;
    vt->cursor_row = n;
    vt->wrap_pending = 0;
}

static void
csi_ed(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0) ? params[0] : 0;
    int cr = vt->cursor_row;
    int cc = vt->cursor_col;
    if (n == 0) {
        for (int c = cc; c <= vt->cols; c++)
            cell_set_space(vt_cell_at(vt, c, cr));
        for (int r = cr + 1; r <= vt->rows; r++)
            vt_fill_row(vt, r);
    } else if (n == 1) {
        for (int r = 1; r < cr; r++)
            vt_fill_row(vt, r);
        for (int c = 1; c <= cc; c++)
            cell_set_space(vt_cell_at(vt, c, cr));
    } else if (n == 2 || n == 3) {
        vt_fill_screen(vt);
    }
}

static void
csi_el(vterm_t *vt, int *params, int nparams) {
    (void)nparams;
    int n = (nparams > 0) ? params[0] : 0;
    int cr = vt->cursor_row;
    if (n == 0) {
        for (int c = vt->cursor_col; c <= vt->cols; c++)
            cell_set_space(vt_cell_at(vt, c, cr));
    } else if (n == 1) {
        for (int c = 1; c <= vt->cursor_col; c++)
            cell_set_space(vt_cell_at(vt, c, cr));
    } else if (n == 2) {
        for (int c = 1; c <= vt->cols; c++)
            cell_set_space(vt_cell_at(vt, c, cr));
    }
}

static void
csi_sgr(vterm_t *vt, int *params, int nparams) {
    handle_sgr(vt, params, nparams);
}

static void
csi_decstbm(vterm_t *vt, int *params, int nparams) {
    int top = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int bottom = (nparams > 1 && params[1] > 0) ? params[1] : vt->rows;
    if (top < 1) top = 1; if (top > vt->rows) top = vt->rows;
    if (bottom < 1) bottom = 1; if (bottom > vt->rows) bottom = vt->rows;
    if (top > bottom) { int t = top; top = bottom; bottom = t; }
    vt->scroll_top = top;
    vt->scroll_bottom = bottom;
}

static void
csi_su(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt_scroll_up(vt, n);
}

static void
csi_sd(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    vt_scroll_down(vt, n);
}

static void
csi_decscusr(vterm_t *vt, int *params, int nparams, const uint8_t *intermediate, int ilen) {
    (void)intermediate; (void)ilen;
    if (ilen > 0 && intermediate[0] != ' ') return;
    int n = (nparams > 0) ? params[0] : 1;
    if (n == 1 || n == 2) vt->cursor_style = 0;
    else if (n == 3 || n == 4) vt->cursor_style = 1;
    else if (n == 5 || n == 6) vt->cursor_style = 2;
}

static void
csi_dsr(vterm_t *vt, int *params, int nparams) {
    if (nparams > 0 && params[0] == 6) {
        /* Enqueue CPR: ESC [ row ; col R */
        lua_State *L = NULL;  /* We'll use a different approach */
        (void)L;
        char resp[32];
        snprintf(resp, sizeof(resp), "\x1b[%d;%dR", vt->cursor_row, vt->cursor_col);
        /* Push to input_queue via Lua */
    }
}

static void
csi_decset(vterm_t *vt, int *params, int nparams) {
    for (int i = 0; i < nparams; i++) {
        int p = params[i];
        if (p == 1000 || p == 1002 || p == 1003) {
            vt->mode.mouse++;
        } else if (p == 1004) {
            vt->mode.focus_events = 1;
        } else if (p == 2004) {
            vt->mode.bracketed_paste = 1;
        } else if (p == 2026) {
            vt->mode.synchronized_output++;
        } else if (p == 1049) {
            vt->mode.alternate_screen = 1;
        }
    }
}

static void
csi_decrst(vterm_t *vt, int *params, int nparams) {
    for (int i = 0; i < nparams; i++) {
        int p = params[i];
        if (p == 1000 || p == 1002 || p == 1003) {
            if (vt->mode.mouse > 0) vt->mode.mouse--;
        } else if (p == 1004) {
            vt->mode.focus_events = 0;
        } else if (p == 2004) {
            vt->mode.bracketed_paste = 0;
        } else if (p == 2026) {
            if (vt->mode.synchronized_output > 0) vt->mode.synchronized_output--;
        } else if (p == 1049) {
            vt->mode.alternate_screen = 0;
        }
    }
}

static void
csi_ich(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int row = vt->cursor_row;
    int col = vt->cursor_col;
    cell_t *r = vt_cell_at(vt, 1, row);
    if (n > vt->cols - col + 1) n = vt->cols - col + 1;
    for (int c = vt->cols - 1; c >= col + n - 1; c--) {
        r[c] = r[c - n];
    }
    for (int c = col - 1; c < col + n - 1 && c < vt->cols; c++) {
        cell_set_space(&r[c]);
    }
}

static void
csi_dch(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int row = vt->cursor_row;
    int col = vt->cursor_col;
    cell_t *r = vt_cell_at(vt, 1, row);
    if (n > vt->cols - col + 1) n = vt->cols - col + 1;
    for (int c = col - 1; c < vt->cols - n; c++) {
        r[c] = r[c + n];
    }
    for (int c = vt->cols - n; c < vt->cols; c++) {
        cell_set_space(&r[c]);
    }
}

static void
csi_il(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int row = vt->cursor_row;
    int bottom = vt->scroll_bottom;
    int height = bottom - row + 1;
    if (n > height) n = height;
    int row_size = vt->cols * sizeof(cell_t);
    cell_t *top_ptr = vt_cell_at(vt, 1, row);
    memmove(top_ptr + n * vt->cols, top_ptr, (size_t)(height - n) * row_size);
    for (int r = row; r < row + n; r++) {
        vt_fill_row(vt, r);
    }
}

static void
csi_dl(vterm_t *vt, int *params, int nparams) {
    int n = (nparams > 0 && params[0] > 0) ? params[0] : 1;
    int row = vt->cursor_row;
    int bottom = vt->scroll_bottom;
    int height = bottom - row + 1;
    if (n > height) n = height;
    int row_size = vt->cols * sizeof(cell_t);
    cell_t *top_ptr = vt_cell_at(vt, 1, row);
    memmove(top_ptr, top_ptr + n * vt->cols, (size_t)(height - n) * row_size);
    for (int r = bottom - n + 1; r <= bottom; r++) {
        vt_fill_row(vt, r);
    }
}

/* ── Parser ──────────────────────────────────────────────────── */

static inline int
is_csi_param(uint8_t b) { return b >= 0x30 && b <= 0x3F; }
static inline int
is_csi_intermediate(uint8_t b) { return b >= 0x20 && b <= 0x2F; }
static inline int
is_csi_final(uint8_t b) { return b >= 0x40 && b <= 0x7E; }

static void
parser_reset(vterm_t *vt) {
    vt->parser_buf_len = 0;
    vt->parser_intermediate_len = 0;
    vt->parser_osc_len = 0;
    vt->parser_final = 0;
}

static void
execute_csi(vterm_t *vt) {
    uint8_t final = vt->parser_final;
    if (!final) return;

    int params[32];
    int nparams = 0;
    int has_question = 0;

    if (vt->parser_buf_len > 0) {
        int i = 0;
        if (vt->parser_buf[0] == '?') {
            has_question = 1;
            i = 1;
        }
        int cur = 0;
        int has_cur = 0;
        for (; i < vt->parser_buf_len; i++) {
            uint8_t b = vt->parser_buf[i];
            if (b == ';') {
                params[nparams++] = has_cur ? cur : 0;
                cur = 0;
                has_cur = 0;
            } else if (b >= '0' && b <= '9') {
                cur = cur * 10 + (b - '0');
                has_cur = 1;
            }
            if (nparams >= 32) break;
        }
        if (nparams < 32) {
            params[nparams++] = has_cur ? cur : 0;
        }
    }

    if (has_question) {
        if (final == 'h') csi_decset(vt, params, nparams);
        else if (final == 'l') csi_decrst(vt, params, nparams);
    } else {
        switch (final) {
        case 'H': csi_cup(vt, params, nparams); break;
        case 'A': csi_cuu(vt, params, nparams); break;
        case 'B': csi_cud(vt, params, nparams); break;
        case 'C': csi_cuf(vt, params, nparams); break;
        case 'D': csi_cub(vt, params, nparams); break;
        case 'E': csi_cnl(vt, params, nparams); break;
        case 'F': csi_cpl(vt, params, nparams); break;
        case 'G': csi_cha(vt, params, nparams); break;
        case 'd': csi_vpa(vt, params, nparams); break;
        case 'J': csi_ed(vt, params, nparams); break;
        case 'K': csi_el(vt, params, nparams); break;
        case 'm': csi_sgr(vt, params, nparams); break;
        case 'r': csi_decstbm(vt, params, nparams); break;
        case 'S': csi_su(vt, params, nparams); break;
        case 'T': csi_sd(vt, params, nparams); break;
        case 'q': csi_decscusr(vt, params, nparams, vt->parser_intermediate, vt->parser_intermediate_len); break;
        case 'n': csi_dsr(vt, params, nparams); break;
        case '@': csi_ich(vt, params, nparams); break;
        case 'P': csi_dch(vt, params, nparams); break;
        case 'L': csi_il(vt, params, nparams); break;
        case 'M': csi_dl(vt, params, nparams); break;
        }
    }
    parser_reset(vt);
}

static void
execute_osc(vterm_t *vt) {
    /* OSC format: number ; payload */
    uint8_t *s = vt->parser_osc;
    int len = vt->parser_osc_len;
    int sep = -1;
    for (int i = 0; i < len; i++) {
        if (s[i] == ';') { sep = i; break; }
    }
    if (sep >= 0) {
        int osc_num = 0;
        for (int i = 0; i < sep; i++) {
            if (s[i] >= '0' && s[i] <= '9')
                osc_num = osc_num * 10 + (s[i] - '0');
        }
        if (osc_num == 0 || osc_num == 2) {
            free(vt->title);
            int plen = len - sep - 1;
            vt->title = (char *)malloc(plen + 1);
            if (vt->title) {
                memcpy(vt->title, s + sep + 1, plen);
                vt->title[plen] = '\0';
            }
        } else if (osc_num == 52) {
            /* clipboard - push to Lua table */
        }
    }
    parser_reset(vt);
}

static void
process_byte(vterm_t *vt, uint8_t b) {
    int ps = vt->parser_state;

    if (ps == PS_GROUND) {
        if (vt->utf8_needed > 0) {
            vt->utf8_buf[vt->utf8_have++] = b;
            if (vt->utf8_have >= vt->utf8_needed) {
                vt_write_char(vt, vt->utf8_buf, vt->utf8_have);
                vt->utf8_needed = 0;
            }
            return;
        }

        if (b == 0x1B) {
            parser_reset(vt);
            vt->parser_state = PS_ESC;
        } else if (b == 0x0D) {
            vt->cursor_col = 1;
            vt->wrap_pending = 0;
        } else if (b == 0x0A) {
            vt->wrap_pending = 0;
            vt->cursor_row++;
            if (vt->cursor_row > vt->scroll_bottom) {
                vt_scroll_up(vt, 1);
                vt->cursor_row = vt->scroll_bottom;
            } else if (vt->cursor_row > vt->rows) {
                vt->cursor_row = vt->rows;
            }
        } else if (b == 0x09) {
            int tab = 8;
            vt->cursor_col = ((vt->cursor_col - 1) / tab + 1) * tab + 1;
            if (vt->cursor_col > vt->cols) vt->cursor_col = vt->cols;
        } else if (b >= 0x20 && b <= 0x7E) {
            uint8_t ch = b;
            vt_write_char(vt, &ch, 1);
        } else if (b >= 0x80) {
            if (b < 0xE0) vt->utf8_needed = 2;
            else if (b < 0xF0) vt->utf8_needed = 3;
            else vt->utf8_needed = 4;
            vt->utf8_buf[0] = b;
            vt->utf8_have = 1;
        }
        return;
    }

    if (ps == PS_ESC) {
        if (b == 0x5B) { vt->parser_state = PS_CSI_ENTRY; }
        else if (b == 0x5D) { vt->parser_state = PS_OSC_STRING; }
        else if (b == 0x50) { vt->parser_state = PS_DCS_STRING; }
        else if (b == 0x37) { /* DECSC */
            vt->saved_cursor.col = vt->cursor_col;
            vt->saved_cursor.row = vt->cursor_row;
            vt->saved_cursor.visible = vt->cursor_visible;
            vt->saved_cursor.style = vt->current_style;
            vt->saved_cursor.style_id = vt->write_style_id;
            vt->parser_state = PS_GROUND;
        } else if (b == 0x38) { /* DECRC */
            vt->cursor_col = vt->saved_cursor.col;
            if (vt->cursor_col < 1) vt->cursor_col = 1;
            if (vt->cursor_col > vt->cols) vt->cursor_col = vt->cols;
            vt->cursor_row = vt->saved_cursor.row;
            if (vt->cursor_row < 1) vt->cursor_row = 1;
            if (vt->cursor_row > vt->rows) vt->cursor_row = vt->rows;
            vt->cursor_visible = vt->saved_cursor.visible;
            vt->current_style = vt->saved_cursor.style;
            vt->write_style_id = vt->saved_cursor.style_id;
            vt->wrap_pending = 0;
            vt->parser_state = PS_GROUND;
        } else if (b == 0x63) { /* RIS */
            vt_reset(vt);
            vt->parser_state = PS_GROUND;
        } else {
            vt->parser_state = PS_GROUND;
        }
        return;
    }

    if (ps == PS_CSI_ENTRY) {
        if (is_csi_param(b)) {
            if (vt->parser_buf_len < 64) vt->parser_buf[vt->parser_buf_len++] = b;
            vt->parser_state = PS_CSI_PARAM;
        } else if (is_csi_intermediate(b)) {
            if (vt->parser_intermediate_len < 8) vt->parser_intermediate[vt->parser_intermediate_len++] = b;
            vt->parser_state = PS_CSI_INTERMEDIATE;
        } else if (is_csi_final(b)) {
            vt->parser_final = b;
            execute_csi(vt);
            vt->parser_state = PS_GROUND;
        } else {
            vt->parser_state = PS_GROUND;
        }
        return;
    }

    if (ps == PS_CSI_PARAM) {
        if (is_csi_param(b)) {
            if (vt->parser_buf_len < 64) vt->parser_buf[vt->parser_buf_len++] = b;
        } else if (is_csi_intermediate(b)) {
            if (vt->parser_intermediate_len < 8) vt->parser_intermediate[vt->parser_intermediate_len++] = b;
            vt->parser_state = PS_CSI_INTERMEDIATE;
        } else if (is_csi_final(b)) {
            vt->parser_final = b;
            execute_csi(vt);
            vt->parser_state = PS_GROUND;
        } else {
            vt->parser_state = PS_GROUND;
        }
        return;
    }

    if (ps == PS_CSI_INTERMEDIATE) {
        if (is_csi_intermediate(b)) {
            if (vt->parser_intermediate_len < 8) vt->parser_intermediate[vt->parser_intermediate_len++] = b;
        } else if (is_csi_final(b)) {
            vt->parser_final = b;
            execute_csi(vt);
            vt->parser_state = PS_GROUND;
        } else {
            vt->parser_state = PS_GROUND;
        }
        return;
    }

    if (ps == PS_OSC_STRING) {
        if (b == 0x07) {
            execute_osc(vt);
            vt->parser_state = PS_GROUND;
        } else if (b == 0x1B) {
            vt->parser_state = PS_OSC_ESC;
        } else {
            if (vt->parser_osc_len < 4096) vt->parser_osc[vt->parser_osc_len++] = b;
        }
        return;
    }

    if (ps == PS_OSC_ESC) {
        if (b == 0x5C) {
            execute_osc(vt);
            vt->parser_state = PS_GROUND;
        } else {
            if (vt->parser_osc_len < 4096) vt->parser_osc[vt->parser_osc_len++] = 0x1B;
            if (vt->parser_osc_len < 4096) vt->parser_osc[vt->parser_osc_len++] = b;
            vt->parser_state = PS_OSC_STRING;
        }
        return;
    }

    if (ps == PS_DCS_STRING) {
        if (b == 0x1B) vt->parser_state = PS_DCS_ESC;
        else if (b == 0x07) vt->parser_state = PS_GROUND;
        return;
    }

    if (ps == PS_DCS_ESC) {
        if (b == 0x5C) vt->parser_state = PS_GROUND;
        else vt->parser_state = PS_DCS_STRING;
        return;
    }
}

/* ── Lua helpers ─────────────────────────────────────────────── */

static vterm_t *
check_vterm(lua_State *L, int idx) {
    return (vterm_t *)luaL_checkudata(L, idx, VTERM_MT);
}


/* Push attrs table in Lua vterm format: {fg=..., bg=..., bold=...} */
static void
push_attrs(lua_State *L, const style_entry_t *se) {
    lua_createtable(L, 0, 10);

    /* fg */
    if (se->fg_mode == COLOR_MODE_DEFAULT) {
        lua_pushnil(L);
    } else if (se->fg_mode == COLOR_MODE_16) {
        lua_createtable(L, 0, 2);
        lua_pushstring(L, "indexed");
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, se->fg_val);
        lua_setfield(L, -2, "idx");
    } else if (se->fg_mode == COLOR_MODE_256) {
        lua_createtable(L, 0, 2);
        lua_pushstring(L, "indexed");
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, se->fg_val);
        lua_setfield(L, -2, "idx");
    } else {
        lua_createtable(L, 0, 4);
        lua_pushstring(L, "rgb");
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, (se->fg_val >> 16) & 0xFF);
        lua_setfield(L, -2, "r");
        lua_pushinteger(L, (se->fg_val >> 8) & 0xFF);
        lua_setfield(L, -2, "g");
        lua_pushinteger(L, se->fg_val & 0xFF);
        lua_setfield(L, -2, "b");
    }
    lua_setfield(L, -2, "fg");

    /* bg */
    if (se->bg_mode == COLOR_MODE_DEFAULT) {
        lua_pushnil(L);
    } else if (se->bg_mode == COLOR_MODE_16 || se->bg_mode == COLOR_MODE_256) {
        lua_createtable(L, 0, 2);
        lua_pushstring(L, "indexed");
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, se->bg_val);
        lua_setfield(L, -2, "idx");
    } else {
        lua_createtable(L, 0, 4);
        lua_pushstring(L, "rgb");
        lua_setfield(L, -2, "type");
        lua_pushinteger(L, (se->bg_val >> 16) & 0xFF);
        lua_setfield(L, -2, "r");
        lua_pushinteger(L, (se->bg_val >> 8) & 0xFF);
        lua_setfield(L, -2, "g");
        lua_pushinteger(L, se->bg_val & 0xFF);
        lua_setfield(L, -2, "b");
    }
    lua_setfield(L, -2, "bg");

    lua_pushboolean(L, se->attrs & ATTR_BOLD);
    lua_setfield(L, -2, "bold");
    lua_pushboolean(L, se->attrs & ATTR_DIM);
    lua_setfield(L, -2, "dim");
    lua_pushboolean(L, se->attrs & ATTR_ITALIC);
    lua_setfield(L, -2, "italic");
    lua_pushboolean(L, se->attrs & ATTR_UNDERLINE);
    lua_setfield(L, -2, "underline");
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "blink");
    lua_pushboolean(L, se->attrs & ATTR_INVERSE);
    lua_setfield(L, -2, "inverse");
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "hidden");
    lua_pushboolean(L, se->attrs & ATTR_STRIKETHROUGH);
    lua_setfield(L, -2, "strikethrough");
}

/* ── Lua API ─────────────────────────────────────────────────── */

static int
l_new(lua_State *L) {
    int cols = (int)luaL_checkinteger(L, 1);
    int rows = (int)luaL_checkinteger(L, 2);
    luaL_argcheck(L, cols > 0 && cols < 10000, 1, "cols out of range");
    luaL_argcheck(L, rows > 0 && rows < 10000, 2, "rows out of range");

    vterm_t *vt = (vterm_t *)lua_newuserdatauv(L, sizeof(vterm_t), 1);
    memset(vt, 0, sizeof(*vt));
    vt->cols = cols;
    vt->rows = rows;
    vt->cursor_col = 1;
    vt->cursor_row = 1;
    vt->cursor_visible = 1;
    vt->scroll_top = 1;
    vt->scroll_bottom = rows;
    vt->cells = (cell_t *)calloc((size_t)cols * rows, sizeof(cell_t));
    if (!vt->cells) {
        luaL_error(L, "vterm.new: out of memory");
    }
    vt_fill_screen(vt);

    /* uservalue[1] = {} for Lua-side fields (write_log, input_queue, etc.) */
    lua_newtable(L);
    lua_setiuservalue(L, -2, 1);

    luaL_getmetatable(L, VTERM_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int
l_write(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    size_t len;
    const char *s = luaL_checklstring(L, 2, &len);
    for (size_t i = 0; i < len; i++) {
        process_byte(vt, (uint8_t)s[i]);
    }
    return 0;
}

static int
l_cell(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int col = (int)luaL_checkinteger(L, 2);
    int row = (int)luaL_checkinteger(L, 3);
    if (row < 1 || row > vt->rows || col < 1 || col > vt->cols) {
        lua_pushnil(L);
        return 1;
    }
    cell_t *c = vt_cell_at(vt, col, row);
    const uint8_t *bytes;
    uint32_t blen;
    cell_bytes(c, &vt->cell_slab, &bytes, &blen);
    lua_createtable(L, 0, 2);
    lua_pushlstring(L, (const char *)bytes, blen);
    lua_setfield(L, -2, "char");
    const style_entry_t *se = pool_get(&vt->pool, c->style_id);
    push_attrs(L, se);
    lua_setfield(L, -2, "attrs");
    return 1;
}

static int
l_row(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int r = (int)luaL_checkinteger(L, 2);
    if (r < 1 || r > vt->rows) {
        lua_pushnil(L);
        return 1;
    }
    lua_createtable(L, vt->cols, 0);
    for (int c = 1; c <= vt->cols; c++) {
        cell_t *cell = vt_cell_at(vt, c, r);
        const uint8_t *bytes;
        uint32_t blen;
        cell_bytes(cell, &vt->cell_slab, &bytes, &blen);
        lua_pushlstring(L, (const char *)bytes, blen);
        const style_entry_t *se = pool_get(&vt->pool, cell->style_id);
        push_attrs(L, se);
        lua_settable(L, -3);
    }
    return 1;
}

static int
l_screen(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_createtable(L, vt->rows, 0);
    for (int r = 1; r <= vt->rows; r++) {
        lua_createtable(L, vt->cols, 0);
        for (int c = 1; c <= vt->cols; c++) {
            cell_t *cell = vt_cell_at(vt, c, r);
            const uint8_t *bytes;
            uint32_t blen;
            cell_bytes(cell, &vt->cell_slab, &bytes, &blen);
            lua_pushlstring(L, (const char *)bytes, blen);
            const style_entry_t *se = pool_get(&vt->pool, cell->style_id);
            push_attrs(L, se);
            lua_settable(L, -3);
        }
        lua_rawseti(L, -2, r);
    }
    return 1;
}

static int
l_cursor(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, vt->cursor_col);
    lua_setfield(L, -2, "col");
    lua_pushinteger(L, vt->cursor_row);
    lua_setfield(L, -2, "row");
    lua_pushboolean(L, vt->cursor_visible);
    lua_setfield(L, -2, "visible");
    const char *style = (vt->cursor_style == 0) ? "block" :
                        (vt->cursor_style == 1) ? "underline" : "bar";
    lua_pushstring(L, style);
    lua_setfield(L, -2, "style");
    return 1;
}

static int
l_mode(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_createtable(L, 0, 7);
    lua_pushboolean(L, vt->mode.raw);
    lua_setfield(L, -2, "raw");
    lua_pushinteger(L, vt->mode.mouse);
    lua_setfield(L, -2, "mouse");
    lua_pushboolean(L, vt->mode.bracketed_paste);
    lua_setfield(L, -2, "bracketed_paste");
    lua_pushboolean(L, vt->mode.focus_events);
    lua_setfield(L, -2, "focus_events");
    lua_pushboolean(L, vt->mode.kkp);
    lua_setfield(L, -2, "kkp");
    lua_pushboolean(L, vt->mode.alternate_screen);
    lua_setfield(L, -2, "alternate_screen");
    lua_pushinteger(L, vt->mode.synchronized_output);
    lua_setfield(L, -2, "synchronized_output");
    return 1;
}

static int
l_has_mode(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int num = (int)luaL_checkinteger(L, 2);
    int result = 0;
    if (num == 1000 || num == 1002 || num == 1003) {
        result = vt->mode.mouse > 0;
    } else if (num == 1004) {
        result = vt->mode.focus_events;
    } else if (num == 2004) {
        result = vt->mode.bracketed_paste;
    } else if (num == 2026) {
        result = vt->mode.synchronized_output > 0;
    } else if (num == 1049) {
        result = vt->mode.alternate_screen;
    }
    lua_pushboolean(L, result);
    return 1;
}

static int
l_mouse_level(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_pushinteger(L, vt->mode.mouse);
    return 1;
}


static int
l_sync_depth(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_pushinteger(L, vt->mode.synchronized_output);
    return 1;
}

static int
l_screen_string(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_createtable(L, vt->rows, 0);
    for (int r = 1; r <= vt->rows; r++) {
        luaL_Buffer b;
        luaL_buffinit(L, &b);
        for (int c = 1; c <= vt->cols; c++) {
            cell_t *cell = vt_cell_at(vt, c, r);
            const uint8_t *bytes;
            uint32_t blen;
            cell_bytes(cell, &vt->cell_slab, &bytes, &blen);
            luaL_addlstring(&b, (const char *)bytes, blen);
        }
        luaL_pushresult(&b);
        lua_rawseti(L, -2, r);
    }
    return 1;
}

static int
l_row_string(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int r = (int)luaL_checkinteger(L, 2);
    if (r < 1 || r > vt->rows) {
        lua_pushstring(L, "");
        return 1;
    }
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int c = 1; c <= vt->cols; c++) {
        cell_t *cell = vt_cell_at(vt, c, r);
        const uint8_t *bytes;
        uint32_t blen;
        cell_bytes(cell, &vt->cell_slab, &bytes, &blen);
        luaL_addlstring(&b, (const char *)bytes, blen);
    }
    luaL_pushresult(&b);
    return 1;
}


static int
term_set_raw_direct(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int on = lua_toboolean(L, 2);
    vt->mode.raw = on ? 1 : 0;
    return 0;
}

/* Terminal interface closures */

static int
term_write(lua_State *L) {
    vterm_t *vt = (vterm_t *)lua_touserdata(L, lua_upvalueindex(1));
    size_t len;
    const char *s = luaL_checklstring(L, 1, &len);
    for (size_t i = 0; i < len; i++) {
        process_byte(vt, (uint8_t)s[i]);
    }
    return 0;
}

static int
term_get_size(lua_State *L) {
    vterm_t *vt = (vterm_t *)lua_touserdata(L, lua_upvalueindex(1));
    lua_pushinteger(L, vt->cols);
    lua_pushinteger(L, vt->rows);
    return 2;
}


static int
term_set_raw(lua_State *L) {
    vterm_t *vt = (vterm_t *)lua_touserdata(L, lua_upvalueindex(1));
    int on = lua_toboolean(L, 1);
    vt->mode.raw = on ? 1 : 0;
    return 0;
}

static int
term_windows_vt_enable(lua_State *L) {
    (void)L;
    lua_pushboolean(L, 1);
    return 1;
}

static int
l_as_terminal(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    lua_createtable(L, 0, 5);

    lua_pushvalue(L, 1);  /* push vt userdata as upvalue */
    lua_pushcclosure(L, term_write, 1);
    lua_setfield(L, -2, "write");

    lua_pushvalue(L, 1);
    lua_pushcclosure(L, term_get_size, 1);
    lua_setfield(L, -2, "get_size");

    lua_pushvalue(L, 1);
    lua_pushcclosure(L, term_set_raw, 1);
    lua_setfield(L, -2, "set_raw");

    lua_pushcfunction(L, term_windows_vt_enable);
    lua_setfield(L, -2, "windows_vt_enable");

    return 1;
}

static int
l_resize(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    int new_cols = (int)luaL_checkinteger(L, 2);
    int new_rows = (int)luaL_checkinteger(L, 3);
    if (new_cols < 1 || new_rows < 1) {
        return luaL_error(L, "vterm.resize: invalid size");
    }
    cell_t *new_cells = (cell_t *)calloc((size_t)new_cols * new_rows, sizeof(cell_t));
    if (!new_cells) {
        return luaL_error(L, "vterm.resize: out of memory");
    }
    /* Copy overlapping region */
    int copy_cols = (new_cols < vt->cols) ? new_cols : vt->cols;
    int copy_rows = (new_rows < vt->rows) ? new_rows : vt->rows;
    for (int r = 0; r < copy_rows; r++) {
        for (int c = 0; c < copy_cols; c++) {
            new_cells[r * new_cols + c] = vt->cells[r * vt->cols + c];
        }
        /* Fill new columns with spaces */
        for (int c = copy_cols; c < new_cols; c++) {
            cell_set_space(&new_cells[r * new_cols + c]);
        }
    }
    /* Fill new rows */
    for (int r = copy_rows; r < new_rows; r++) {
        for (int c = 0; c < new_cols; c++) {
            cell_set_space(&new_cells[r * new_cols + c]);
        }
    }
    free(vt->cells);
    vt->cells = new_cells;
    vt->cols = new_cols;
    vt->rows = new_rows;
    if (vt->cursor_col > new_cols) vt->cursor_col = new_cols;
    if (vt->cursor_row > new_rows) vt->cursor_row = new_rows;
    if (vt->scroll_bottom > new_rows) vt->scroll_bottom = new_rows;
    return 0;
}

/* ── __gc ────────────────────────────────────────────────────── */

static int
l_gc(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    free(vt->cells);
    slab_free(&vt->cell_slab);
    pool_free(&vt->pool);
    free(vt->title);
    return 0;
}

/* ── Registration ────────────────────────────────────────────── */

static const luaL_Reg vterm_methods[] = {
    {"write", l_write},
    {"cell", l_cell},
    {"row", l_row},
    {"screen", l_screen},
    {"cursor", l_cursor},
    {"mode", l_mode},
    {"has_mode", l_has_mode},
    {"mouse_level", l_mouse_level},
    {"sync_depth", l_sync_depth},
    {"screen_string", l_screen_string},
    {"row_string", l_row_string},
    {"set_raw", term_set_raw_direct},
    {"as_terminal", l_as_terminal},
    {"resize", l_resize},
    {NULL, NULL}
};

static const luaL_Reg vterm_funcs[] = {
    {"new", l_new},
    {NULL, NULL}
};

static int
l_index(lua_State *L) {
    vterm_t *vt = check_vterm(L, 1);
    const char *key = lua_tostring(L, 2);
    if (!key) {
        lua_pushnil(L);
        return 1;
    }
    if (strcmp(key, "cols") == 0) {
        lua_pushinteger(L, vt->cols);
        return 1;
    }
    if (strcmp(key, "rows") == 0) {
        lua_pushinteger(L, vt->rows);
        return 1;
    }
    /* Fall back to methods in the metatable */
    lua_getmetatable(L, 1);
    lua_pushvalue(L, 2);
    lua_rawget(L, -2);
    if (!lua_isnil(L, -1)) return 1;
    lua_pop(L, 1);
    /* Fall back to uservalue env table */
    if (lua_getiuservalue(L, 1, 1) != LUA_TNIL) {
        lua_pushvalue(L, 2);
        lua_gettable(L, -2);
        return 1;
    }
    return 1;
}

static int
l_newindex(lua_State *L) {
    check_vterm(L, 1);
    luaL_checkany(L, 2);
    /* Store in uservalue env table */
    lua_getiuservalue(L, 1, 1);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_setiuservalue(L, 1, 1);
        lua_getiuservalue(L, 1, 1);
    }
    lua_pushvalue(L, 2);
    lua_pushvalue(L, 3);
    lua_settable(L, -3);
    return 0;
}

int
tui_open_vterm(lua_State *L) {
    luaL_newmetatable(L, VTERM_MT);
    lua_pushcfunction(L, l_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_newindex);
    lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, l_gc);
    lua_setfield(L, -2, "__gc");
    luaL_setfuncs(L, vterm_methods, 0);
    lua_pop(L, 1);

    luaL_newlib(L, vterm_funcs);
    return 1;
}
