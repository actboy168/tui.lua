/*
 * tui_core.c — Aggregator entry for the tui_core Lua DLL.
 *
 * Exposes:
 *   terminal — raw I/O, size, VT enable
 *   keys     — stateless ANSI/UTF-8 parser (keys.parse)
 *   wcwidth  — display-width table (wcwidth/string_width/char_width)
 *   screen   — cell buffer + ANSI diff renderer (Stage 9)
 *
 * Layout after `require "tui_core"`:
 *   tui_core = {
 *       terminal = { set_raw, get_size, windows_vt_enable, read_raw,
 *                    write },
 *       keys     = { parse },
 *       wcwidth  = { wcwidth, string_width, char_width },
 *       screen   = { new, size, resize, invalidate, clear, put, diff, rows, ... },
 *   }
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
int luaopen_terminal(lua_State *L);
int luaopen_keys(lua_State *L);
int luaopen_wcwidth(lua_State *L);
int luaopen_screen(lua_State *L);
int luaopen_tui_core_text(lua_State *L);

DLL_EXPORT LUAMOD_API int
luaopen_tui_core(lua_State *L) {
    luaL_checkversion(L);
    lua_createtable(L, 0, 5);

    /* terminal sub-table */
    luaopen_terminal(L);
    lua_setfield(L, -2, "terminal");

    /* keys sub-table */
    luaopen_keys(L);
    lua_setfield(L, -2, "keys");

    /* wcwidth sub-table */
    luaopen_wcwidth(L);
    lua_setfield(L, -2, "wcwidth");

    /* screen sub-table */
    luaopen_screen(L);
    lua_setfield(L, -2, "screen");

    /* text sub-table (wrap) */
    luaopen_tui_core_text(L);
    lua_setfield(L, -2, "text");

    return 1;
}
