local tui = require "tui"
local split_props_children = require("tui.internal.element")._split_props_children
local clickable = require "tui.hook.clickable"
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
end

local function assert_single_line(text, where)
    if text:find("\n", 1, true) or text:find("\r", 1, true) then
        error(("Link: %s must be single-line"):format(where), 3)
    end
end

local function collect_plain_text(props)
    local label = props.label
    local children = props.children or {}
    if label ~= nil and #children > 0 then
        error("Link: use either `label` or children, not both", 3)
    end

    if label ~= nil then
        local text = tostring(label)
        assert_no_control(text, "label")
        assert_single_line(text, "label")
        return text
    end

    if #children == 0 then
        return nil
    end

    local parts = {}
    for i, child in ipairs(children) do
        if type(child) == "table" then
            return nil
        end
        local text = tostring(child)
        assert_no_control(text, ("children[%d]"):format(i))
        assert_single_line(text, ("children[%d]"):format(i))
        parts[#parts + 1] = text
    end
    return table.concat(parts)
end

local function normalize_rich_children(children)
    local normalized = {}
    for i, child in ipairs(children or {}) do
        if type(child) == "table" then
            normalized[#normalized + 1] = child
        else
            local text = tostring(child)
            assert_no_control(text, ("children[%d]"):format(i))
            normalized[#normalized + 1] = tui.Text { text }
        end
    end
    if #normalized == 0 then
        return nil
    end
    if #normalized == 1 then
        return normalized[1]
    end
    local row = {
        flexDirection = "row",
    }
    for _, child in ipairs(normalized) do
        row[#row + 1] = child
    end
    return tui.Box(row)
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

local function LinkImpl(props)
    props = props or {}
    local href = props.href
    if type(href) ~= "string" or href == "" then
        error("Link: `href` must be a non-empty string", 3)
    end
    assert_no_control(href, "href")
    assert_single_line(href, "href")

    local plain_text = collect_plain_text(props)
    local rich_child = nil
    if plain_text == nil then
        rich_child = normalize_rich_children(props.children or {})
        if rich_child == nil then
            return nil
        end
    elseif plain_text == "" then
        return nil
    end

    local disabled = props.isDisabled and true or false
    local click = clickable.useClickable {
        disabled = disabled,
        onClick = props.onClick,
        autoFocus = props.autoFocus,
        focusId = props.focusId,
        id = props.id,
        payload = { href = href },
    }

    local box_props = {
        onMouseDown = click.onMouseDown,
    }
    for k, v in pairs(props) do
        if not LINK_PROPS[k] and not TEXT_STYLE_KEYS[k] then
            box_props[k] = v
        end
    end

    if plain_text ~= nil then
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
            line = prefix .. plain_text .. (prefix ~= "" and "\27[0m" or "")
        else
            line = prefix .. osc8_open(href) .. plain_text .. osc8_close() .. (prefix ~= "" and "\27[0m" or "")
        end

        box_props.width = box_props.width or tui.displayWidth(plain_text)
        box_props.height = box_props.height or 1
        box_props[1] = tui.RawAnsi {
            lines = { line },
            width = tui.displayWidth(plain_text),
        }
        return tui.Box(box_props)
    end

    if props.color ~= nil then
        box_props.color = props.color
    end
    if props.backgroundColor ~= nil then
        box_props.backgroundColor = props.backgroundColor
    end

    if disabled then
        box_props[1] = rich_child
    else
        box_props[1] = tui.Transform {
            transform = function(region)
                region:setHyperlink(href)
            end,
            rich_child,
        }
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
