/*
 * tui_core.c — Aggregator entry for the tui_core Lua DLL.
 *
 * Stage 3 exposes:
 *   terminal — raw I/O, size, VT enable, IME position
 *   keys     — stateless ANSI/UTF-8 parser (keys.parse)
 *
 * Layout after `require "tui_core"`:
 *   tui_core = {
 *       terminal = { set_raw, get_size, windows_vt_enable, read_raw,
 *                    write, set_ime_pos },
 *       keys     = { parse },
 *   }
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

/* Forward declarations of the sub-module openers defined in other .c files
 * that are compiled into this DLL. They follow the standard Lua loader
 * signature and push a single table on the stack. */
int luaopen_terminal(lua_State *L);
int luaopen_keys(lua_State *L);

LUAMOD_API int
luaopen_tui_core(lua_State *L) {
    luaL_checkversion(L);
    lua_createtable(L, 0, 2);

    /* terminal sub-table */
    luaopen_terminal(L);
    lua_setfield(L, -2, "terminal");

    /* keys sub-table */
    luaopen_keys(L);
    lua_setfield(L, -2, "keys");

    return 1;
}
