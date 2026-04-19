-- test/property/test_no_crash_random_size.lua — no crash on arbitrary terminal sizes.
--
-- Property: rendering with any valid terminal size (1×1 through 200×100)
-- does not produce an error.

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"
local pbt     = require "test.property.pbt"

local suite = lt.test "no_crash_random_size"

-- ---------------------------------------------------------------------------
-- App shape builders — representative component trees.

local SHAPES = {}

-- Shape 1: simple box with text
table.insert(SHAPES, function(rng)
    return function()
        return tui.Box {
            tui.Text { "hello" },
        }
    end
end)

-- Shape 2: row of flex-growing boxes
table.insert(SHAPES, function(rng)
    return function()
        return tui.Box {
            flexDirection = "row",
            tui.Box { key = "a", flexGrow = 1, tui.Text { "A" } },
            tui.Box { key = "b", flexGrow = 1, tui.Text { "B" } },
            tui.Box { key = "c", flexGrow = 1, tui.Text { "C" } },
        }
    end
end)

-- Shape 3: focused TextInput
table.insert(SHAPES, function(rng)
    local v = "test"
    return function()
        return tui.Box {
            tui.TextInput {
                value = v,
                onChange = function(nv) v = nv end,
            },
        }
    end
end)

-- Shape 4: box with border, padding, and nested text
table.insert(SHAPES, function(rng)
    local border = rng.pick({ "single", "round" })
    return function()
        return tui.Box {
            borderStyle = border,
            paddingX = 1,
            tui.Text { "content" },
        }
    end
end)

-- Shape 5: 5 levels of nested boxes
table.insert(SHAPES, function(rng)
    return function()
        local function nest(d)
            if d == 0 then
                return tui.Text { "leaf" }
            end
            return tui.Box { paddingLeft = 1, nest(d - 1) }
        end
        return tui.Box { nest(5) }
    end
end)

-- ---------------------------------------------------------------------------
-- Test

function suite:test_no_crash_on_random_sizes()
    pbt.check {
        name       = "no crash on random sizes",
        iterations = 100,
        property   = function(rng)
            local builder = rng.pick(SHAPES)
            local App     = builder(rng)
            local cols    = rng.int(1, 200)
            local rows    = rng.int(1, 100)
            local ok, err = pcall(function()
                local h = testing.render(App, { cols = cols, rows = rows })
                h:unmount()
            end)
            if not ok then
                error(("crash at %dx%d: %s"):format(cols, rows, tostring(err)), 0)
            end
        end,
    }
end
