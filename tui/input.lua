-- tui/input.lua — public input simulation API.
--
-- Provides press(), type(), paste(), mouse(), dispatch() for simulating
-- terminal input in the bare test harness (no vterm / no scheduler).
--
-- For the full harness (with vterm), use the methods on the harness
-- instance directly: h:press(), h:type(), h:paste(), h:mouse(),
-- h:dispatch(), h:dispatch_event(), h:type_composing(),
-- h:type_composing_confirm().

local input_mod = require "tui.internal.input"
local testing_input = require "tui.testing.input"
local testing_mouse = require "tui.testing.mouse"

local M = {}

--- Feed raw bytes through input_mod.dispatch().
function M.dispatch(bytes)
    if not bytes or #bytes == 0 then return end
    input_mod.dispatch(bytes)
end

--- Encode a mouse event spec as SGR bytes and dispatch it.
function M.mouse(ev_type, btn, x, y, mods)
    M.dispatch(testing_mouse.harness(ev_type, btn, x, y, mods))
end

--- Wrap text with bracketed-paste markers and dispatch it.
function M.paste(text)
    M.dispatch(testing_input.paste(text))
end

--- Resolve a key name to bytes and dispatch it.
-- Printable UTF-8 strings (resolve_key returns nil) are type()d instead.
function M.press(name)
    local raw = testing_input.resolve_key(name)
    if raw == nil then M.type(name); return end
    M.dispatch(raw)
end

--- Parse raw bytes into semantic key events.
function M.parse(bytes)
    return testing_input.parse(bytes)
end

--- Type a string, encoding each Unicode codepoint as UTF-8 bytes and
-- dispatching them one at a time through dispatch().
function M.type(str)
    if type(str) ~= "string" then error("type: expected string", 2) end
    local i = 1
    while i <= #str do
        local b = str:byte(i)
        local n = b < 0x80 and 1 or b < 0xC0 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        M.dispatch(str:sub(i, i + n - 1))
        i = i + n
    end
end

return M
