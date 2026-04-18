/*
 * wcwidth.h — internal API shared across tui_core.dll sub-modules.
 *
 * These are NOT Lua bindings. The Lua-facing API lives in wcwidth.c and is
 * registered under `tui_core.wcwidth`. This header exists so that other C
 * sources in the same DLL (e.g. screen.c) can call the underlying functions
 * directly without round-tripping through Lua.
 */

#pragma once

#include <stddef.h>
#include <stdint.h>

/* Terminal display width for a Unicode code point.
 *   -1  control (C0 / C1, except NUL which is 0)
 *    0  zero-width (combining marks, ZWJ, format chars, variation selectors, NUL)
 *    1  normal narrow
 *    2  East Asian Wide / Fullwidth / Emoji_Presentation
 */
int wcwidth_cp(uint32_t cp);

/* Decode one UTF-8 code point from s[*out_i..n). Advances *out_i past the
 * sequence on success (or past the first invalid byte on failure). On
 * invalid input, returns U+FFFD. */
uint32_t utf8_next(const unsigned char *s, size_t n, size_t *out_i);
