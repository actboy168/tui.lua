local lt = require "ltest"
local yoga = require "yoga"

local suite = lt.test "yoga_float_input"

function suite.test_integer_input_accepted()
    -- 整数输入应该正常工作
    local root = yoga.node_new()

    yoga.node_set(root, { width = 10, height = 5 })
    yoga.node_calc(root)

    local x, y, w, h = yoga.node_get(root)
    lt.assertEquals(w, 10)
    lt.assertEquals(h, 5)
    yoga.node_free(root)
end

function suite.test_float_input_rejected()
    -- 浮点数输入应该报错
    local root = yoga.node_new()
    local ok, err = pcall(function()
        yoga.node_set(root, { width = 10.5, height = 5.3 })
    end)
    lt.assertEquals(ok, false, "should reject float input")
    lt.assertEquals(err:match("integer") ~= nil, true,
        "error should mention integer: " .. tostring(err))
    yoga.node_free(root)
end

function suite.test_nested_integer_coords()
    -- 嵌套节点的整数坐标
    local root = yoga.node_new()
    local child = yoga.node_new(root)

    yoga.node_set(root, { width = 20, height = 10 })
    yoga.node_set(child, { margin = 2, padding = 1, width = 10, height = 5 })

    yoga.node_calc(root)

    local x1, y1, w1, h1 = yoga.node_get(root)
    local x2, y2, w2, h2 = yoga.node_get(child)

    -- 检查所有输出是否为整数
    lt.assertEquals(math.type(x1), "integer", "root x should be integer")
    lt.assertEquals(math.type(y1), "integer", "root y should be integer")
    lt.assertEquals(math.type(x2), "integer", "child x should be integer")
    lt.assertEquals(math.type(y2), "integer", "child y should be integer")

    yoga.node_free(root)
end
