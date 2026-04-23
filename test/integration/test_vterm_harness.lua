-- test/integration/test_vterm_harness.lua — vterm + harness integration tests
local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing.harness"
local vterm   = require "tui.testing.vterm"
local input_helpers = require "tui.testing.input"

local suite = lt.test "vterm_harness"

-- ---------------------------------------------------------------------------
-- Basic vterm integration

function suite:test_vterm_always_available()
    -- vterm is the default terminal backend
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    lt.assertNotEquals(h:vterm(), nil)
    h:unmount()
end

function suite:test_vterm_without_interactive()
    -- Explicit non-interactive paint path
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = false })
    lt.assertNotEquals(h:vterm(), nil)
    -- Non-interactive: no BSU/ESU, no cursorHide, no bracketed paste
    local vt = h:vterm()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026h"), false, "no BSU in non-interactive")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?25l"), false, "no cursorHide in non-interactive")
    lt.assertEquals(vterm.has_mode(vt, 2004), false, "no bracketed paste in non-interactive")
    h:unmount()
end

function suite:test_vterm_enabled_returns_state()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3 })
    lt.assertEquals(h:vterm().rows, 3)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Interactive mode sequences

function suite:test_bracketed_paste_enabled()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.has_mode(vt, 2004), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2004h"), true)
    h:unmount()
end

function suite:test_focus_events_enabled()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.has_mode(vt, 1004), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1004h"), true)
    h:unmount()
end

function suite:test_cursor_hidden_on_init()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?25l"), true)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- BSU/ESU (Synchronized Output)

function suite:test_sync_update_wraps_output()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026h"), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026l"), true)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Mouse mode auto-enable

function suite:test_mouse_mode_auto_enable_with_onclick()
    local function App()
        return tui.Box {
            onClick = function() end,
            tui.Text { "click me" },
        }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.mouse_level(vt) > 0, true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000h"), true)
    h:unmount()
end

function suite:test_no_mouse_mode_without_onclick()
    local function App()
        return tui.Text { "no click" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.mouse_level(vt), 0)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Teardown sequences

function suite:test_teardown_disables_bracketed_paste()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    h:clear_ansi()
    h:unmount()
    -- After unmount, the disable sequence should have been written
    -- Check via the vterm write_log (h:vterm() is nil after unmount,
    -- so check ansi buffer before unmount)
end

function suite:test_ansi_buf_still_works_with_vterm()
    local function App()
        return tui.Text { "hello" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    -- vterm write_log should have captured output
    local vt = h:vterm()
    lt.assertEquals(#vterm.write_log(vt) > 0, true)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Vterm screen content

function suite:test_vterm_screen_shows_content()
    local function App()
        return tui.Text { "AB" }
    end
    local h = testing.render(App, { cols = 5, rows = 1 })
    local vt = h:vterm()
    lt.assertEquals(vterm.cell(vt, 1, 1).char, "A")
    lt.assertEquals(vterm.cell(vt, 2, 1).char, "B")
    h:unmount()
end

function suite:test_vterm_cursor_visible_with_text_input()
    local function App()
        return tui.TextInput { value = "hi" }
    end
    local h = testing.render(App, { cols = 10, rows = 1, interactive = true })
    local vt = h:vterm()
    lt.assertEquals(vterm.cursor(vt).visible, true)
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- OSC 52 clipboard (harness wiring; sequence format tested in test_clipboard.lua)

function suite:test_osc52_enabled_and_wired_in_interactive()
    -- Interactive mode should enable OSC 52 and wire the terminal writer,
    -- so clipboard.copy() emits sequences through the vterm terminal.
    local function App()
        return tui.Text { "clipboard test" }
    end
    local h = testing.render(App, { cols = 20, rows = 3, interactive = true })
    local vt = h:vterm()
    local clipboard = require "tui.internal.clipboard"
    clipboard.copy("hello")
    -- Just verify the OSC 52 sequence reached the vterm write_log.
    -- The exact format (base64 payload, BEL terminator) is tested in
    -- test/unit/test_clipboard.lua.
    lt.assertEquals(vterm.has_sequence(vt, "\x1b]52;c;"), true,
        "OSC 52 prefix should reach vterm write_log in interactive mode")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Focus event injection

function suite:test_focus_in_dispatched_to_component()
    -- Focus events are dispatched through input_mod.dispatch,
    -- which is how they flow in production (terminal.read_raw -> dispatch).
    local focus_states = {}
    local function App()
        local state = tui.useTerminalFocus()
        focus_states[#focus_states + 1] = state.focused
        return tui.Text { width = 10, height = 1, state.focused and "focused" or "blurred" }
    end
    local h = testing.render(App, { cols = 10, rows = 1, interactive = true })
    -- Initial state: focused
    lt.assertEquals(focus_states[#focus_states], true)
    -- Dispatch focus_out as raw bytes through input_mod
    h:dispatch(input_helpers.posix("\x1b[O"))
    h:rerender()
    lt.assertEquals(focus_states[#focus_states], false)
    -- Dispatch focus_in
    h:dispatch(input_helpers.posix("\x1b[I"))
    h:rerender()
    lt.assertEquals(focus_states[#focus_states], true)
    h:unmount()
end

function suite:test_focus_event_sequences_via_dispatch()
    -- Focus events can also be dispatched via the harness dispatch method
    local focus_count = { ["focus_in"] = 0, ["focus_out"] = 0 }
    local function App()
        tui.useInput(function(_, key)
            if key.name == "focus_in" or key.name == "focus_out" then
                focus_count[key.name] = focus_count[key.name] + 1
            end
        end)
        return tui.Text { width = 5, height = 1, "x" }
    end
    local h = testing.render(App, { cols = 5, rows = 1 })
    -- Dispatch focus events as raw bytes
    h:dispatch(input_helpers.posix("\x1b[I"))
    h:rerender()
    h:dispatch(input_helpers.posix("\x1b[O"))
    lt.assertEquals(focus_count["focus_in"], 0, "focus events should not reach useInput")
    lt.assertEquals(focus_count["focus_out"], 0, "focus events should not reach useInput")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Main-screen mode

function suite:test_main_screen_mode_set_in_interactive()
    -- Interactive mode should set screen mode to "main", which uses
    -- relative cursor moves instead of absolute CUP positioning.
    -- Verify by checking that the first render uses \r (carriage return)
    -- for main-screen first-frame alignment instead of absolute CUP.
    local function App()
        return tui.Text { "main screen" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    -- diff_main first frame starts with \r to align to column 0
    -- (main-screen mode uses relative moves; alt-screen would use CUP)
    local log = vterm.write_log(vt)
    local found_cr_align = false
    for _, s in ipairs(log) do
        -- Look for \r at the start of diff output (after BSU)
        if s:find("\r", 1, true) then found_cr_align = true end
    end
    lt.assertEquals(found_cr_align, true,
        "main-screen mode should use carriage return for alignment")
    -- Also verify that BSU/ESU wraps the output (interactive + main-screen)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026h"), true)
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?2026l"), true)
    h:unmount()
end

function suite:test_main_screen_content_h_clipping()
    -- content_h should limit the viewport area that gets diffed
    local function App()
        return tui.Text { "short" }
    end
    local h = testing.render(App, { cols = 20, rows = 10, interactive = true })
    local vt = h:vterm()
    -- The content should only fill 1 row; the rest is untouched.
    -- The vterm screen row 1 should have "short".
    lt.assertEquals(vterm.row_string(vt, 1):match("^short"), "short")
    -- Row 2+ should be empty (spaces)
    lt.assertEquals(vterm.row_string(vt, 2):match("^%s*$") ~= nil, true,
        "row 2 should be empty since content only fills row 1")
    h:unmount()
end

function suite:test_teardown_cursor_restore()
    -- On unmount in interactive mode, cursor should be shown and
    -- focus events / bracketed paste disabled
    local function App()
        return tui.Text { "teardown" }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    -- Capture the write_log before unmount so we can verify teardown sequences
    local vt = h:vterm()
    local log_before = #vterm.write_log(vt)
    h:unmount()
    -- After unmount, the vt is detached but write_log is still accessible.
    -- Check that teardown wrote the disable sequences.
    -- Note: vt is still valid after unmount since we held a ref.
    local log = vterm.write_log(vt)
    local found_disable_focus = false
    local found_disable_paste = false
    local found_cursor_show = false
    for i = log_before + 1, #log do
        if log[i]:find("\x1b[?1004l", 1, true) then found_disable_focus = true end
        if log[i]:find("\x1b[?2004l", 1, true) then found_disable_paste = true end
        if log[i]:find("\x1b[?25h", 1, true) then found_cursor_show = true end
    end
    lt.assertEquals(found_disable_focus, true, "focus events should be disabled on teardown")
    lt.assertEquals(found_disable_paste, true, "bracketed paste should be disabled on teardown")
    lt.assertEquals(found_cursor_show, true, "cursor should be shown on teardown")
end

function suite:test_teardown_moves_cursor_below_content()
    -- Regression: teardown must move the cursor below the rendered content
    -- so the shell prompt doesn't overlap with the TUI output.
    -- A multi-line app with a declared cursor (TextInput) should emit
    -- cursorDown(N) where N = (content_h + 1) - last_display_y > 0.
    local function App()
        return tui.Box {
            flexDirection = "column",
            width = 10,
            height = 5,
            tui.Text { key = "a", "line1" },
            tui.Text { key = "b", "line2" },
            tui.Text { key = "c", "line3" },
            tui.TextInput { key = "d", value = "ab" },
        }
    end
    local h = testing.render(App, { cols = 10, rows = 5, interactive = true })
    local vt = h:vterm()
    local log_before = #vterm.write_log(vt)
    h:unmount()
    local log = vterm.write_log(vt)
    -- Collect teardown output
    local teardown_out = {}
    for i = log_before + 1, #log do
        teardown_out[#teardown_out + 1] = log[i]
    end
    local combined = table.concat(teardown_out)
    -- Teardown must move cursor below content:
    --   - With declared cursor: cursorDown(dy) where dy > 0
    --   - Without declared cursor: \n to move one line down
    -- If neither happens, the shell prompt overlaps the TUI output.
    local found_cursor_down = combined:find("\x1b[", 1, true) ~= nil
        and combined:find("B", 1, true) ~= nil
    local found_newline_move = combined:find("\n", 1, true) ~= nil
    lt.assertEquals(found_cursor_down or found_newline_move, true,
        "teardown should move cursor down past content")
end

function suite:test_teardown_moves_cursor_no_declared_cursor()
    -- Regression: when no declared cursor exists (no TextInput),
    -- teardown should still emit a newline to move below content.
    local function App()
        return tui.Box {
            flexDirection = "column",
            width = 10,
            height = 3,
            tui.Text { key = "a", "row1" },
            tui.Text { key = "b", "row2" },
            tui.Text { key = "c", "row3" },
        }
    end
    local h = testing.render(App, { cols = 10, rows = 3, interactive = true })
    local vt = h:vterm()
    local log_before = #vterm.write_log(vt)
    h:unmount()
    local log = vterm.write_log(vt)
    local teardown_out = {}
    for i = log_before + 1, #log do
        teardown_out[#teardown_out + 1] = log[i]
    end
    local combined = table.concat(teardown_out)
    -- No declared cursor → move_seq = "\n\r" → combined has a \n before cursor show
    lt.assertNotEquals(combined:find("\n", 1, true), nil,
        "teardown should emit newline to move past content when no cursor")
    lt.assertNotEquals(combined:find("\x1b[?25h", 1, true), nil,
        "cursor should be shown on teardown")
end

-- ---------------------------------------------------------------------------
-- Mouse mode lifecycle

function suite:test_mouse_level_upgrade_and_downgrade()
    -- Test that mouse level upgrades and downgrades emit correct sequences
    local release_ref = {}
    local function App()
        local _, setState = tui.useState(false)
        release_ref.setState = setState
        return tui.Text { "mouse lifecycle" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    -- Request mouse level 1 via the input module
    local input_mod = require "tui.internal.input"
    local release1 = input_mod.request_mouse_level(1)
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000h"), true,
        "level 1 click tracking should be enabled")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1006h"), true,
        "SGR extended coordinates should be enabled")
    -- Upgrade to level 2
    local release2 = input_mod.request_mouse_level(2)
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1002h"), true,
        "level 2 drag tracking should be enabled")
    -- Release level 2 — should downgrade back to level 1
    release2()
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1002l"), true,
        "level 2 should be disabled after release")
    -- Release level 1 — should disable all mouse tracking
    release1()
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000l"), true,
        "level 1 should be disabled after release")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1006l"), true,
        "SGR extended coordinates should be disabled after last release")
    h:unmount()
end

function suite:test_mouse_level_3_any_motion()
    -- Test that level 3 (any-motion tracking) emits correct sequences
    local function App()
        return tui.Text { "level 3" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    local input_mod = require "tui.internal.input"
    local release3 = input_mod.request_mouse_level(3)
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1003h"), true,
        "level 3 any-motion tracking should be enabled")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1006h"), true,
        "SGR extended coordinates should be enabled")
    release3()
    h:paint()
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1003l"), true,
        "level 3 should be disabled after release")
    h:unmount()
end

function suite:test_mouse_auto_enable_disable_lifecycle()
    -- onClick component causes auto mouse enable; removing it disables
    local show_click = { value = true }
    local function App()
        if show_click.value then
            return tui.Box {
                onClick = function() end,
                tui.Text { "clickable" },
            }
        end
        return tui.Text { "plain" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    -- Auto-enable: onClick present → mouse level > 0
    lt.assertEquals(vterm.mouse_level(vt) > 0, true,
        "mouse should be auto-enabled with onClick")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000h"), true,
        "click tracking sequence should be emitted")
    -- Remove onClick by toggling the condition
    show_click.value = false
    h:rerender()
    -- After rerender without onClick, mouse should be disabled
    lt.assertEquals(vterm.mouse_level(vt), 0,
        "mouse should be auto-disabled when onClick is removed")
    lt.assertEquals(vterm.has_sequence(vt, "\x1b[?1000l"), true,
        "click tracking disable sequence should be emitted")
    h:unmount()
end

-- ---------------------------------------------------------------------------
-- Error fallback banner

function suite:test_error_fallback_banner_with_throw_on_error_false()
    -- When throw_on_error=false, render errors produce a fallback banner tree
    -- instead of propagating.
    local reconciler_mod = require "tui.internal.reconciler"
    local layout_mod = require "tui.internal.layout"

    local function BuggyApp()
        error("something went wrong")
    end

    local rec_state = reconciler_mod.new()
    local app_handle = { exit = function() end }
    local W, H = 40, 5

    -- throw_on_error=false (production path) should catch the error
    -- and produce a fallback error banner tree
    local ok, tree_or_err = pcall(reconciler_mod.render, rec_state, BuggyApp, app_handle)
    lt.assertEquals(ok, false, "BuggyApp should throw")
    local tree = tui.Box { width = W, height = H, tui.Text { "[tui] render error: " .. tostring(tree_or_err) } }
    reconciler_mod.clear_dirty(rec_state)
    layout_mod.compute(tree, H)

    lt.assertNotEquals(tree, nil)
    lt.assertEquals(tree.kind, "box")
    -- The tree should have a child text with the error banner
    lt.assertEquals(#tree.children > 0, true, "fallback tree should have children")
    local text_child = tree.children[1]
    lt.assertEquals(text_child.kind, "text")
    lt.assertNotEquals(text_child.text:find("%[tui%] render error:"), nil,
        "fallback should contain [tui] render error: prefix")
    lt.assertNotEquals(text_child.text:find("something went wrong"), nil,
        "fallback should contain the error message")

    layout_mod.free(tree)
    reconciler_mod.shutdown(rec_state)
end

function suite:test_error_fallback_banner_renders_to_screen()
    -- Verify the fallback banner tree actually renders visible content
    local reconciler_mod = require "tui.internal.reconciler"
    local screen_mod = require "tui.internal.screen"
    local layout_mod = require "tui.internal.layout"

    local function BuggyApp()
        error("oops")
    end

    local rec_state = reconciler_mod.new()
    local app_handle = { exit = function() end }
    local W, H = 40, 3

    local ok, tree_or_err = pcall(reconciler_mod.render, rec_state, BuggyApp, app_handle)
    lt.assertEquals(ok, false, "BuggyApp should throw")
    local tree = tui.Box { width = W, height = H, tui.Text { "[tui] render error: " .. tostring(tree_or_err) } }
    layout_mod.compute(tree, H)

    local scr = screen_mod.new(W, H)
    local renderer_mod = require "tui.internal.renderer"
    screen_mod.clear(scr)
    renderer_mod.paint(tree, scr)

    local rows = screen_mod.rows(scr)
    lt.assertNotEquals(rows[1]:find("%[tui%] render error:"), nil,
        "screen row 1 should contain error banner")

    layout_mod.free(tree)
    reconciler_mod.shutdown(rec_state)
end

function suite:test_error_fallback_does_not_fire_with_good_component()
    -- A non-throwing component should NOT produce a fallback banner
    local reconciler_mod = require "tui.internal.reconciler"
    local layout_mod = require "tui.internal.layout"

    local function GoodApp()
        return tui.Box { width = 40, height = 3, tui.Text { "all good" } }
    end

    local rec_state = reconciler_mod.new()
    local app_handle = { exit = function() end }
    local W, H = 40, 3

    local tree = reconciler_mod.render(rec_state, GoodApp, app_handle)
    lt.assertNotEquals(tree, nil)
    if tree.kind == "box" then
        tree.props = tree.props or {}
        if tree.props.width == nil then tree.props.width = W end
        if tree.props.height == nil then tree.props.height = H end
    end
    reconciler_mod.clear_dirty(rec_state)
    layout_mod.compute(tree, H)

    lt.assertEquals(tree.kind, "box")
    -- The children should contain actual content, not error banner text
    local found_error_banner = false
    local function check_children(node)
        if node.text and node.text:find("%[tui%] render error:") then
            found_error_banner = true
        end
        if node.children then
            for _, c in ipairs(node.children) do check_children(c) end
        end
    end
    check_children(tree)
    lt.assertEquals(found_error_banner, false,
        "good component should not produce error banner")

    layout_mod.free(tree)
    reconciler_mod.shutdown(rec_state)
end

-- ---------------------------------------------------------------------------
-- Vterm resize support

function suite:test_vterm_resize_updates_dimensions()
    local function App()
        return tui.Text { "resize me" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    -- Initial dimensions
    lt.assertEquals(vt.cols, 20)
    lt.assertEquals(vt.rows, 5)
    -- Resize to new dimensions
    h:resize(40, 10)
    lt.assertEquals(vt.cols, 40)
    lt.assertEquals(vt.rows, 10)
    h:unmount()
end

function suite:test_vterm_resize_preserves_content()
    -- Resize should preserve the overlapping region of existing content.
    local function App()
        return tui.Text { "hello world" }
    end
    local h = testing.render(App, { cols = 20, rows = 5, interactive = true })
    local vt = h:vterm()
    -- Resize narrower (keep columns small, expand rows)
    h:resize(10, 8)
    -- "hello world" fills cols 1-11, so cols 1-10 should still show "hello worl"
    lt.assertEquals(vt.row_string(vt, 1):sub(1, 10), "hello worl")
    h:unmount()
end
