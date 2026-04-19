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
 * Not covered (Stage 3 scope):
 *   * mouse events (SGR / legacy X10)
 *   * bracketed paste
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
                /* CSI */
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
    luaL_checkversion(L);
    luaL_newlib(L, lib);
    return 1;
}
