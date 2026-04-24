-- test/property/test_layout_invariant.lua — child rect does not overflow parent.
--
-- Property: after layout, every child's border-box rect is contained within
-- its parent's border-box rect.  Tests a variety of tree shapes with
-- randomized prop values (padding, flexGrow, flexDirection, borderStyle).

local lt      = require "ltest"
local tui     = require "tui"
local testing = require "tui.testing"
local pbt     = require "test.property.pbt"

local suite = lt.test "layout_invariant"

-- ---------------------------------------------------------------------------
-- Invariant check: walk the tree and assert no child overflows its parent.

local function assert_no_overflow(parent)
    local pr = parent.rect
    if not pr then return end
    for _, child in ipairs(parent.children or {}) do
        local cr = child.rect
        if cr then
            if cr.x < pr.x then
                error(("child x(%d) < parent x(%d)"):format(cr.x, pr.x), 0)
            end
            if cr.y < pr.y then
                error(("child y(%d) < parent y(%d)"):format(cr.y, pr.y), 0)
            end
            if cr.x + cr.w > pr.x + pr.w then
                error(("child right(%d) > parent right(%d)"):format(
                    cr.x + cr.w, pr.x + pr.w), 0)
            end
            if cr.y + cr.h > pr.y + pr.h then
                error(("child bottom(%d) > parent bottom(%d)"):format(
                    cr.y + cr.h, pr.y + pr.h), 0)
            end
            assert_no_overflow(child)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tree shape builders.
-- Each builder(rng) returns an App function component.

local SHAPES = {}

-- Shape 1: nested boxes with random padding per level
table.insert(SHAPES, {
    name = "nested_boxes",
    builder = function(rng)
        local depth = rng.int(2, 8)
        local pads  = {}
        for i = 1, depth do
            pads[i] = rng.int(0, 3)
        end
        return function()
            local function nest(d)
                if d == 0 then
                    return tui.Text { "x" }
                end
                return tui.Box { paddingLeft = pads[d], nest(d - 1) }
            end
            return tui.Box { nest(depth) }
        end
    end,
})

-- Shape 2: flex row with random flexGrow children
table.insert(SHAPES, {
    name = "flex_row",
    builder = function(rng)
        local n = rng.int(2, 5)
        local grows = {}
        for i = 1, n do
            grows[i] = rng.int(0, 3)
        end
        return function()
            local children = {}
            for i = 1, n do
                children[i] = tui.Box {
                    key = i,
                    flexGrow = grows[i],
                    tui.Text { tostring(i) },
                }
            end
            return tui.Box {
                flexDirection = "row",
                children,
            }
        end
    end,
})

-- Shape 3: flex column with random flexGrow children
table.insert(SHAPES, {
    name = "flex_column",
    builder = function(rng)
        local n = rng.int(2, 5)
        local grows = {}
        for i = 1, n do
            grows[i] = rng.int(0, 3)
        end
        return function()
            local children = {}
            for i = 1, n do
                children[i] = tui.Box {
                    key = i,
                    flexGrow = grows[i],
                    tui.Text { tostring(i) },
                }
            end
            return tui.Box {
                flexDirection = "column",
                children,
            }
        end
    end,
})

-- Shape 4: box with border + padding and a nested child
table.insert(SHAPES, {
    name = "padded_border",
    builder = function(rng)
        local border = rng.pick({ nil, "single", "round" })
        local padX   = rng.int(0, 3)
        local padY   = rng.int(0, 3)
        return function()
            local props = {
                tui.Text { "inner" },
            }
            if border then props.borderStyle = border end
            if padX > 0 then props.paddingX = padX end
            if padY > 0 then props.paddingY = padY end
            return tui.Box(props)
        end
    end,
})

-- Shape 5: 3-level tree mixing row/column directions
table.insert(SHAPES, {
    name = "mixed_deep",
    builder = function(rng)
        local dirs = {}
        local pads = {}
        for i = 1, 3 do
            dirs[i] = rng.pick({ "row", "column" })
            pads[i] = rng.int(0, 2)
        end
        return function()
            local inner = tui.Box {
                paddingLeft = pads[3],
                tui.Text { "leaf" },
            }
            local mid = tui.Box {
                key = "mid",
                flexDirection = dirs[2],
                paddingLeft = pads[2],
                inner,
            }
            return tui.Box {
                flexDirection = dirs[1],
                paddingLeft = pads[1],
                mid,
            }
        end
    end,
})

-- ---------------------------------------------------------------------------
-- Test

function suite:test_child_does_not_overflow_parent()
    pbt.check {
        name       = "child does not overflow parent (border-box)",
        iterations = 100,
        property   = function(rng)
            local shape = rng.pick(SHAPES)
            local App   = shape.builder(rng)
            local cols  = rng.int(10, 120)
            local rows  = rng.int(5, 50)
            local h = testing.harness(App, { cols = cols, rows = rows })
            local ok, err = pcall(assert_no_overflow, h:tree())
            h:unmount()
            if not ok then error(err, 0) end
        end,
    }
end
