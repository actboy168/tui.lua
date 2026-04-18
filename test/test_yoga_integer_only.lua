local lt = require "ltest"
local yoga = require "yoga"

local suite = lt.test "yoga_integer_only"

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
