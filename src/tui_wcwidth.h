/*
 * tui_wcwidth.h — internal API shared across tui_core.dll sub-modules.
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

/* Decode one grapheme cluster from s[*out_i..n). Advances *out_i past the
 * entire cluster. Writes the cluster's UTF-8 byte length to *out_byte_len
 * and its terminal display width to *out_width.
 *
 * Implements a UAX#29 subset:
 *   - GB3 CR × LF (treated as one cluster, width 0)
 *   - GB4/5 controls break (width -1 converted to 0)
 *   - GB6/7/8 Hangul L/V/T/LV/LVT conjoining (cluster width = 2)
 *   - GB9   X × (Extend | ZWJ)
 *   - GB9a  X × SpacingMark  (approximated: any wcwidth==0 non-control)
 *   - GB11  Extended_Pictographic Extend* ZWJ × Extended_Pictographic
 *           (approximated: after any ZWJ we swallow one more cluster base)
 *   - GB12/13 sot (RI RI)* RI × RI (flag pairs)
 *
 * Width rules:
 *   - base code point wcwidth drives cluster width
 *   - VS16 (U+FE0F) after base promotes cluster width to 2
 *   - VS15 (U+FE0E) leaves base width alone
 *   - RI+RI fused → width 2
 *
 * A lone 0-width or control base at the cluster start returns width 0 and
 * advances by the single decoded code point so callers can `continue` safely.
 */
void grapheme_next(const unsigned char *s, size_t n, size_t *out_i,
                   size_t *out_byte_len, int *out_width);
