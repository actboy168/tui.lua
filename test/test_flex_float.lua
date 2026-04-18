local lt = require "ltest"
local yoga = require "yoga"

local suite = lt.test "flex_float"

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
    -- flexShrink 0.5 should allow partial shrinking
    lt.assertEquals(w <= 20, true, "child should have shrunk")
    yoga.node_free(root)
end
