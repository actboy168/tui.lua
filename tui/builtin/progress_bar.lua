-- tui/builtin/progress_bar.lua — <ProgressBar> component.
--
-- Renders a single-line horizontal fill bar. Minimal by design:
--   * Known-progress only (indeterminate state belongs to Spinner).
--   * No label / percent overlay (compose with a sibling Text).
--   * No border (wrap in a Box if you want one).
--
-- Props:
--   value  : 0..1 progress (clamped). Non-numbers are treated as 0.
--   width  : total column width of the bar. Default 20. To fill a line, pass
--            `useWindowSize().cols` or a Yoga-resolved width from a parent.
--   color  : foreground color applied to the fill run (default "cyan"). Set
--            to false/nil to render without color.
--   chars  : { fill = "█", empty = "░" }. Either side may be a single
--            display-column glyph. Defaults are U+2588 FULL BLOCK and
--            U+2591 LIGHT SHADE.

local element = require "tui.element"

local M = {}

local <const> DEFAULT_FILL  = "\u{2588}"  -- █
local <const> DEFAULT_EMPTY = "\u{2591}"  -- ░

local function clamp01(v)
    if type(v) ~= "number" or v ~= v then return 0 end  -- nil/nan/non-number
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function ProgressBarImpl(props)
    props = props or {}
    local value = clamp01(props.value)
    local width = props.width or 20
    if type(width) ~= "number" or width < 0 then width = 0 end
    width = math.floor(width)

    local chars = props.chars or {}
    local fill_ch  = chars.fill  or DEFAULT_FILL
    local empty_ch = chars.empty or DEFAULT_EMPTY

    -- Simple cell-count fill (no fractional partial blocks — keeps the C
    -- renderer's grapheme handling uncomplicated, and at width 20+ the loss
    -- is imperceptible). If sub-cell resolution becomes important, swap in
    -- the 1/8-block ladder (U+258F..U+2588) — the API already accommodates
    -- it via the `chars` prop.
    local filled = math.floor(value * width + 0.5)
    if filled > width then filled = width end
    if filled < 0 then filled = 0 end

    local bar = string.rep(fill_ch, filled) .. string.rep(empty_ch, width - filled)

    local text_props = { bar }
    if props.color then text_props.color = props.color
    elseif props.color == nil then text_props.color = "cyan" end
    return element.Text(text_props)
end

function M.ProgressBar(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = ProgressBarImpl, props = props, key = key }
end

return M
