/*
 * tui_core.c — Aggregator entry for the tui_core Lua DLL.
 *
 * Stage 1 only exposes the `terminal` submodule. Future stages will register
 * `wcwidth` and `keys` subtables the same way.
 *
 * Layout after `require "tui_core"`:
 *   tui_core = {
 *       terminal = { set_raw, get_size, windows_vt_enable, read_raw,
 *                    write, set_ime_pos },
 *   }
 */

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>

/* Forward declarations of the sub-module openers defined in other .c files
 * that are compiled into this DLL. They follow the standard Lua loader
 * signature and push a single table on the stack. */
int luaopen_terminal(lua_State *L);

LUAMOD_API int
luaopen_tui_core(lua_State *L) {
    luaL_checkversion(L);
    lua_createtable(L, 0, 1);

    /* terminal sub-table */
    luaopen_terminal(L);
    lua_setfield(L, -2, "terminal");

    return 1;
}
