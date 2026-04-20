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

local lt      = require "ltest"
local testing = require "tui.testing"

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
        h:press("up"):press("up"):press("up")
    end)
    lt.assertNotEquals(frame:find("3", 1, true), nil)
end

function suite:test_counter_decrement()
    local frame = load_frame_after("examples/counter.lua", { cols = 30, rows = 10 }, function(h)
        h:press("down")
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
