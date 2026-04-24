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

local lt            = require "ltest"
local testing       = require "tui.testing"
local hit_test      = require "tui.internal.hit_test"
local input_helpers = require "tui.testing.input"

local suite         = lt.test "examples"

-- Helper: render an example, capture a frame, unmount, then return the frame.
-- Unmounting before assertions ensures the harness is always torn down even
-- if a later assertion fails.
local function load_frame(path, opts)
    local frame
    testing.capture_stderr(function()
        local App = testing.load_app(path)
        local h   = testing.harness(App, opts)
        frame     = h:frame()
        h:unmount()
    end)
    return frame
end

-- Like load_frame but runs a callback to drive the harness before capturing.
local function load_frame_after(path, opts, drive_fn)
    local frame
    testing.capture_stderr(function()
        local App = testing.load_app(path)
        local h   = testing.harness(App, opts)
        drive_fn(h)
        h:rerender()
        frame = h:frame()
        h:unmount()
    end)
    return frame
end

local function has_hyperlink(h, rows, url)
    for row = 1, rows do
        for _, cell in ipairs(h:cells(row)) do
            if cell.hyperlink == url then
                return true
            end
        end
    end
    return false
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
        local h = testing.harness(App, { cols = 40, rows = 10 })
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
        h:press("up"); h:rerender()
        h:rerender()
        h:press("up"); h:rerender()
        h:rerender()
        h:press("up"); h:rerender()
    end)
    lt.assertNotEquals(frame:find("3", 1, true), nil)
end

function suite:test_counter_decrement()
    local frame = load_frame_after("examples/counter.lua", { cols = 30, rows = 10 }, function(h)
        h:press("down"); h:rerender()
    end)
    lt.assertNotEquals(frame:find("-1", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- progress_demo.lua
-- ---------------------------------------------------------------------------

function suite:test_progress_demo_initial_render()
    local frame = load_frame("examples/progress_demo.lua", { cols = 60, rows = 15 })
    -- Content is taller than terminal (padding+gap pushes height ~19);
    -- bottom 15 rows are visible.  "0%" and "Esc 退出" are in the lower half.
    lt.assertNotEquals(frame:find("0%", 1, true), nil)
    lt.assertNotEquals(frame:find("Esc", 1, true), nil)
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
-- todo_list.lua
-- ---------------------------------------------------------------------------

function suite:test_todo_list_shows_empty_placeholder()
    local frame = load_frame("examples/todo_list.lua", { cols = 45, rows = 17 })
    lt.assertNotEquals(frame:find("暂无任务", 1, true), nil)
    lt.assertNotEquals(frame:find("添加新任务...", 1, true), nil)
end

function suite:test_todo_list_adds_task_on_submit()
    local frame = load_frame_after("examples/todo_list.lua", { cols = 45, rows = 17 }, function(h)
        h:type("Buy milk")
        h:rerender()
        h:press("enter")
        h:rerender()
    end)
    lt.assertNotEquals(frame:find("Buy milk", 1, true), nil)
    lt.assertNotEquals(frame:find("[ ]", 1, true), nil)
    lt.assertEquals(frame:find("暂无任务", 1, true), nil)
end

function suite:test_todo_list_clears_input_after_submit()
    local h = testing.load_app("examples/todo_list.lua")
    testing.capture_stderr(function()
        h = testing.harness(h, { cols = 45, rows = 17 })
        h:type("Do something")
        h:rerender()
        h:press("enter")
        h:rerender()

        lt.assertNotEquals(h:frame():find("Do something", 1, true), nil)

        -- Input row should be cleared after submit.
        local input_row = h:row(4)
        lt.assertEquals(input_row:find("Do something", 1, true), nil,
            "input row should be cleared after submit")

        h:unmount()
    end)
end

function suite:test_todo_list_empty_submit_noop()
    local frame = load_frame_after("examples/todo_list.lua", { cols = 45, rows = 17 }, function(h)
        h:press("enter")
    end)
    lt.assertNotEquals(frame:find("暂无任务", 1, true), nil)
end

-- ---------------------------------------------------------------------------
-- hyperlink examples
-- ---------------------------------------------------------------------------

function suite:test_link_example_initial_render()
    local frame = load_frame("examples/link.lua", { cols = 70, rows = 12 })
    lt.assertNotEquals(frame:find("Link 示例", 1, true), nil)
    lt.assertNotEquals(frame:find("可激活链接", 1, true), nil)
    lt.assertNotEquals(frame:find("状态: 尚未激活", 1, true), nil)
end

function suite:test_link_example_enter_updates_status()
    local frame = load_frame_after("examples/link.lua", { cols = 70, rows = 12 }, function(h)
        h:press("enter")
    end)
    lt.assertNotEquals(frame:find("状态: keyboard -> https://example.com/docs", 1, true), nil)
end

function suite:test_raw_ansi_example_initial_render()
    local frame = load_frame("examples/raw_ansi.lua", { cols = 70, rows = 10 })
    lt.assertNotEquals(frame:find("RawAnsi 示例", 1, true), nil)
    lt.assertNotEquals(frame:find("raw-docs", 1, true), nil)
end

function suite:test_raw_ansi_example_exposes_hyperlink_metadata()
    testing.capture_stderr(function()
        local App = testing.load_app("examples/raw_ansi.lua")
        local h   = testing.harness(App, { cols = 70, rows = 10 })
        lt.assertTrue(has_hyperlink(h, 10, "https://example.com/raw"))
        h:unmount()
    end)
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
-- The chat example uses <Textarea> which internally adds onMouseDown/onScroll
-- to its wrapper Box. These tests verify the hit-test → dispatch pipeline
-- works end-to-end: click to focus, click to position cursor, scroll.

--- Find the first Box element in the tree with an onMouseDown prop.
local function find_clickable_box(tree)
    local function walk(e)
        if not e then return nil end
        if e.kind == "box" and e.props and type(e.props.onMouseDown) == "function" then
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

function suite:test_link_example_mouse_click_updates_status()
    testing.capture_stderr(function()
        local App = testing.load_app("examples/link.lua")
        local h   = testing.harness(App, { cols = 70, rows = 12 })
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a clickable Link box")
        local r = box.rect
        local cx, cy = h:sgr(r.x, r.y)
        h:mouse("down", 1, cx, cy)
        h:rerender()
        local frame = h:frame()
        lt.assertNotEquals(frame:find("状态: mouse -> https://example.com/docs", 1, true), nil)
        lt.assertTrue(has_hyperlink(h, 12, "https://example.com/docs"))
        h:unmount()
    end)
end

function suite:test_chat_tree_has_mouse_props()
    -- The chat example's Textarea adds onMouseDown/onScroll, so the tree
    -- should be detected as needing mouse mode by has_mouse_props.
    testing.capture_stderr(function()
        local App  = testing.load_app("examples/chat.lua")
        local h    = testing.harness(App, { cols = 40, rows = 10 })
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
        local h   = testing.harness(App, { cols = 40, rows = 10 })

        -- Find the Textarea's clickable Box and click its first cell.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a clickable Box in the tree")
        local r = box.rect
        lt.assertNotEquals(r, nil, "clickable Box should have a rect")

        -- Click the top-left content cell of the Textarea Box.
        local cx, cy = h:sgr(r.x, r.y)
        h:mouse("down", 1, cx, cy)
        h:rerender()
        h:mouse("up", 1, cx, cy)

        -- Now type — should go into the Textarea.
        h:type("hi")
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
        local h   = testing.harness(App, { cols = 40, rows = 10 })

        -- First focus by typing (autoFocus should handle this).
        h:type("abcde")
        h:rerender()

        -- Find the Textarea's clickable Box.
        local box = find_clickable_box(h:tree())
        lt.assertNotEquals(box, nil)
        local r = box.rect

        -- Click at column offset 2 (3rd cell) within the Box to move cursor
        -- between 'b' and 'c'.
        local cx, cy = h:sgr(r.x + 2, r.y)
        h:mouse("down", 1, cx, cy)
        h:rerender()
        h:mouse("up", 1, cx, cy)

        -- Type at the new cursor position.
        h:type("X")
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
        local h   = testing.harness(App, { cols = 40, rows = 6 })

        -- Focus and fill the Textarea with many lines.
        -- A 6-row terminal has room for border (2 rows) + ~4 content rows.
        -- Adding 6 lines forces scrolling.
        for i = 1, 5 do
            h:type("L" .. i)
            h:rerender()
            h:dispatch("\x1b[13;2u") -- Shift+Enter → newline
        end
        h:type("L6")

        -- Find the scrollable Box.
        local box = find_scrollable_box(h:tree())
        lt.assertNotEquals(box, nil, "should find a scrollable Box")
        local r = box.rect

        -- Scroll down inside the Textarea.
        local scroll_x = r.x + 1
        local scroll_y = r.y + 1
        h:mouse("scroll_down", nil, scroll_x, scroll_y)

        -- After scrolling down, the first line should have moved up
        -- out of view.
        local frame_after = h:frame()
        lt.assertEquals(frame_after:find("L1", 1, true), nil,
            "L1 should have scrolled out of view")
        h:unmount()
    end)
end
