local tui = require "tui"
local split_props_children = require("tui.internal.element")._split_props_children
local clickable = require "tui.hook.clickable"

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

local BUTTON_PROPS = {
    label = true,
    onClick = true,
    autoFocus = true,
    focusId = true,
    id = true,
    isDisabled = true,
    children = true,
}

local function assert_no_control(text, where)
    if text:find("\27", 1, true) then
        error(("Button: %s must not contain ESC bytes"):format(where), 3)
    end
    if text:find("\7", 1, true) then
        error(("Button: %s must not contain BEL bytes"):format(where), 3)
    end
end

local function assert_single_line(text, where)
    if text:find("\n", 1, true) or text:find("\r", 1, true) then
        error(("Button: %s must be single-line"):format(where), 3)
    end
end

local function build_label_text(props)
    local label = props.label
    local children = props.children or {}
    if label ~= nil and #children > 0 then
        error("Button: use either `label` or children, not both", 3)
    end
    if label == nil then
        return nil
    end
    local text = tostring(label)
    assert_no_control(text, "label")
    assert_single_line(text, "label")
    return text
end

local function normalize_children(children)
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
        justifyContent = "center",
    }
    for _, child in ipairs(normalized) do
        row[#row + 1] = child
    end
    return tui.Box(row)
end

local function ButtonImpl(props)
    props = props or {}

    local label = build_label_text(props)
    local content
    if label ~= nil then
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
            label,
        }
        if text_props.bold == nil then
            text_props.bold = true
        end
        if props.isDisabled and text_props.dim == nil and text_props.dimColor == nil then
            text_props.dim = true
        end
        content = tui.Text(text_props)
    else
        content = normalize_children(props.children or {})
        if content == nil then
            return nil
        end
    end

    local disabled = props.isDisabled and true or false
    local click = clickable.useClickable {
        disabled = disabled,
        onClick = props.onClick,
        autoFocus = props.autoFocus,
        focusId = props.focusId,
        id = props.id,
    }

    local box_props = {
        flexDirection = "row",
        justifyContent = "center",
        borderStyle = props.borderStyle or "round",
        borderColor = props.borderColor or (disabled and "gray" or (click.isFocused and "cyan" or "white")),
        paddingX = props.paddingX ~= nil and props.paddingX or 1,
        paddingY = props.paddingY ~= nil and props.paddingY or 0,
        onMouseDown = click.onMouseDown,
        content,
    }

    if label == nil then
        if props.color ~= nil then
            box_props.color = props.color
        end
        if props.backgroundColor ~= nil then
            box_props.backgroundColor = props.backgroundColor
        end
    end

    for k, v in pairs(props) do
        if not BUTTON_PROPS[k] and not TEXT_STYLE_KEYS[k] then
            box_props[k] = v
        end
    end

    return tui.Box(box_props)
end

function M.Button(t)
    t = t or {}
    local props, children = split_props_children(t)
    local key = props.key
    props.key = nil
    props.children = children
    return { kind = "component", fn = ButtonImpl, props = props, key = key }
end

return M
