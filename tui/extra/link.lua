local tui = require "tui"
local split_props_children = require("tui.internal.element")._split_props_children
local sgr = require "tui.internal.sgr"

local M = {}

local TEXT_STYLE_KEYS = {
    color = true,
    backgroundColor = true,
    bold = true,
    italic = true,
    underline = true,
    strikethrough = true,
    inverse = true,
    dim = true,
    dimColor = true,
}

local LINK_PROPS = {
    href = true,
    onClick = true,
    autoFocus = true,
    focusId = true,
    id = true,
    isDisabled = true,
    label = true,
    children = true,
}

local function assert_no_control(text, where)
    if text:find("\27", 1, true) then
        error(("Link: %s must not contain ESC bytes"):format(where), 3)
    end
    if text:find("\7", 1, true) then
        error(("Link: %s must not contain BEL bytes"):format(where), 3)
    end
    if text:find("\n", 1, true) or text:find("\r", 1, true) then
        error(("Link: %s must be single-line"):format(where), 3)
    end
end

local function collect_text(props)
    local label = props.label
    local children = props.children or {}
    if label ~= nil and #children > 0 then
        error("Link: use either `label` or children, not both", 3)
    end

    local text
    if label ~= nil then
        text = tostring(label)
    else
        local parts = {}
        for i, child in ipairs(children) do
            if type(child) == "table" then
                error(("Link: children[%d] must be plain text, got table"):format(i), 3)
            end
            parts[#parts + 1] = tostring(child)
        end
        text = table.concat(parts)
    end

    assert_no_control(text, "label")
    return text
end

local function append_color_params(params, spec, is_bg, which)
    if spec == nil then return end
    local base = is_bg and 40 or 30
    local hi_base = is_bg and 100 or 90
    if type(spec) == "number" then
        if spec ~= math.floor(spec) or spec < 0 or spec > 255 then
            error(("Link: %s must be integer 0..255, got %s"):format(which, tostring(spec)), 3)
        end
        if spec <= 7 then
            params[#params + 1] = tostring(base + spec)
        elseif spec <= 15 then
            params[#params + 1] = tostring(hi_base + spec - 8)
        else
            params[#params + 1] = is_bg and "48" or "38"
            params[#params + 1] = "5"
            params[#params + 1] = tostring(spec)
        end
        return
    end

    if type(spec) ~= "string" then
        error(("Link: %s must be string or integer, got %s"):format(which, type(spec)), 3)
    end

    local r, g, b = spec:match("^#(%x%x)(%x%x)(%x%x)$")
    if r then
        params[#params + 1] = is_bg and "48" or "38"
        params[#params + 1] = "2"
        params[#params + 1] = tostring(tonumber(r, 16))
        params[#params + 1] = tostring(tonumber(g, 16))
        params[#params + 1] = tostring(tonumber(b, 16))
        return
    end

    local idx = sgr.COLORS[spec]
    if idx == nil then
        error(("Link: unknown color name for %s: %q"):format(which, spec), 3)
    end
    if idx <= 7 then
        params[#params + 1] = tostring(base + idx)
    else
        params[#params + 1] = tostring(hi_base + idx - 8)
    end
end

local function build_sgr_prefix(props)
    local params = {}
    local fg = props.dimColor or props.color
    local bg = props.backgroundColor

    if props.bold then params[#params + 1] = "1" end
    if props.dim or props.dimColor ~= nil then params[#params + 1] = "2" end
    if props.italic then params[#params + 1] = "3" end
    if props.underline then params[#params + 1] = "4" end
    if props.inverse then params[#params + 1] = "7" end
    if props.strikethrough then params[#params + 1] = "9" end

    append_color_params(params, fg, false, "color")
    append_color_params(params, bg, true, "backgroundColor")

    if #params == 0 then return "" end
    return "\27[" .. table.concat(params, ";") .. "m"
end

local function osc8_open(href)
    return "\27]8;;" .. href .. "\27\\"
end

local function osc8_close()
    return "\27]8;;\27\\"
end

local function merge_click_event(base, href, source)
    local out = {
        href = href,
        source = source,
    }
    if base then
        for k, v in pairs(base) do
            out[k] = v
        end
        out.href = href
        out.source = source
    end
    return out
end

local function LinkImpl(props)
    props = props or {}
    local href = props.href
    if type(href) ~= "string" or href == "" then
        error("Link: `href` must be a non-empty string", 3)
    end
    assert_no_control(href, "href")

    local text = collect_text(props)
    if text == "" then
        return nil
    end

    local disabled = props.isDisabled and true or false
    local text_props = {
        color = props.color,
        backgroundColor = props.backgroundColor,
        bold = props.bold,
        italic = props.italic,
        underline = props.underline,
        strikethrough = props.strikethrough,
        inverse = props.inverse,
        dim = props.dim,
        dimColor = props.dimColor,
    }
    if text_props.color == nil and text_props.dimColor == nil then
        text_props.color = "blue"
    end
    if text_props.underline == nil then
        text_props.underline = true
    end

    local prefix = build_sgr_prefix(text_props)
    local line
    if disabled then
        line = prefix .. text .. (prefix ~= "" and "\27[0m" or "")
    else
        line = prefix .. osc8_open(href) .. text .. osc8_close() .. (prefix ~= "" and "\27[0m" or "")
    end

    local ctx = tui.useRef {}
    ctx.current.href = href
    ctx.current.onClick = props.onClick
    ctx.current.disabled = disabled

    local keyboard_active = (not disabled) and (props.onClick ~= nil)
    local focus = tui.useFocus {
        autoFocus = keyboard_active and (props.autoFocus == true),
        id = props.focusId or props.id,
        isActive = keyboard_active,
        on_input = function(_input, key)
            if key and key.name == "enter" and ctx.current.onClick and not ctx.current.disabled then
                ctx.current.onClick(merge_click_event(nil, ctx.current.href, "keyboard"))
            end
        end,
    }

    local on_mouse_down
    if not disabled and props.onClick ~= nil then
        on_mouse_down = function(ev)
            focus.focus()
            ctx.current.onClick(merge_click_event(ev, ctx.current.href, "mouse"))
        end
    end

    local box_props = {
        width = props.width or tui.displayWidth(text),
        height = props.height or 1,
        onMouseDown = on_mouse_down,
        tui.RawAnsi {
            lines = { line },
            width = tui.displayWidth(text),
        },
    }

    for k, v in pairs(props) do
        if not LINK_PROPS[k] and not TEXT_STYLE_KEYS[k] then
            box_props[k] = v
        end
    end

    return tui.Box(box_props)
end

function M.Link(t)
    t = t or {}
    local props, children = split_props_children(t)
    local key = props.key
    props.key = nil
    props.children = children
    return { kind = "component", fn = LinkImpl, props = props, key = key }
end

return M
