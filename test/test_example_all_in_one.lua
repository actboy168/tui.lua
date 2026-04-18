-- test/test_example_all_in_one.lua — smoke-test the all_in_one example
-- through the offscreen harness so layout bugs (Yoga defaults, widget
-- collisions, missing flexDirection) fail here instead of only surfacing
-- in the real terminal.
--
-- Strategy: require examples/all_in_one (which returns the App factory
-- when loaded via require, and only calls tui.render when run directly).
-- Mount with testing.render at a realistic size and assert invariants
-- over a few interaction paths.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local App = require "examples.all_in_one"

local suite = lt.test "example_all_in_one"

local function strip_ansi(s)
    return (s:gsub("\27%[[%d;]*m", ""))
end

local function frame_text(h)
    return strip_ansi(h:frame())
end

-- ---------------------------------------------------------------------------
-- Mount at a reasonable terminal size. The real failure mode spotted in the
-- screenshot (80x24 stacked everything into column due to Yoga defaults) is
-- caught by asserting that known-adjacent header labels share a row.

function suite:test_initial_paint_has_header_on_one_row()
    local h = testing.render(App, { cols = 80, rows = 24 })
    local rows = h:rows()
    -- Header row 2 (inside the "round" border) should contain "chat demo",
    -- "model:", the current model, and "uptime" / "?:help" on the SAME row.
    local header_row
    for i = 1, math.min(4, #rows) do
        local plain = strip_ansi(rows[i])
        if plain:find("chat demo", 1, true)
           and plain:find("model:", 1, true)
           and plain:find("uptime", 1, true)
           and plain:find("?:help", 1, true) then
            header_row = i
            break
        end
    end
    lt.assertEquals(type(header_row), "number",
                    "header labels should share a single row (row layout bug)")
    h:unmount()
end

function suite:test_input_box_and_hint_are_rendered()
    local h = testing.render(App, { cols = 80, rows = 24 })
    local txt = frame_text(h)
    -- Input is focused on mount, so placeholder isn't shown; assert the
    -- input's border frame is present by looking for the footer hint line
    -- (which must render regardless of focus state).
    lt.assertEquals(txt:find("Enter: send", 1, true) ~= nil, true,
                    "footer hint line should render")
    -- Header uptime label proves the input row painted (since header comes
    -- first and everything below depends on the column flex layout).
    lt.assertEquals(txt:find("uptime", 1, true) ~= nil, true,
                    "header uptime should render")
    h:unmount()
end

function suite:test_help_toggle_shows_commands_box()
    local h = testing.render(App, { cols = 80, rows = 24 })
    -- Help is not visible initially.
    lt.assertEquals(frame_text(h):find("commands", 1, true), nil)
    -- `?` is a printable char, not a named key — use :type() to dispatch.
    h:type("?")
    lt.assertEquals(frame_text(h):find("commands", 1, true) ~= nil, true,
                    "? should toggle help box")
    h:type("?")
    lt.assertEquals(frame_text(h):find("commands", 1, true), nil,
                    "? again should close help")
    h:unmount()
end

function suite:test_slash_theme_flips_theme()
    local h = testing.render(App, { cols = 80, rows = 24 })
    -- The plain frame text is the same before/after /theme (theme only
    -- changes colors, not characters). Assert via the accumulated ANSI
    -- diff instead: clear it, submit /theme, and look for color-code
    -- activity in the resulting diff.
    h:clear_ansi()
    h:type("/theme"):press("enter")
    local ansi = h:ansi()
    lt.assertEquals(#ansi > 0, true, "/theme should emit ANSI diff")
    lt.assertEquals(ansi:find("\27%[") ~= nil, true,
                    "diff should contain SGR escape codes from color change")
    h:unmount()
end

function suite:test_slash_model_opens_overlay()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("/model"):press("enter")
    local txt = frame_text(h)
    lt.assertEquals(txt:find("choose model", 1, true) ~= nil, true,
                    "model overlay header should appear")
    -- All four model labels must be visible (Select renders all when no
    -- limit is set). Catches the regression where limit=1 used to collapse
    -- the picker into a single hidden row.
    lt.assertEquals(txt:find("claude-opus-4", 1, true) ~= nil, true)
    lt.assertEquals(txt:find("claude-sonnet", 1, true) ~= nil, true)
    lt.assertEquals(txt:find("gpt-4o", 1, true) ~= nil, true)
    lt.assertEquals(txt:find("local/llama3", 1, true) ~= nil, true)
    h:unmount()
end

function suite:test_slash_model_pick_closes_overlay_and_updates_header()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("/model"):press("enter")
    -- Move to second model and pick.
    h:press("down"):press("enter")
    local txt = frame_text(h)
    lt.assertEquals(txt:find("choose model", 1, true), nil,
                    "overlay should close after picking")
    lt.assertEquals(txt:find("claude-sonnet", 1, true) ~= nil, true,
                    "header should reflect the newly picked model")
    h:unmount()
end

function suite:test_submit_appends_message_and_starts_streaming()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("hello"):press("enter")
    -- User message rendered immediately via Static.
    local txt = frame_text(h)
    lt.assertEquals(txt:find("[you] hello", 1, true) ~= nil, true)
    -- Streaming banner up (spinner + progress + percent).
    lt.assertEquals(txt:find("generating", 1, true) ~= nil, true,
                    "streaming banner should be visible right after submit")
    h:unmount()
end

function suite:test_streamed_reply_finalizes_into_history()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("hi"):press("enter")
    -- Advance enough virtual time for the full reply to stream + finalize.
    -- REPLIES[1] is ~35 chars + " (re: hi)" suffix, 40ms per char -> ~2s.
    h:advance(5000)
    local txt = frame_text(h)
    lt.assertEquals(txt:find("[bot]", 1, true) ~= nil, true,
                    "bot reply should land in history")
    lt.assertEquals(txt:find("generating", 1, true), nil,
                    "streaming banner should clear after finalize")
    h:unmount()
end

function suite:test_slash_clear_empties_history()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("first"):press("enter")
    h:advance(5000)
    lt.assertEquals(frame_text(h):find("[you] first", 1, true) ~= nil, true)
    h:type("/clear"):press("enter")
    lt.assertEquals(frame_text(h):find("[you] first", 1, true), nil,
                    "/clear should drop history rows")
    h:unmount()
end

function suite:test_slash_crash_shows_error_boundary_fallback()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("/crash"):press("enter")
    local txt = frame_text(h)
    lt.assertEquals(txt:find("caught error", 1, true) ~= nil, true,
                    "ErrorBoundary fallback should render after /crash")
    lt.assertEquals(txt:find("demo explosion", 1, true) ~= nil, true)
    h:unmount()
end

function suite:test_slash_reset_recovers_from_crash()
    local h = testing.render(App, { cols = 80, rows = 24 })
    h:type("/crash"):press("enter")
    lt.assertEquals(frame_text(h):find("caught error", 1, true) ~= nil, true)
    h:type("/reset"):press("enter")
    lt.assertEquals(frame_text(h):find("caught error", 1, true), nil,
                    "/reset should clear the boundary fallback")
    h:unmount()
end

-- Large terminal: ensure nothing breaks at typical wide sizes either.
function suite:test_large_terminal_renders_without_error()
    local h = testing.render(App, { cols = 120, rows = 40 })
    local txt = frame_text(h)
    lt.assertEquals(txt:find("chat demo", 1, true) ~= nil, true)
    lt.assertEquals(txt:find("uptime", 1, true) ~= nil, true)
    lt.assertEquals(txt:find("Enter: send", 1, true) ~= nil, true)
    h:unmount()
end

-- Small terminal: the app should show a "too small" fallback instead of
-- rendering a garbled layout.
function suite:test_small_terminal_shows_fallback()
    local h = testing.render(App, { cols = 20, rows = 5 })
    local txt = frame_text(h)
    lt.assertEquals(txt:find("terminal too small", 1, true) ~= nil, true,
                    "should show fallback when terminal is below minimum size")
    h:unmount()
end
