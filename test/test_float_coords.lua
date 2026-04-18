local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "float_coords"

function suite.test_coords_are_integers()
    local h = testing.render(function()
        return tui.Box {
            margin = 2,
            padding = 1,
            borderStyle = "single",
            width = 15,
            height = 5,
            tui.Text { "hello" }
        }
    end, { cols = 20, rows = 10 })

    local root = h:tree()
    lt.assertNotEquals(root, nil, "tree should not be nil")

    local function check_coords(elem, path)
        if elem.rect then
            local x, y = elem.rect.x, elem.rect.y
            lt.assertEquals(math.type(x), "integer", "x coord not integer at " .. path .. ": " .. tostring(x))
            lt.assertEquals(math.type(y), "integer", "y coord not integer at " .. path .. ": " .. tostring(y))
        end
        for i, child in ipairs(elem.children or {}) do
            check_coords(child, path .. ".child[" .. i .. "]")
        end
    end

    check_coords(root, "root")
end

function suite.test_flex_layout_produces_integers()
    local h = testing.render(function()
        return tui.Box {
            flexDirection = "row",
            width = 10,
            height = 5,
            tui.Box { key = "a", flexGrow = 1, tui.Text { "a" } },
            tui.Box { key = "b", flexGrow = 1, tui.Text { "b" } },
            tui.Box { key = "c", flexGrow = 1, tui.Text { "c" } },
        }
    end, { cols = 20, rows = 10 })

    local root = h:tree()
    lt.assertNotEquals(root, nil, "tree should not be nil")

    local function check_coords(elem, path)
        if elem.rect then
            local x, y, w, h_rect = elem.rect.x, elem.rect.y, elem.rect.w, elem.rect.h
            lt.assertEquals(math.type(x), "integer", "x not integer at " .. path .. ": " .. tostring(x))
            lt.assertEquals(math.type(y), "integer", "y not integer at " .. path .. ": " .. tostring(y))
            lt.assertEquals(math.type(w), "integer", "w not integer at " .. path .. ": " .. tostring(w))
            lt.assertEquals(math.type(h_rect), "integer", "h not integer at " .. path .. ": " .. tostring(h_rect))
        end
        for i, child in ipairs(elem.children or {}) do
            check_coords(child, path .. ".child[" .. i .. "]")
        end
    end

    check_coords(root, "root")
end
