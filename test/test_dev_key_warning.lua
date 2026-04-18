-- test/test_dev_key_warning.lua — Stage 17 missing-key warning in reconciler.
-- When a parent has 3+ element children and any of them lacks a `key` prop,
-- dev mode emits a [tui:dev] stderr warning. Deduped per (parent_path, render
-- pass), so the same offending list does not spam on every rerender.
-- (Static 2-child compositions like `Box { A, B }` intentionally do NOT warn —
-- they are almost never the site of keying bugs; matches Ink/React DevTools.)

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"

local suite = lt.test "dev_key_warning"

-- 2+ element children, all keyless → warning fires.
function suite:test_missing_key_warns()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
                tui.Text { "c" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("[tui:dev]", 1, true) ~= nil, true,
        "expected dev warning, got: " .. stderr)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true) ~= nil, true,
        "expected 'unique key prop' in message, got: " .. stderr)
    -- Source location prefix should point at the test file, not reconciler.
    lt.assertEquals(stderr:find("test_dev_key_warning.lua:", 1, true) ~= nil, true,
        "expected source location prefix, got: " .. stderr)
end

-- All children keyed → no warning.
function suite:test_all_keyed_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                { kind = "text", children = { "a" }, props = {}, key = "a" },
                { kind = "text", children = { "b" }, props = {}, key = "b" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "did not expect warning, got: " .. stderr)
end

-- Single child (no siblings) → no warning.
function suite:test_single_child_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box { tui.Text { "only" } }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "did not expect warning for single child, got: " .. stderr)
end

-- Text node's string children don't trigger (Text children are strings).
function suite:test_text_string_children_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Text { "hello", " ", "world" }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "text string children should not trigger, got: " .. stderr)
end

-- Warning deduped within a single render: parent's loop runs once even with
-- many violating children, only one warning line for that parent path.
function suite:test_warning_deduped_per_render()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
                tui.Text { "c" },
                tui.Text { "d" },
                tui.Text { "e" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    -- Count occurrences by searching repeatedly.
    local n, pos = 0, 1
    while true do
        local i = stderr:find("[tui:dev]", pos, true)
        if not i then break end
        n = n + 1
        pos = i + 1
    end
    lt.assertEquals(n, 1, "expected exactly 1 warning, got " .. n ..
        " in stderr: " .. stderr)
end

-- 2 element children → no warning (threshold is 3+).
function suite:test_two_children_no_warn()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
            }
        end
        local b = testing.mount_bare(App)
        b:unmount()
    end)
    lt.assertEquals(stderr:find("unique `key` prop", 1, true), nil,
        "2 children should not trigger key warning, got: " .. stderr)
end

-- Rerender produces a fresh warning (dedup resets per render pass).
function suite:test_warning_repeats_on_rerender()
    local stderr = testing.capture_stderr(function()
        local function App()
            return tui.Box {
                tui.Text { "a" },
                tui.Text { "b" },
                tui.Text { "c" },
            }
        end
        local b = testing.mount_bare(App)
        b:rerender()
        b:rerender()
        b:unmount()
    end)
    local n, pos = 0, 1
    while true do
        local i = stderr:find("[tui:dev]", pos, true)
        if not i then break end
        n = n + 1
        pos = i + 1
    end
    -- 3 renders × 1 warning each = 3 total.
    lt.assertEquals(n, 3, "expected 3 warnings across 3 renders, got " .. n)
end
