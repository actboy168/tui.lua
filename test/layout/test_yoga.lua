-- test/test_yoga.lua — Yoga layout binding tests

local lt   = require "ltest"
local yoga = require "tui.core".yoga

local suite = lt.test "yoga"

-- ============================================================================
-- Integer enforcement
-- ============================================================================

function suite.test_integer_accepted()
    local root = yoga.node_new()
    yoga.node_set(root, { width = 10, height = 5 })
    yoga.node_calc(root)
    local x, y, w, h = yoga.node_get(root)
    lt.assertEquals(w, 10)
    lt.assertEquals(h, 5)
    yoga.node_free(root)
end

function suite.test_float_rejected()
    local root = yoga.node_new()
    local ok, err = pcall(function()
        yoga.node_set(root, { width = 10.5 })
    end)
    lt.assertEquals(ok, false, "should reject float")
    lt.assertEquals(err:match("integer") ~= nil, true, "error should mention integer: " .. tostring(err))
    yoga.node_free(root)
end

function suite.test_margin_float_rejected()
    local root = yoga.node_new()
    local ok, err = pcall(function()
        yoga.node_set(root, { margin = 2.5 })
    end)
    lt.assertEquals(ok, false, "should reject float margin")
    yoga.node_free(root)
end

function suite.test_padding_float_rejected()
    local root = yoga.node_new()
    local ok, err = pcall(function()
        yoga.node_set(root, { padding = 1.9 })
    end)
    lt.assertEquals(ok, false, "should reject float padding")
    yoga.node_free(root)
end

function suite.test_percentage_rejected()
    local root = yoga.node_new()
    local ok, err = pcall(function()
        yoga.node_set(root, { width = "10%" })
    end)
    lt.assertEquals(ok, false, "should reject percentage")
    yoga.node_free(root)
end

-- ============================================================================
-- Float exceptions (flexGrow, flexShrink)
-- ============================================================================

function suite.test_flexGrow_accepts_float()
    local root = yoga.node_new()
    local child = yoga.node_new(root)

    yoga.node_set(root, { width = 10, height = 5 })
    yoga.node_set(child, { flexGrow = 0.5 })

    yoga.node_calc(root)

    local _, _, w, h = yoga.node_get(child)
    lt.assertEquals(w, 10)  -- child should fill parent's width
    yoga.node_free(root)
end

function suite.test_flexShrink_accepts_float()
    local root = yoga.node_new()
    local child = yoga.node_new(root)

    yoga.node_set(root, { width = 10, height = 5 })
    yoga.node_set(child, { width = 20, flexShrink = 0.5 })

    yoga.node_calc(root)

    local _, _, w, h = yoga.node_get(child)
    lt.assertEquals(w <= 20, true, "child should have shrunk")
    yoga.node_free(root)
end

-- ============================================================================
-- Coordinate output
-- ============================================================================

function suite.test_nested_integer_coords()
    local root = yoga.node_new()
    local child = yoga.node_new(root)

    yoga.node_set(root, { width = 20, height = 10 })
    yoga.node_set(child, { margin = 2, padding = 1, width = 10, height = 5 })

    yoga.node_calc(root)

    local x1, y1 = yoga.node_get(root)
    local x2, y2 = yoga.node_get(child)

    lt.assertEquals(math.type(x1), "integer", "root x should be integer")
    lt.assertEquals(math.type(y1), "integer", "root y should be integer")
    lt.assertEquals(math.type(x2), "integer", "child x should be integer")
    lt.assertEquals(math.type(y2), "integer", "child y should be integer")

    yoga.node_free(root)
end
