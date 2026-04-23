/* tui_fatal.h — helper macro for C-layer invariant-violation errors.
 *
 * Errors raised with TUI_FATAL carry the "[tui:fatal] " prefix that
 * reconciler.is_fatal() detects and re-throws past any active ErrorBoundary
 * pcall.  Use it for conditions that indicate a tui programming bug (OOM,
 * broken internal invariant, impossible enum value) where papering over with
 * a fallback UI would be misleading.
 *
 * Regular user-facing validation errors (bad public API arguments, out-of-
 * range indices in test helpers) should use plain luaL_error / luaL_argerror
 * so they can be caught and reported normally.
 */
#pragma once
#include <lauxlib.h>

/* The first argument after L must be a string literal so that the compiler
 * can perform static string concatenation with the prefix. */
#define TUI_FATAL(L, ...) luaL_error((L), "[tui:fatal] " __VA_ARGS__)
