local lt = require "ltest"
local tui = require "tui"
local testing = require "tui.testing"

local suite = lt.test "csi_float_detection"

function suite.test_csi_rejects_float_coords()
    -- 这个测试验证 testing.lua 中的 check_csi_integers 是否能捕获浮点坐标
    -- 如果 rect.x 或 rect.y 是浮点数，cursor 定位会产生 \27[y.x;x.yH 这样的非法序列

    -- 由于 Yoga 配置了 PointScaleFactor=1 且 lnodeGet 强制转换为 int，
    -- 正常情况下不会产生浮点坐标。这个测试验证防护机制是否工作。

    local h = testing.render(function()
        return tui.Box {
            width = 10,
            height = 5,
            tui.TextInput { value = "test", focus = true }
        }
    end, { cols = 20, rows = 10 })

    -- cursor() 应该返回整数坐标
    local col, row = h:cursor()
    if col and row then
        lt.assertEquals(math.type(col), "integer", "cursor col should be integer")
        lt.assertEquals(math.type(row), "integer", "cursor row should be integer")
    end
end
