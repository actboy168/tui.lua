-- test/unit/test_mouse_mode.lua
-- Tests for the mouse mode level manager in tui.internal.input.

local lt        = require "ltest"
local input_mod = require "tui.internal.input"
local ansi      = require "tui.internal.ansi"

local suite = lt.test "mouse_mode"

local ESC = "\x1b"
local mm  = ansi.mouseMode

-- Helper: reset input state and capture written sequences.
local function setup()
    input_mod._reset()
    local written = {}
    input_mod.set_mouse_mode_writer(function(s) written[#written + 1] = s end)
    return written
end

-- Clear captured sequences in-place (reassigning the variable breaks the closure).
local function clear(w)
    for i = #w, 1, -1 do w[i] = nil end
end

local function teardown()
    input_mod.set_mouse_mode_writer(nil)
    input_mod._reset()
end

-- ---------------------------------------------------------------------------

-- Level 0 → 2 (drag): SGR + click_on + drag_on
function suite:test_request_drag_level_enables_sequences()
    local w = setup()
    local rel = input_mod.request_mouse_level(2)
    lt.assertEquals(w[1], mm.sgr_on,   "first: SGR on")
    lt.assertEquals(w[2], mm.click_on, "second: click on")
    lt.assertEquals(w[3], mm.drag_on,  "third: drag on")
    lt.assertEquals(#w, 3)
    rel()
    teardown()
end

-- Releasing drops back to 0: drag_off + click_off + sgr_off
function suite:test_release_drag_level_disables_sequences()
    local w = setup()
    local rel = input_mod.request_mouse_level(2)
    clear(w)
    rel()
    lt.assertEquals(w[1], mm.drag_off,  "first: drag off")
    lt.assertEquals(w[2], mm.click_off, "second: click off")
    lt.assertEquals(w[3], mm.sgr_off,   "third: SGR off")
    lt.assertEquals(#w, 3)
    teardown()
end

-- Level 1 (click only): only SGR + click_on
function suite:test_request_click_level()
    local w = setup()
    local rel = input_mod.request_mouse_level(1)
    lt.assertEquals(w[1], mm.sgr_on,   "SGR on")
    lt.assertEquals(w[2], mm.click_on, "click on")
    lt.assertEquals(#w, 2)
    clear(w)
    rel()
    lt.assertEquals(w[1], mm.click_off, "click off")
    lt.assertEquals(w[2], mm.sgr_off,   "SGR off")
    teardown()
end

-- Stacked refs: two requestors for level 2; mode stays until both release.
function suite:test_stacked_refs_stay_active()
    local w = setup()
    local r1 = input_mod.request_mouse_level(2)
    local r2 = input_mod.request_mouse_level(2)
    -- r2 at same level — no additional sequences sent
    lt.assertEquals(#w, 3)  -- only from r1
    clear(w)
    -- Releasing one should NOT disable yet
    r2()
    lt.assertEquals(#w, 0, "no disable while one ref still active")
    -- Releasing last ref should disable
    r1()
    lt.assertTrue(#w > 0, "disable sent after last ref released")
    teardown()
end

-- Upgrade from level 1 to level 2: only drag_on sent (no re-init of base).
function suite:test_upgrade_from_click_to_drag()
    local w = setup()
    local r1 = input_mod.request_mouse_level(1)  -- enables click+SGR
    clear(w)
    local r2 = input_mod.request_mouse_level(2)  -- should only add drag_on
    lt.assertEquals(#w, 1, "only drag_on added")
    lt.assertEquals(w[1], mm.drag_on)
    clear(w)
    r2()  -- back to level 1, only drag_off
    lt.assertEquals(#w, 1)
    lt.assertEquals(w[1], mm.drag_off)
    r1()
    teardown()
end

-- release() is idempotent (double-release should not double-send).
function suite:test_release_is_idempotent()
    local w = setup()
    local rel = input_mod.request_mouse_level(2)
    clear(w)
    rel()
    local first_count = #w
    rel()  -- second release — should be a no-op
    lt.assertEquals(#w, first_count, "double release sends no extra sequences")
    teardown()
end

-- No writer: request/release still tracks level in memory but sends nothing.
function suite:test_no_writer_no_crash()
    input_mod._reset()
    input_mod.set_mouse_mode_writer(nil)
    local rel = input_mod.request_mouse_level(2)
    rel()  -- should not crash
    lt.assertTrue(true, "no crash without writer")
end

return suite
