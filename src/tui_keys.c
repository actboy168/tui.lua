/*
 * keys.c — stateless ANSI/UTF-8 key parser for tui.lua
 *
 * Input:  a byte string (from terminal.read)
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

/* ── Kitty Keyboard Protocol (KKP) ───────────────────────────── */

/*
 * Map a Kitty keyboard protocol Unicode codepoint to a key name string.
 * Returns NULL for printable ASCII (32-126) — caller should use the
 * character itself as the "input" field rather than a named key.
 * Returns "kitty_key" for unknown private-use codepoints.
 */
static const char *kitty_key_name(int cp) {
    switch (cp) {
        /* C0 / DEL — retained as named keys even in KKP mode */
        case 27:    return "escape";
        case 13:    return "enter";
        case 9:     return "tab";
        case 127:   return "backspace";
        /* Lock / system keys */
        case 57358: return "caps_lock";
        case 57359: return "scroll_lock";
        case 57360: return "num_lock";
        case 57361: return "print_screen";
        case 57362: return "pause";
        case 57363: return "menu";
        /* F13–F35 */
        case 57376: return "f13";
        case 57377: return "f14";
        case 57378: return "f15";
        case 57379: return "f16";
        case 57380: return "f17";
        case 57381: return "f18";
        case 57382: return "f19";
        case 57383: return "f20";
        case 57384: return "f21";
        case 57385: return "f22";
        case 57386: return "f23";
        case 57387: return "f24";
        case 57388: return "f25";
        case 57389: return "f26";
        case 57390: return "f27";
        case 57391: return "f28";
        case 57392: return "f29";
        case 57393: return "f30";
        case 57394: return "f31";
        case 57395: return "f32";
        case 57396: return "f33";
        case 57397: return "f34";
        case 57398: return "f35";
        /* Keypad keys */
        case 57399: return "kp_0";
        case 57400: return "kp_1";
        case 57401: return "kp_2";
        case 57402: return "kp_3";
        case 57403: return "kp_4";
        case 57404: return "kp_5";
        case 57405: return "kp_6";
        case 57406: return "kp_7";
        case 57407: return "kp_8";
        case 57408: return "kp_9";
        case 57409: return "kp_decimal";
        case 57410: return "kp_divide";
        case 57411: return "kp_multiply";
        case 57412: return "kp_subtract";
        case 57413: return "kp_add";
        case 57414: return "kp_enter";
        case 57415: return "kp_equal";
        case 57416: return "kp_separator";
        case 57417: return "kp_left";
        case 57418: return "kp_right";
        case 57419: return "kp_up";
        case 57420: return "kp_down";
        case 57421: return "kp_page_up";
        case 57422: return "kp_page_down";
        case 57423: return "kp_home";
        case 57424: return "kp_end";
        case 57425: return "kp_insert";
        case 57426: return "kp_delete";
        case 57427: return "kp_begin";
        /* Media keys */
        case 57428: return "media_play";
        case 57429: return "media_pause";
        case 57430: return "media_play_pause";
        case 57431: return "media_reverse";
        case 57432: return "media_stop";
        case 57433: return "media_fast_forward";
        case 57434: return "media_rewind";
        case 57435: return "media_track_next";
        case 57436: return "media_track_previous";
        case 57437: return "media_record";
        case 57438: return "lower_volume";
        case 57439: return "raise_volume";
        case 57440: return "mute_volume";
        /* Modifier keys */
        case 57441: return "left_shift";
        case 57442: return "left_ctrl";
        case 57443: return "left_alt";
        case 57444: return "left_super";
        case 57445: return "left_hyper";
        case 57446: return "left_meta";
        case 57447: return "right_shift";
        case 57448: return "right_ctrl";
        case 57449: return "right_alt";
        case 57450: return "right_super";
        case 57451: return "right_hyper";
        case 57452: return "right_meta";
        case 57453: return "iso_level3_shift";
        case 57454: return "iso_level5_shift";
        default:    return NULL;
    }
}

/*
 * Parse a Kitty Keyboard Protocol "CSI u" sequence.
 *
 * Full format (spaces for clarity only):
 *   <key> [: alt [: base]] [; mod [: event_type]] [; text] u
 *
 * `s` points to the first byte after "ESC [" (i.e. the key digit or a
 * parameter prefix byte).  `n` is the remaining buffer length.
 *
 * On success:
 *   *out_key        — Unicode key codepoint
 *   *out_mod        — raw modifier value (1 = no modifiers)
 *   *out_event_type — 1=press, 2=repeat, 3=release
 *   returns number of bytes consumed (including the trailing 'u')
 *
 * On failure (not a valid CSI u): returns -1.
 */
static int parse_kitty_csi(const char *s, size_t n,
                            int *out_key, int *out_mod, int *out_event_type) {
    *out_key        = 0;
    *out_mod        = 1;
    *out_event_type = 1;

    size_t i = 0;

    /* Parse key codepoint (mandatory). */
    if (i >= n || s[i] < '0' || s[i] > '9') return -1;
    int key = 0;
    while (i < n && s[i] >= '0' && s[i] <= '9')
        key = key * 10 + (s[i++] - '0');

    /* Skip optional alt-key / base-layout-key sub-fields (colon separated). */
    while (i < n && s[i] == ':') {
        i++; /* skip ':' */
        while (i < n && s[i] >= '0' && s[i] <= '9') i++;
    }

    /* Optional first semi-colon group: modifier [: event_type]. */
    int mod = 1, event_type = 1;
    if (i < n && s[i] == ';') {
        i++; /* skip ';' */
        /* modifier value */
        int m = 0;
        bool have_m = false;
        while (i < n && s[i] >= '0' && s[i] <= '9') {
            m = m * 10 + (s[i++] - '0');
            have_m = true;
        }
        if (have_m && m > 0) mod = m;
        /* optional event_type sub-field */
        if (i < n && s[i] == ':') {
            i++; /* skip ':' */
            int et = 0;
            bool have_et = false;
            while (i < n && s[i] >= '0' && s[i] <= '9') {
                et = et * 10 + (s[i++] - '0');
                have_et = true;
            }
            if (have_et && et > 0) event_type = et;
        }
    }

    /* Optional second semi-colon group: associated text (skip entirely). */
    if (i < n && s[i] == ';') {
        i++; /* skip ';' */
        while (i < n && s[i] != 'u') i++;
    }

    /* Must end with 'u'. */
    if (i >= n || s[i] != 'u') return -1;
    i++; /* consume 'u' */

    *out_key        = key;
    *out_mod        = mod;
    *out_event_type = event_type;
    return (int)i;
}

/*
 * Apply KKP modifiers to the event table at tbl_idx.
 * KKP mod = 1 + bitmask where:
 *   shift=1, alt=2, ctrl=4, super=8, hyper=16, meta=32,
 *   caps_lock=64, num_lock=128
 */
static void apply_kitty_mod(lua_State *L, int tbl_idx, int mod) {
    if (mod < 2) return;
    int bits = mod - 1;
    if (bits & 0x01) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "shift"); }
    if (bits & 0x02) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "meta");  }
    if (bits & 0x04) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "ctrl");  }
    if (bits & 0x08) { lua_pushboolean(L, 1); lua_setfield(L, tbl_idx, "super"); }
}

/* Encode a Unicode codepoint (≤ U+10FFFF) as UTF-8 into buf (≥ 5 bytes).
 * Returns the number of bytes written (1–4), or 0 for invalid codepoints. */
static int cp_to_utf8(int cp, char *buf) {
    if (cp < 0) return 0;
    if (cp < 0x80) {
        buf[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800) {
        buf[0] = (char)(0xC0 | (cp >> 6));
        buf[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        buf[0] = (char)(0xE0 | (cp >> 12));
        buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    if (cp <= 0x10FFFF) {
        buf[0] = (char)(0xF0 | (cp >> 18));
        buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (cp & 0x3F));
        return 4;
    }
    return 0;
}


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
                /* CSI — quick-scan to find the final byte (0x40-0x7E).
                 * CSI parameter bytes (0x30-0x3F) and intermediate bytes
                 * (0x20-0x2F) are all < 0x40, so we scan forward until we
                 * hit a byte >= 0x40.  If the final byte is 'u' this is a
                 * Kitty Keyboard Protocol sequence. */
                {
                    size_t j = i + 2;
                    while (j < n && (unsigned char)s[j] < 0x40) j++;
                    char csi_final = (j < n) ? s[j] : 0;

                    if (csi_final == 'u') {
                        /* ── Kitty Keyboard Protocol CSI u ──────────────── */
                        int key = 0, mod = 1, event_type = 1;
                        int kconsumed = parse_kitty_csi(s + i + 2, n - i - 2,
                                                        &key, &mod, &event_type);
                        if (kconsumed < 0) {
                            /* Malformed — emit raw csi and advance past the final byte. */
                            size_t total2 = (j + 1) - i;
                            begin_event(L, s + i, total2);
                            set_cstr(L, "name", "csi");
                            lua_rawseti(L, out_idx, ++emitted);
                            i = j + 1;
                            continue;
                        }
                        size_t total2 = 2 + (size_t)kconsumed;
                        const char *kname = kitty_key_name(key);

                        begin_event(L, s + i, total2);

                        if (kname != NULL) {
                            /* Named functional key or C0 key. */
                            set_cstr(L, "name", kname);
                        } else if (key >= 32 && key <= 126) {
                            /* Printable ASCII codepoint with modifiers. */
                            char ch = (char)key;
                            set_cstr(L, "name", "char");
                            set_str(L, "input", &ch, 1);
                        } else if (key > 126) {
                            /* Non-ASCII Unicode codepoint (e.g. accented char). */
                            char utf8buf[5];
                            int ulen = cp_to_utf8(key, utf8buf);
                            set_cstr(L, "name", "char");
                            if (ulen > 0)
                                set_str(L, "input", utf8buf, (size_t)ulen);
                        } else {
                            /* Unknown private-use or control codepoint. */
                            set_cstr(L, "name", "kitty_key");
                            lua_pushinteger(L, (lua_Integer)key);
                            lua_setfield(L, -2, "keycode");
                        }
                        apply_kitty_mod(L, lua_gettop(L), mod);
                        /* event_type: 1=press (default, omit), 2=repeat, 3=release */
                        if (event_type == 2) {
                            lua_pushstring(L, "repeat");
                            lua_setfield(L, -2, "event_type");
                        } else if (event_type == 3) {
                            lua_pushstring(L, "release");
                            lua_setfield(L, -2, "event_type");
                        } else {
                            lua_pushstring(L, "press");
                            lua_setfield(L, -2, "event_type");
                        }
                        lua_rawseti(L, out_idx, ++emitted);
                        i += total2;
                        continue;
                    }
                }
                /* Legacy CSI */
                const char *name = NULL;
                int mod = 1, num = 0;
                int consumed = parse_csi(s, n, i + 2, &name, &mod, &num);
                size_t total = 2 + (size_t)consumed;
                if (name == NULL) {
                    /* Unknown CSI: emit a generic "csi" event carrying raw. */
                    begin_event(L, s + i, total);
                    set_cstr(L, "name", "csi");
                    lua_rawseti(L, out_idx, ++emitted);
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
    luaL_newlib(L, lib);
    return 1;
}
