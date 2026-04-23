local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "testing_support_modules"

local function snapshot_name(prefix)
    local id = tostring({}):gsub("^table: ", ""):gsub("[^%w]", "")
    return prefix .. "_" .. id
end

local function snapshot_path(name)
    return "test/__snapshots__/" .. name .. ".txt"
end

local function remove_if_exists(path)
    os.remove(path)
end

local function write_file(path, content)
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
end

function suite:test_capture_stderr_nesting_keeps_buffers_separate()
    local outer = testing.capture_stderr(function()
        io.stderr:write("[tui:dev] outer one\n")
        local inner = testing.capture_stderr(function()
            io.stderr:write("[tui:dev] inner only\n")
        end)
        lt.assertNotEquals(inner:find("inner only", 1, true), nil)
        lt.assertEquals(inner:find("outer one", 1, true), nil)
        io.stderr:write("[tui:test] outer two\n")
    end)

    lt.assertNotEquals(outer:find("outer one", 1, true), nil)
    lt.assertNotEquals(outer:find("outer two", 1, true), nil)
    lt.assertEquals(outer:find("inner only", 1, true), nil)
end

function suite:test_capture_stderr_restores_after_error()
    local ok, err = pcall(function()
        testing.capture_stderr(function()
            io.stderr:write("[tui:dev] before boom\n")
            error("boom")
        end)
    end)
    lt.assertFalse(ok)
    lt.assertNotEquals(tostring(err):find("boom", 1, true), nil)

    local captured = testing.capture_stderr(function()
        io.stderr:write("[tui:dev] after boom\n")
    end)
    lt.assertNotEquals(captured:find("after boom", 1, true), nil)
end

function suite:test_snapshot_first_write_and_crlf_trim_compare()
    local name = snapshot_name("tmp_snapshot_norm")
    local path = snapshot_path(name)
    remove_if_exists(path)

    local h = testing.render(function()
        return tui.Text { "x" }
    end, { cols = 3, rows = 1 })

    h:match_snapshot(name)
    local rf = assert(io.open(path, "rb"))
    local first = rf:read("*a")
    rf:close()
    lt.assertEquals(first, "x\n")

    write_file(path, "x  \r\n")
    h:match_snapshot(name)
    h:unmount()
    remove_if_exists(path)
end

function suite:test_snapshot_mismatch_reports_context()
    local name = snapshot_name("tmp_snapshot_diff")
    local path = snapshot_path(name)
    remove_if_exists(path)
    write_file(path, "old\n")

    local h = testing.render(function()
        return tui.Text { "new" }
    end, { cols = 3, rows = 1 })

    local ok, err = pcall(function()
        h:match_snapshot(name)
    end)
    h:unmount()
    remove_if_exists(path)

    lt.assertFalse(ok)
    local msg = tostring(err)
    lt.assertNotEquals(msg:find("snapshot mismatch", 1, true), nil)
    lt.assertNotEquals(msg:find("first diff at line 1", 1, true), nil)
    lt.assertNotEquals(msg:find("re-run with TUI_UPDATE_SNAPSHOTS=1", 1, true), nil)
end

function suite:test_find_helpers_handle_nil_tree()
    lt.assertEquals(testing.find_by_kind(nil, "text"), nil)
    lt.assertEquals(testing.find_all_by_kind(nil, "text"), {})
    lt.assertEquals(testing.text_content(nil), {})
    lt.assertEquals(testing.find_text_with_cursor(nil), nil)
end

function suite:test_dispatch_event_repaints_and_returns_self()
    local value = ""
    local function App()
        tui.useInput(function(str, key)
            if key.name == "char" then
                value = value .. str
            end
        end)
        return tui.Text { value }
    end
    local h = testing.render(App, { cols = 10, rows = 1 })
    local same = h:dispatch_event {
        name = "char",
        input = "x",
        raw = "x",
        ctrl = false,
        meta = false,
        shift = false,
    }
    lt.assertNotEquals(h:row(1):find("x", 1, true), nil)
    h:unmount()
end

function suite:test_load_app_runtime_error_path_and_restore()
    local bad = os.tmpname() .. ".lua"
    local f = assert(io.open(bad, "wb"))
    f:write("error('load-app-boom')\n")
    f:close()

    local ok, err = pcall(testing.load_app, bad)
    remove_if_exists(bad)
    lt.assertFalse(ok)
    lt.assertNotEquals(tostring(err):find("load_app: error", 1, true), nil)
    lt.assertNotEquals(tostring(err):find("load-app-boom", 1, true), nil)

    local good = os.tmpname() .. ".lua"
    local f2 = assert(io.open(good, "wb"))
    f2:write("local tui = require 'tui'\n")
    f2:write("tui.render(function() return tui.Text { 'ok' } end)\n")
    f2:close()

    local App = testing.load_app(good)
    remove_if_exists(good)
    local h = testing.render(App, { cols = 10, rows = 1 })
    lt.assertNotEquals(h:row(1):find("ok", 1, true), nil)
    h:unmount()
end

return suite
