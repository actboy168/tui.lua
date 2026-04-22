-- test/integration/test_examples.lua — non-intrusive example tests.
--
-- Uses testing.load_app() to load each example file without modifying it.
-- tui.render() is intercepted so the example's event loop never starts;
-- the captured root component is then mounted in the test harness instead.
--
-- Examples are production code and do not carry `key` props on every sibling
-- (not required outside dev mode). Each test wraps dev-render inside
-- testing.capture_stderr() to suppress those warnings, then unmounts before
-- running assertions so the harness is always cleaned up.

local lt       = require "ltest"
local testing  = require "tui.testing"
local tui_input = require "tui.input"
local tui_input = require "tui.input"
local hit_test = require "tui.internal.hit_test"
local input_helpers = require "tui.testing.input"

local suite = lt.test "examples"

-- Helper: render an example, capture a frame, unmount, then return the frame.
-- Unmounting before assertions ensures the harness is always torn down even
-- if a later assertion fails.
local function load_frame(path, opts)
    local frame
    testing.capture_stderr(function()
        local App = testing.load_app(path)
        local h   = testing.render(App, opts)
        frame = h:frame()
        h:unmount()
    end)
    return frame
end

-- Like load_frame but runs a callback to drive the harness before capturing.
local function load_frame_after(path, opts, drive_fn)
    local frame
    testing.capture_stderr(function()
        local App = testing.load_app(path)
        local h   = testing.render(App, opts)
        drive_fn(h)
        h:rerender()
        frame = h:frame()
        h:unmount()
    end)
    return frame
end

-- ---------------------------------------------------------------------------
-- hello.lua
-- ---------------------------------------------------------------------------

function suite:test_hello_renders_greeting()
    local frame = load_frame("examples/hello.lua", { cols = 40, rows = 10 })
    lt.assertNotEquals(frame:find("Hello, tui.lua!", 1, true), nil)
end

function suite:test_hello_snapshot()
    testing.capture_stderr(function()
        local App = testing.load_app("examples/hello.lua")
        local h = testing.render(App, { cols = 40, rows = 10 })
        h:match_snapshot("example_hello_40x10")
        h:unmount()
    end)
end

-- ---------------------------------------------------------------------------
-- counter.lua
-- ---------------------------------------------------------------------------

function suite:test_counter_initial_zero()
    local frame = load_frame("examples/counter.lua", { cols = 30, rows = 10 })
    lt.assertNotEquals(frame:find("0", 1, true), nil)
end

function suite:test_counter_increment()
    local frame = load_frame_after("examples/counter.lua", { cols = 30, rows = 10 }, function(h)
        tui_input.press("up"); h:rerender()
        tui_input.press("up"); h:rerender()
        tui_input.press("up"); h:rerender()
    end)
    lt.assertNotEquals(frame:find("3", 1, true), nil)
end

function suite:test_counter_decrement()
    local frame = load_frame_after("examples/counter.lua", { cols = 30, rows = 10 }, function(h)
        tui_input.press("down"); h:rerender()
    end)
    lt.assertNotEquals(frame:find("-1", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- progress_demo.lua
-- ---------------------------------------------------------------------------

function suite:test_progress_demo_initial_render()
    local frame = load_frame("examples/progress_demo.lua", { cols = 60, rows = 15 })
    lt.assertNotEquals(frame:find("进度演示", 1, true), nil)
    lt.assertNotEquals(frame:find("0%", 1, true), nil)
end

function suite:test_progress_demo_advances_with_time()
    -- Each 100ms tick adds 2%; advance 500ms → 10%
    local frame = load_frame_after("examples/progress_demo.lua", { cols = 60, rows = 15 }, function(h)
        h:advance(500)
    end)
    lt.assertNotEquals(frame:find("10%", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- select_menu.lua
-- ---------------------------------------------------------------------------

function suite:test_select_menu_shows_items()
    local frame = load_frame("examples/select_menu.lua", { cols = 40, rows = 15 })
    lt.assertNotEquals(frame:find("主菜单", 1, true), nil)
    lt.assertNotEquals(frame:find("新建项目", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- load_app error handling
-- ---------------------------------------------------------------------------

function suite:test_load_app_bad_path_raises()
    local ok, err = pcall(testing.load_app, "examples/nonexistent.lua")
    lt.assertFalse(ok)
    lt.assertNotEquals(err:find("load_app", 1, true), nil)
end

function suite:test_load_app_no_render_call_raises()
    -- A valid Lua file that doesn't call tui.render() should error.
    local tmpfile = os.tmpname() .. ".lua"
    local f = io.open(tmpfile, "w")
    f:write("-- no tui.render() call\nlocal x = 1\n")
    f:close()

    local ok, err = pcall(testing.load_app, tmpfile)
    os.remove(tmpfile)

    lt.assertFalse(ok)
    lt.assertNotEquals(err:find("did not call tui.render", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- chat.lua — mouse interaction tests
-- ---------------------------------------------------------------------------
-- The chat example uses <Textarea> which internally adds onClick/onScroll
-- to its wrapper Box. These tests verify the hit-test → dispatch pipeline
-- works end-to-end: click to focus, click to position cursor, scroll.

--- Find the first Box element in the tree with an onClick prop.
local function find_clickable_box(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "box" and e.props and type(e.props.onClick) == "function" then
            return e
        end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

--- Find the first Box element in the tree with an onScroll prop.
local function find_scrollable_box(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "box" and e.props and type(e.props.onScroll) == "function" then
            return e
        end
        for _, c in ipairs(e.children or {}) do
            local r = walk(c)
            if r then return r end
        end
    end
    return walk(tree)
end

function suite:test_chat_tree_has_mouse_props()
    -- The chat example's Textarea adds onClick/onScroll, so the tree
    -- should be detected as needing mouse mode by has_mouse_props.
    testing.capture_stderr(function()
        local App = testing.load_app("examples/chat.lua")
        local h   = testing.render(App, { cols = 40, rows = 10 })
        local tree = h:tree()
        lt.assertTrue(hit_test.has_mouse_props(tree))
        h:unmount()
    end)
end

function suite:test_chat_click_focuses_textarea()
    -- Click on the Textarea area should focus it, allowing subsequent
    -- keyboard input to go into the Textarea.
    local value = nil
    testing.capture_stderr(function()
        local App = testing.load_app("examples/chat.lua")
        local h   = testing.render(App, { cols = 40, rows = 10 })

        -- Find the Textarea's clickable Box and click its first cell.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a clickable Box in the tree")
        local r = box.rect
        lt.assertNotEquals(r, nil, "clickable Box should have a rect")

        -- Click the top-left content cell of the Textarea Box.
        -- SGR coordinates are 1-based; rect is 0-based, so add 1.
        local click_x = r.x + 1
        local click_y = r.y + 1
        tui_input.mouse("down", 1, click_x, click_y)
        tui_input.mouse("up", 1, click_x, click_y)

        -- Now type — should go into the Textarea.
        tui_input.type("hi")
        h:rerender()
        local frame = h:frame()
        lt.assertNotEquals(frame:find("hi", 1, true), nil, "typed text should appear in the frame")
        h:unmount()
    end)
end

function suite:test_chat_click_positions_cursor()
    -- Type some text, then click at a specific column to move the cursor
    -- and verify subsequent typing goes at the clicked position.
    testing.capture_stderr(function()
        local App = testing.load_app("examples/chat.lua")
        local h   = testing.render(App, { cols = 40, rows = 10 })

        -- First focus by typing (autoFocus should handle this).
        tui_input.type("abcde")
        h:rerender()

        -- Find the Textarea's clickable Box.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil)
        local r = box.rect

        -- Click at column offset 2 (3rd cell) within the Box to move cursor
        -- between 'b' and 'c'.  SGR x = rect.x + 1 (1-based) + 2 (offset).
        local click_x = r.x + 1 + 2
        local click_y = r.y + 1
        tui_input.mouse("down", 1, click_x, click_y)
        tui_input.mouse("up", 1, click_x, click_y)

        -- Type at the new cursor position.
        tui_input.type("X")
        h:rerender()
        local frame = h:frame()
        -- Cursor was between 'b' and 'c', so "abXcde" should appear.
        lt.assertNotEquals(frame:find("abXcde", 1, true), nil,
            "cursor should be repositioned by click; got: " .. frame)
        h:unmount()
    end)
end

function suite:test_chat_scroll_in_textarea()
    -- When Textarea content exceeds its visible height, scroll events
    -- should scroll the viewport. Use a small terminal and enough lines
    -- so the content overflows.
    testing.capture_stderr(function()
        local App = testing.load_app("examples/chat.lua")
        local h   = testing.render(App, { cols = 40, rows = 6 })

        -- Focus and fill the Textarea with many lines.
        -- A 6-row terminal has room for border (2 rows) + ~4 content rows.
        -- Adding 6 lines forces scrolling.
        for i = 1, 5 do
            tui_input.type("L" .. i)
            h:dispatch(input_helpers.raw("\x1b[13;2u"))  -- Shift+Enter → newline
        end
        tui_input.type("L6")

        -- Find the scrollable Box.
        local box = find_scrollable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a scrollable Box")
        local r = box.rect

        -- Scroll down inside the Textarea.
        local scroll_x = r.x + 1
        local scroll_y = r.y + 1
        tui_input.mouse("scroll_down", nil, scroll_x, scroll_y)

        -- After scrolling down, the first line should have moved up
        -- out of view.
        local frame_after = h:frame()
        lt.assertEquals(frame_after:find("L1", 1, true), nil,
            "L1 should have scrolled out of view")
        h:unmount()
    end)
end
