/*
 * keys.c — stateless ANSI/UTF-8 key parser for tui.lua
 *
 * Input:  a byte string (from terminal.read_raw)
 * Output: Lua array of event tables:
 *
 *   {
 *     name  = <string>,   -- semantic key name, e.g. "up", "enter", "char"
 *     input = <string>,   -- the text to show (single UTF-8 char or "")
 *     ctrl  = <bool>,
 *     meta  = <bool>,
 *     shift = <bool>,     -- only set when we can infer it from CSI modifier
 *     raw   = <string>,   -- original bytes consumed (for debugging)
 *   }
 *
 * Covered:
 *   * printable UTF-8 -> { name="char", input=<the char> }
 *   * ESC alone (standalone key) -> { name="escape" }
 *   * ESC <letter>           -> meta+char (alt combo)
 *   * CR/LF -> "enter"; HT -> "tab"; BS/DEL -> "backspace"
 *   * Ctrl+a..z (0x01..0x1A except the ones above) -> { name="char", input=<letter>, ctrl=true }
 *   * CSI arrows / Home / End:
 *       ESC [ A/B/C/D/H/F  -> up/down/right/left/home/end
 *   * CSI tilde keys:
 *       ESC [ 2~ insert, 3~ delete, 5~ pageup, 6~ pagedown,
 *             11~..15~ F1..F5, 17~..21~ F6..F10, 23~..24~ F11..F12
 *   * SS3 (xterm function-ish):
 *       ESC O P/Q/R/S -> F1..F4
 *   * Modifier suffix forms:
 *       ESC [ 1 ; <mod> A  (arrow+mod), ESC [ <n> ; <mod> ~ (tilde+mod)
 *       mod = 1 + bitmask(shift=1, meta=2, ctrl=4); e.g. ";5A" = ctrl+up
 *
 * Mouse events (SGR extended and legacy X10):
 *   SGR:     ESC [ < Pb ; Px ; Py M (press/move) / m (release)
 *   X10:     ESC [ M <b+32> <x+32> <y+32>  (6 raw bytes)
 *   Event:   { name="mouse", type="down"/"up"/"move"/"scroll",
 *              button=1/2/3/nil, x=col, y=row, scroll=1/-1/nil,
 *              shift, meta, ctrl }
 *
 * Not covered:
 *   * kitty keyboard protocol
 *
 * All parsing is done in a single forward pass; partial trailing sequences
 * (e.g. lone ESC at end of buffer) are treated as the standalone escape.
 */

#define LUA_LIB
#include <lua.h>
#include <lauxlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

/* Helper: push a k/v string pair into the table at the top. */
static void set_str(lua_State *L, const char *k, const char *v, size_t len) {
    lua_pushlstring(L, v, len);
    lua_setfield(L, -2, k);
}
static void set_bool(lua_State *L, const char *k, bool v) {
    lua_pushboolean(L, v);
    lua_setfield(L, -2, k);
}
static void set_cstr(lua_State *L, const char *k, const char *v) {
    lua_pushstring(L, v);
    lua_setfield(L, -2, k);
}

/* Begin a fresh event table at stack top, with defaults. */
static void begin_event(lua_State *L, const char *raw, size_t raw_len) {
    lua_createtable(L, 0, 6);
    set_str(L, "raw", raw, raw_len);
    set_bool(L, "ctrl",  false);
    set_bool(L, "meta",  false);
    set_bool(L, "shift", false);
    set_cstr(L, "input", "");
}

/* UTF-8 head byte -> total length of the sequence (1..4), or 0 if invalid. */
static int utf8_len(unsigned char b) {
    if (b < 0x80)           return 1;
    if ((b & 0xE0) == 0xC0) return 2;
    if ((b & 0xF0) == 0xE0) return 3;
    if ((b & 0xF8) == 0xF0) return 4;
    return 0;
}

/*
 * Decode the ";<mod>" modifier integer into ctrl/meta/shift flags.
 * mod = 1 + bitmask(shift=1, meta=2, ctrl=4)
 */
static void apply_mod(lua_State *L, int tbl_idx, int mod) {
    if (mod < 2) return;
    int bits = mod - 1;
    if (bits & 1) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "shift"); }
    if (bits & 2) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "meta"); }
    if (bits & 4) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "ctrl"); }
}

/*
 * Emit one mouse event table into the output array.
 *
 * btn_raw : raw button byte (before stripping modifiers):
 *   bits 0-1 : button number (0=left, 1=middle, 2=right; 3=release for X10)
 *   bit  2   : shift
 *   bit  3   : meta/alt
 *   bit  4   : ctrl
 *   bit  5   : motion (move/drag)
 *   bit  6   : wheel (scroll)
 * x, y       : column/row, 1-based.
 * is_release : SGR 'm' final byte; for X10 derived from btn_raw bits 0-1 == 3.
 */
static void push_mouse_event(lua_State *L, int out_idx, int *emitted,
                              const char *raw, size_t raw_len,
                              int btn_raw, int x, int y, bool is_release) {
    int  btn_num = btn_raw & 0x03;
    bool shift   = (btn_raw & 0x04) != 0;
    bool meta    = (btn_raw & 0x08) != 0;
    bool ctrl    = (btn_raw & 0x10) != 0;
    bool motion  = (btn_raw & 0x20) != 0;
    bool wheel   = (btn_raw & 0x40) != 0;

    begin_event(L, raw, raw_len);   /* sets raw, ctrl/meta/shift=false, input="" */
    set_cstr(L, "name", "mouse");
    if (shift) set_bool(L, "shift", true);
    if (meta)  set_bool(L, "meta",  true);
    if (ctrl)  set_bool(L, "ctrl",  true);

    lua_pushinteger(L, x);
    lua_setfield(L, -2, "x");
    lua_pushinteger(L, y);
    lua_setfield(L, -2, "y");

    if (wheel) {
        set_cstr(L, "type", "scroll");
        /* bits 0-1: 0=up → 1, 1=down → -1 (2/3 seldom used; map to -1) */
        lua_pushinteger(L, btn_num == 0 ? 1 : -1);
        lua_setfield(L, -2, "scroll");
    } else if (is_release) {
        set_cstr(L, "type", "up");
        /* SGR preserves which button; X10 loses it (btn_num == 3) */
        if (btn_num != 3) {
            lua_pushinteger(L, btn_num + 1);
            lua_setfield(L, -2, "button");
        }
    } else if (motion) {
        set_cstr(L, "type", "move");
        if (btn_num != 3) {         /* btn_num == 3 = hover (no button held) */
            lua_pushinteger(L, btn_num + 1);
            lua_setfield(L, -2, "button");
        }
    } else {
        set_cstr(L, "type", "down");
        lua_pushinteger(L, btn_num + 1);
        lua_setfield(L, -2, "button");
    }

    lua_rawseti(L, out_idx, ++(*emitted));
}

/* Map CSI final byte (after optional "1;mod") to a key name. */
static const char* csi_final_name(char c) {
    switch (c) {
        case 'A': return "up";
        case 'B': return "down";
        case 'C': return "right";
        case 'D': return "left";
        case 'H': return "home";
        case 'F': return "end";
        case 'Z': return "backtab"; /* shift-tab in many terminals */
        case 'I': return "focus_in";  /* DEC 1004: terminal gained focus */
        case 'O': return "focus_out"; /* DEC 1004: terminal lost focus */
        default:  return NULL;
    }
}

/* Map "<n>~" tilde-keypad numbers to key names. */
static const char* tilde_name(int n) {
    switch (n) {
        case 1:  return "home";      /* some terminals */
        case 2:  return "insert";
        case 3:  return "delete";
        case 4:  return "end";       /* some terminals */
        case 5:  return "pageup";
        case 6:  return "pagedown";
        case 11: return "f1";
        case 200: return "paste_start";
        case 201: return "paste_end";
        case 12: return "f2";
        case 13: return "f3";
        case 14: return "f4";
        case 15: return "f5";
        case 17: return "f6";
        case 18: return "f7";
        case 19: return "f8";
        case 20: return "f9";
        case 21: return "f10";
        case 23: return "f11";
        case 24: return "f12";
        default: return NULL;
    }
}

/* Map "ESC O <c>" (SS3) final byte -> key name (F1..F4, also arrows on some). */
static const char* ss3_name(char c) {
    switch (c) {
        case 'P': return "f1";
        case 'Q': return "f2";
        case 'R': return "f3";
        case 'S': return "f4";
        case 'A': return "up";
        case 'B': return "down";
        case 'C': return "right";
        case 'D': return "left";
        case 'H': return "home";
        case 'F': return "end";
        default:  return NULL;
    }
}

/*
 * Parse CSI starting at s[i] (the byte after "ESC [").
 * Consumes digits/semicolons until a final byte.
 * Returns the number of bytes consumed within the CSI body (not counting "ESC [").
 * Sets *out_name (may be NULL if unknown), *out_mod (1 if absent), *out_num (first digit group).
 */
static int parse_csi(const char *s, size_t n, size_t i,
                     const char **out_name, int *out_mod, int *out_num) {
    *out_name = NULL;
    *out_mod  = 1;
    *out_num  = 0;

    int first = 0, second = 0;
    bool have_first = false, have_second = false;
    bool in_second = false;
    size_t start = i;

    while (i < n) {
        char c = s[i];
        if (c >= '0' && c <= '9') {
            if (!in_second) {
                first = first * 10 + (c - '0');
                have_first = true;
            } else {
                second = second * 10 + (c - '0');
                have_second = true;
            }
            i++;
        } else if (c == ';') {
            in_second = true;
            i++;
        } else {
            /* final byte */
            if (c == '~') {
                if (have_first) *out_name = tilde_name(first);
                if (have_second) *out_mod = second;
                *out_num = first;
            } else {
                *out_name = csi_final_name(c);
                if (have_second) *out_mod = second;
                else if (have_first && first > 1) *out_mod = first; /* e.g. ESC[5A */
                *out_num = first;
            }
            i++;
            return (int)(i - start);
        }
    }
    /* Unterminated CSI — return what we consumed so caller can drop it. */
    return (int)(i - start);
}

/*
 * Main parser. Emits events into a fresh Lua array table on the stack.
 */
static int l_parse(lua_State *L) {
    size_t n;
    const char *s = luaL_checklstring(L, 1, &n);
    lua_createtable(L, 0, 0);
    int out_idx = lua_gettop(L);
    int emitted = 0;

    size_t i = 0;
    while (i < n) {
        unsigned char b = (unsigned char)s[i];

        /* --- ESC and escape sequences --- */
        if (b == 0x1B) {
            /* ESC at end of buffer -> standalone escape */
            if (i + 1 >= n) {
                begin_event(L, s + i, 1);
                set_cstr(L, "name", "escape");
                lua_rawseti(L, out_idx, ++emitted);
                i++;
                continue;
            }
            char next = s[i + 1];
            if (next == '[') {
                /* ── SGR extended mouse: ESC [ < Pb ; Px ; Py M/m ─────── */
                if (i + 2 < n && s[i + 2] == '<') {
                    size_t j = i + 3;   /* first digit of Pb */
                    int pb = 0, px = 0, py = 0, seg = 0;
                    bool valid = false;
                    char final_ch = 0;
                    while (j < n) {
                        char c = s[j];
                        if (c >= '0' && c <= '9') {
                            if      (seg == 0) pb = pb * 10 + (c - '0');
                            else if (seg == 1) px = px * 10 + (c - '0');
                            else if (seg == 2) py = py * 10 + (c - '0');
                            j++;
                        } else if (c == ';') {
                            seg++;
                            j++;
                        } else if (c == 'M' || c == 'm') {
                            final_ch = c;
                            j++;
                            valid = (seg == 2 && px >= 1 && py >= 1);
                            break;
                        } else {
                            break;  /* malformed — fall through to generic CSI */
                        }
                    }
                    if (valid) {
                        push_mouse_event(L, out_idx, &emitted, s + i, j - i,
                                         pb, px, py, final_ch == 'm');
                        i = j;
                        continue;
                    }
                }
                /* ── Legacy X10 mouse: ESC [ M <b+32> <x+32> <y+32> ─────── */
                if (i + 5 < n && s[i + 2] == 'M') {
                    unsigned char bv = (unsigned char)s[i + 3];
                    if (bv >= 32) {     /* sanity: X10 button byte is always >= 32 */
                        int btn_raw = (int)bv - 32;
                        int px = (int)(unsigned char)s[i + 4] - 32;
                        int py = (int)(unsigned char)s[i + 5] - 32;
                        if (px >= 1 && py >= 1) {
                            bool release = (btn_raw & 0x03) == 3;
                            push_mouse_event(L, out_idx, &emitted, s + i, 6,
                                             btn_raw, px, py, release);
                            i += 6;
                            continue;
                        }
                    }
                }
                /* CSI */
                const char *name = NULL;
                int mod = 1, num = 0;
                int consumed = parse_csi(s, n, i + 2, &name, &mod, &num);
                size_t total = 2 + (size_t)consumed;
                if (name == NULL) {
                    /* Check for kitty-style "CSI <keycode> ; <mod> u" sequences.
                     * The final byte is the last byte of the consumed CSI body. */
                    char final_byte = (consumed > 0) ? s[i + 2 + consumed - 1] : 0;
                    if (final_byte == 'u' && num == 13) {
                        /* Enter with modifier: ESC[13;5u = Ctrl+Enter, ESC[13;2u = Shift+Enter */
                        begin_event(L, s + i, total);
                        set_cstr(L, "name", "enter");
                        apply_mod(L, lua_gettop(L), mod);
                        lua_rawseti(L, out_idx, ++emitted);
                    } else {
                        /* Unknown CSI: emit a generic "csi" event carrying raw. */
                        begin_event(L, s + i, total);
                        set_cstr(L, "name", "csi");
                        lua_rawseti(L, out_idx, ++emitted);
                    }
                } else {
                    begin_event(L, s + i, total);
                    set_cstr(L, "name", name);
                    apply_mod(L, lua_gettop(L), mod);
                    lua_rawseti(L, out_idx, ++emitted);
                }
                i += total;
                continue;
            } else if (next == 'O' && i + 2 < n) {
                /* SS3: ESC O <c> */
                char c = s[i + 2];
                const char *name = ss3_name(c);
                begin_event(L, s + i, 3);
                set_cstr(L, "name", name ? name : "ss3");
                lua_rawseti(L, out_idx, ++emitted);
                i += 3;
                continue;
            } else {
                /* ESC <byte>: treat as meta + (char or control). */
                size_t cl = utf8_len((unsigned char)next);
                if (cl == 0) cl = 1;
                if (i + 1 + cl > n) cl = 1;

                begin_event(L, s + i, 1 + cl);
                if (next >= 0x20 && next < 0x7F) {
                    /* meta + printable */
                    char one[1] = { next };
                    set_str(L, "input", one, 1);
                    set_cstr(L, "name", "char");
                    lua_pushboolean(L, 1);
                    lua_setfield(L, -2, "meta");
                } else if (next == 0x7F || next == 0x08) {
                    set_cstr(L, "name", "backspace");
                    lua_pushboolean(L, 1);
                    lua_setfield(L, -2, "meta");
                } else {
                    /* meta + multi-byte UTF-8 */
                    set_str(L, "input", s + i + 1, cl);
                    set_cstr(L, "name", "char");
                    lua_pushboolean(L, 1);
                    lua_setfield(L, -2, "meta");
                }
                lua_rawseti(L, out_idx, ++emitted);
                i += 1 + cl;
                continue;
            }
        }

        /* --- Named control bytes --- */
        if (b == '\r' || b == '\n') {
            begin_event(L, s + i, 1);
            set_cstr(L, "name", "enter");
            lua_rawseti(L, out_idx, ++emitted);
            i++;
            continue;
        }
        if (b == '\t') {
            begin_event(L, s + i, 1);
            set_cstr(L, "name", "tab");
            lua_rawseti(L, out_idx, ++emitted);
            i++;
            continue;
        }
        if (b == 0x7F || b == 0x08) {
            begin_event(L, s + i, 1);
            set_cstr(L, "name", "backspace");
            lua_rawseti(L, out_idx, ++emitted);
            i++;
            continue;
        }

        /* --- Ctrl+letter (0x01..0x1A except those handled above) --- */
        if (b >= 0x01 && b <= 0x1A) {
            char letter = (char)('a' + (b - 1));
            begin_event(L, s + i, 1);
            set_cstr(L, "name", "char");
            set_str(L, "input", &letter, 1);
            lua_pushboolean(L, 1);
            lua_setfield(L, -2, "ctrl");
            lua_rawseti(L, out_idx, ++emitted);
            i++;
            continue;
        }

        /* --- Printable UTF-8 --- */
        int cl = utf8_len(b);
        if (cl == 0 || i + (size_t)cl > n) {
            /* Bad byte: skip, but still emit something so caller isn't blind. */
            begin_event(L, s + i, 1);
            set_cstr(L, "name", "unknown");
            lua_rawseti(L, out_idx, ++emitted);
            i++;
            continue;
        }
        begin_event(L, s + i, (size_t)cl);
        set_cstr(L, "name", "char");
        set_str(L, "input", s + i, (size_t)cl);
        lua_rawseti(L, out_idx, ++emitted);
        i += (size_t)cl;
    }

    return 1;
}

static const luaL_Reg lib[] = {
    { "parse", l_parse },
    { NULL, NULL },
};

int tui_open_keys(lua_State *L) {
    luaL_checkversion(L);
    luaL_newlib(L, lib);
    return 1;
}
