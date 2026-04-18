-- tui/builtin/select.lua — <Select> component.
--
-- Ink-style SelectInput: an arrow-key navigated list with an indicator
-- glyph on the highlighted row. Non-controlled highlight (internal state);
-- parent only sees changes via onChange / onSelect callbacks.
--
-- Props:
--   items          : array. Each element is either
--                      * a string          -> {label=s, value=s}
--                      * a table           -> must have .label, optional .value
--                    An empty list renders an empty Box (no error).
--   onSelect       : fn(item, index) — called on Enter with the item object
--                    (normalized to {label, value}) and its 1-based index.
--   onChange       : fn(item, index) — optional; called whenever the
--                    highlight moves (arrow keys, Home/End). NOT called on
--                    mount for the initial highlight.
--   initialIndex   : 1-based starting highlight. Clamped to items. Default 1.
--   indicator      : string prefix on the highlighted row (default "❯ ").
--   highlightColor : color name applied to the highlighted row's Text
--                    (default "cyan"). Non-highlighted rows render without
--                    color. Set to false / nil for no color at all.
--   renderItem     : fn(item, { isSelected, index }) -> element. When
--                    provided, replaces the default glyph+label rendering
--                    for that row. The `indicator` and `highlightColor`
--                    props are ignored in this case — the callback owns
--                    all visual decisions.
--   limit          : max visible rows. When set and #items > limit, a
--                    scrolling window tracks the highlight; a ">" or "<"
--                    marker has been left out to keep the shape minimal
--                    (add later if needed). Default: show all.
--   focusId        : forwarded to useFocus.
--   autoFocus      : forwarded to useFocus (default true).
--   isDisabled     : maps to useFocus isActive=false (entry stays in the
--                    chain but Tab skips it and keys are ignored).
--
-- Lifecycle: Select itself is stateful while mounted. For a loading pattern
-- (items empty then filled), re-rendering with new items is fine — the
-- highlight is clamped to the new list's bounds by a defensive useEffect.

local element = require "tui.element"
local hooks   = require "tui.hooks"
local text    = require "tui.text"

local M = {}

-- Normalize heterogeneous items into a flat list of {label, value, raw}.
-- `raw` preserves the original input so renderItem/callbacks receive it
-- unmodified (users often pass opaque objects with more fields).
local function normalize_items(items)
    local out = {}
    for i = 1, #items do
        local v = items[i]
        if type(v) == "string" then
            out[i] = { label = v, value = v, raw = v }
        elseif type(v) == "table" then
            local label = v.label
            if label == nil then
                error(("Select: items[%d] is a table but has no `label` field"):format(i), 3)
            end
            out[i] = { label = tostring(label), value = v.value, raw = v }
        else
            error(("Select: items[%d] must be a string or a {label, value} table, got %s")
                :format(i, type(v)), 3)
        end
    end
    return out
end

-- Compute the visible window [first..last] such that `highlight` is inside,
-- given `limit` rows of space. Returns (first, last).
local function window_bounds(n, highlight, limit)
    if not limit or limit >= n then return 1, n end
    -- Try to keep highlight centered-ish. Simpler: shift window so
    -- highlight sits at least one away from the edges when possible.
    local first = highlight - math.floor(limit / 2)
    if first < 1 then first = 1 end
    local last = first + limit - 1
    if last > n then
        last = n
        first = math.max(1, last - limit + 1)
    end
    return first, last
end

local function default_render(item, ctx, props)
    local indicator = props.indicator or "❯ "
    -- Pad non-selected rows by the indicator's *display width*, not its
    -- byte length — the indicator may contain multi-byte glyphs like "❯"
    -- which encode as 3 bytes but occupy 1 column.
    local pad = string.rep(" ", text.display_width(indicator))
    local prefix = ctx.isSelected and indicator or pad
    local text_props = { prefix .. item.label }
    if ctx.isSelected and props.highlightColor then
        text_props.color = props.highlightColor
    end
    return element.Text(text_props)
end

local function SelectImpl(props)
    props = props or {}
    local items_raw = props.items or {}
    local items     = normalize_items(items_raw)
    local n         = #items

    local initial_idx = props.initialIndex or 1
    if initial_idx < 1 then initial_idx = 1 end
    if n > 0 and initial_idx > n then initial_idx = n end

    local highlight, setHighlight = hooks.useState(initial_idx)

    -- Keep latest callbacks and item array in a ref so the keyboard handler
    -- always sees fresh references without re-subscribing to useFocus.
    local ctx = hooks.useRef {}
    ctx.current.items     = items
    ctx.current.highlight = highlight
    ctx.current.onSelect  = props.onSelect
    ctx.current.onChange  = props.onChange
    ctx.current.setH      = setHighlight

    -- Clamp highlight if items shrank underneath us.
    hooks.useEffect(function()
        if n == 0 then
            if highlight ~= 1 then setHighlight(1) end
        elseif highlight > n then
            setHighlight(n)
        end
    end, { n })

    local disabled = props.isDisabled and true or false

    hooks.useFocus {
        autoFocus = (not disabled) and (props.autoFocus ~= false),
        id        = props.focusId,
        isActive  = not disabled,
        on_input  = function(_input, key)
            local st = ctx.current
            local cur = st.highlight
            local len = #st.items
            if len == 0 then return end

            local name = key and key.name
            local next_idx = cur
            if name == "up" then
                next_idx = cur > 1 and cur - 1 or len  -- wrap to bottom
            elseif name == "down" then
                next_idx = cur < len and cur + 1 or 1  -- wrap to top
            elseif name == "home" then
                next_idx = 1
            elseif name == "end" then
                next_idx = len
            elseif name == "enter" then
                if st.onSelect then st.onSelect(st.items[cur], cur) end
                return
            else
                return
            end

            if next_idx ~= cur then
                st.setH(next_idx)
                st.highlight = next_idx  -- eager update for intra-dispatch
                if st.onChange then
                    st.onChange(st.items[next_idx], next_idx)
                end
            end
        end,
    }

    if n == 0 then
        return element.Box { flexDirection = "column" }
    end

    local first, last = window_bounds(n, highlight, props.limit)

    local children = {}
    local renderItem = props.renderItem
    -- Default `highlightColor`: prefer explicit value (even if false/nil user
    -- set), otherwise "cyan". Using rawget semantics via `props.highlightColor`
    -- is fine because undefined keys simply fall through.
    local effective = {
        indicator      = props.indicator,
        highlightColor = props.highlightColor ~= nil and props.highlightColor or "cyan",
    }

    for i = first, last do
        local item = items[i]
        local is_sel = (i == highlight)
        local el
        if renderItem then
            el = renderItem(item.raw, { isSelected = is_sel, index = i })
            if type(el) == "string" then el = element.Text { el } end
        else
            el = default_render(item, { isSelected = is_sel, index = i }, effective)
        end
        -- Key each row by its source index so reorderings preserve state
        -- (though Select rows are stateless Text elements today; cheap
        -- insurance for future per-row interactive content).
        if type(el) == "table" and el.key == nil then
            local copy = {}
            for k, v in pairs(el) do copy[k] = v end
            copy.key = "select:" .. tostring(i)
            el = copy
        end
        children[#children + 1] = el
    end

    local box = { flexDirection = "column", flexShrink = 0 }
    for _, c in ipairs(children) do box[#box + 1] = c end
    return element.Box(box)
end

function M.Select(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = SelectImpl, props = props, key = key }
end

return M
