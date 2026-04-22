-- tui/input.lua — public input simulation API.
--
-- Provides press(), type(), paste(), mouse(), dispatch() for simulating
-- terminal input. Works with both the test harness and production scripts.
--
-- Usage in tests:
--   local h = harness.render(...)
--   h.input.press("enter")
--   h.input.type("hello")
--   h.input.paste("clipboard text")
--
-- Usage in production scripts:
--   local app = tui.app(root, opts)
--   tui.input.ingest(function(bytes) app:feed_input(bytes) end)
--   tui.input.press("enter")
--   app:run()

local input_mod = require "tui.internal.input"
local testing_input = require "tui.testing.input"
local testing_mouse = require "tui.testing.mouse"

local M = {}

--- Set the enqueue function for dispatch().
-- When set, dispatch() calls enqueue_fn(bytes) instead of input_mod.dispatch().
-- The harness uses this to redirect simulated input into the vterm queue.
-- Production scripts use this to feed input into the app's scheduler.
function M.ingest(enqueue_fn)
    input_mod._set_ingest(enqueue_fn)
end

--- Dispatch a raw event table directly through input_mod._dispatch_event().
-- Used for IME composing simulation.
function M.dispatch_event(ev)
    input_mod._dispatch_event(ev)
end

--- Send a composing event (IME composition start/update).
function M.type_composing(text)
    input_mod._dispatch_event {
        name = "composing", input = text or "", raw = text or "",
        ctrl = false, meta = false, shift = false,
    }
end

--- Confirm a composing event (IME composition commit).
function M.type_composing_confirm(text)
    local fake = text or ""
    input_mod._dispatch_event {
        name = "composing_confirm", input = fake, raw = fake,
        ctrl = false, meta = false, shift = false,
    }
end

--- Feed raw bytes through the ingest redirect or input_mod.dispatch().
function M.dispatch(bytes)
    if not bytes or #bytes == 0 then return end
    input_mod._dispatch_bytes(bytes)
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
