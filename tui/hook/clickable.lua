local useRef   = require("tui.hook.state").useRef
local useFocus = require("tui.hook.focus").useFocus

local M = {}

local function merge_click_event(base, payload, source)
    local out = {
        source = source,
    }
    if payload then
        for k, v in pairs(payload) do
            out[k] = v
        end
    end
    if base then
        for k, v in pairs(base) do
            out[k] = v
        end
        out.source = source
        if payload then
            for k, v in pairs(payload) do
                out[k] = v
            end
        end
    end
    return out
end

function M.useClickable(opts)
    opts = opts or {}

    local ctx = useRef {}
    ctx.current.onClick = opts.onClick
    ctx.current.disabled = opts.disabled and true or false
    ctx.current.payload = opts.payload or nil

    local active = (not ctx.current.disabled) and (ctx.current.onClick ~= nil)
    local focus = useFocus {
        autoFocus = active and (opts.autoFocus == true),
        id = opts.focusId or opts.id,
        isActive = active,
        on_input = function(_input, key)
            if key and key.name == "enter" and ctx.current.onClick and not ctx.current.disabled then
                ctx.current.onClick(merge_click_event(nil, ctx.current.payload, "keyboard"))
            end
        end,
    }

    local function fire(source, ev)
        if not ctx.current.onClick or ctx.current.disabled then
            return false
        end
        ctx.current.onClick(merge_click_event(ev, ctx.current.payload, source))
        return true
    end

    local onMouseDown
    if active then
        onMouseDown = function(ev)
            focus.focus()
            fire("mouse", ev)
        end
    end

    return {
        isFocused = focus.isFocused,
        focus = focus.focus,
        isClickable = active,
        onMouseDown = onMouseDown,
        fire = fire,
    }
end

return M
