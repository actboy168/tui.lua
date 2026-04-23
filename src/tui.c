/*
 * tui.c — Aggregator entry for the tui_core Lua DLL.
 *
 * Exposes:
 *   terminal — raw I/O, size, VT enable
 *   keys     — stateless ANSI/UTF-8 parser (keys.parse)
 *   wcwidth  — display-width table (wcwidth/string_width/char_width)
 *   screen   — cell buffer + ANSI diff renderer (Stage 9)
 *
 * Layout after `require "tui.core"`:
 *   tui_core = {
 *       terminal = { set_raw, get_size, windows_vt_enable, read,
 *                    write },
 *       keys     = { parse },
 *       wcwidth  = { wcwidth, string_width, char_width },
 *       screen   = { new, size, resize, invalidate, clear, put, diff, rows, ... },
 *   }
 *
 * Source files: tui_terminal.c, tui_keys.c, tui_wcwidth.c, tui_screen.c,
 *               tui_text.c, tui_text_extra.c
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

#if defined(__GNUC__)
#define DLL_EXPORT __attribute__((visibility("default")))
#else
#define DLL_EXPORT
#endif

/* Forward declarations of the sub-module openers defined in other .c files
 * that are compiled into this DLL. They follow the standard Lua loader
 * signature and push a single table on the stack. */
int tui_open_terminal(lua_State *L);
int tui_open_keys(lua_State *L);
int tui_open_wcwidth(lua_State *L);
int tui_open_screen(lua_State *L);
int tui_open_text(lua_State *L);
int tui_open_text_extra(lua_State *L);
int tui_open_time(lua_State *L);
int tui_open_vterm(lua_State *L);
int tui_open_yoga(lua_State *L);

DLL_EXPORT LUAMOD_API int
luaopen_tui_core(lua_State *L) {
    luaL_checkversion(L);
    lua_createtable(L, 0, 7);

    /* terminal sub-table */
    tui_open_terminal(L);
    lua_setfield(L, -2, "terminal");

    /* keys sub-table */
    tui_open_keys(L);
    lua_setfield(L, -2, "keys");

    /* wcwidth sub-table */
    tui_open_wcwidth(L);
    lua_setfield(L, -2, "wcwidth");

    /* screen sub-table */
    tui_open_screen(L);
    lua_setfield(L, -2, "screen");

    /* text sub-table (wrap + wrap_hard + truncate variants) */
    tui_open_text(L);
    tui_open_text_extra(L);
    lua_setfield(L, -2, "text");

    /* time sub-table (monotonic clock + sleep) */
    tui_open_time(L);
    lua_setfield(L, -2, "time");

    /* vterm sub-table (virtual terminal emulator) */
    tui_open_vterm(L);
    lua_setfield(L, -2, "vterm");

    tui_open_yoga(L);
    lua_setfield(L, -2, "yoga");

    return 1;
}
