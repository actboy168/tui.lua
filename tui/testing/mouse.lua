local tui_core = require "tui.core"

local M = {}

local function assert_int(name, value, min, max)
    assert(type(value) == "number" and value % 1 == 0,
        name .. ": expected integer, got " .. tostring(value))
    assert(value >= min, name .. ": expected >= " .. min .. ", got " .. value)
    if max then
        assert(value <= max, name .. ": expected <= " .. max .. ", got " .. value)
    end
end

local function assert_button(button)
    assert_int("button", button, 1, 3)
end

local function apply_mods(pb, spec)
    if spec.shift then pb = pb + 4 end
    if spec.meta  then pb = pb + 8 end
    if spec.ctrl  then pb = pb + 16 end
    return pb
end

local function sgr_pb(spec)
    if spec.type == "scroll" then
        assert(spec.scroll == 1 or spec.scroll == -1,
            "scroll: expected 1 or -1, got " .. tostring(spec.scroll))
        return spec.scroll == 1 and 64 or 65
    end
    if spec.type == "move" then
        if spec.button == nil then
            return 32 + 3
        end
        assert_button(spec.button)
        return 32 + (spec.button - 1)
    end
    if spec.type == "up" then
        assert_button(spec.button)
        return spec.button - 1
    end
    if spec.type == "down" then
        assert_button(spec.button)
        return spec.button - 1
    end
    error("type: expected down/up/move/scroll, got " .. tostring(spec.type))
end

local function x10_pb(spec)
    if spec.type == "scroll" then
        assert(spec.scroll == 1 or spec.scroll == -1,
            "scroll: expected 1 or -1, got " .. tostring(spec.scroll))
        return spec.scroll == 1 and 64 or 65
    end
    if spec.type == "move" then
        if spec.button == nil then
            return 32 + 3
        end
        assert_button(spec.button)
        return 32 + (spec.button - 1)
    end
    if spec.type == "up" then
        return 3
    end
    if spec.type == "down" then
        assert_button(spec.button)
        return spec.button - 1
    end
    error("type: expected down/up/move/scroll, got " .. tostring(spec.type))
end

--- Encode one semantic mouse event as an SGR sequence.
-- Spec mirrors parsed mouse events:
--   { type = "down"|"up"|"move"|"scroll", button?, scroll?, x, y,
--     shift?, meta?, ctrl? }
-- Use this for dispatch-driven tests that care about protocol-level mouse bytes.
function M.sgr(spec)
    assert(type(spec) == "table", "sgr: expected table spec")
    assert_int("x", spec.x, 1)
    assert_int("y", spec.y, 1)
    local pb = apply_mods(sgr_pb(spec), spec)
    local final = spec.type == "up" and "m" or "M"
    return string.format("\x1b[<%d;%d;%d%s", pb, spec.x, spec.y, final)
end

--- Encode one semantic mouse event as a legacy X10 sequence.
-- X10 release events do not preserve button identity after parsing.
function M.x10(spec)
    assert(type(spec) == "table", "x10: expected table spec")
    assert_int("x", spec.x, 1, 223)
    assert_int("y", spec.y, 1, 223)
    local pb = apply_mods(x10_pb(spec), spec)
    return "\x1b[M"
        .. string.char(pb + 32)
        .. string.char(spec.x + 32)
        .. string.char(spec.y + 32)
end

--- Backward-compatible encoder for Harness:mouse(ev_type, btn, x, y, mods).
-- Use this when a test wants exact parity with the harness convenience API.
function M.harness(ev_type, btn, x, y, mods)
    mods = mods or {}
    local spec = {
        x = x,
        y = y,
        shift = mods.shift,
        meta = mods.meta,
        ctrl = mods.ctrl,
    }
    if ev_type == "scroll_up" then
        spec.type = "scroll"
        spec.scroll = 1
    elseif ev_type == "scroll_down" then
        spec.type = "scroll"
        spec.scroll = -1
    elseif ev_type == "move" then
        spec.type = "move"
        spec.button = btn or 1
    elseif ev_type == "down" or ev_type == "up" then
        spec.type = ev_type
        spec.button = btn or 1
    else
        error("mouse: expected down/up/move/scroll_up/scroll_down, got " .. tostring(ev_type), 2)
    end
    return M.sgr(spec)
end

--- Parse raw mouse bytes into semantic key events.
function M.parse(bytes)
    return tui_core.keys.parse(bytes)
end

--- Encode an SGR mouse spec, then parse it immediately.
function M.parse_sgr(spec)
    return M.parse(M.sgr(spec))
end

--- Encode an X10 mouse spec, then parse it immediately.
function M.parse_x10(spec)
    return M.parse(M.x10(spec))
end

return M
