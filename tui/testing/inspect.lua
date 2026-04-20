local input_mod   = require "tui.internal.input"
local focus_mod   = require "tui.internal.focus"
local scheduler   = require "tui.internal.scheduler"
local reconciler  = require "tui.internal.reconciler"

local M = {}

function M.install(testing, Harness)
    function testing.timer_count()
        local n = 0
        for _ in pairs(scheduler._timers()) do n = n + 1 end
        return n
    end

    function testing.input_handler_count()
        return #input_mod._handlers()
    end

    function testing.fatal(msg)
        reconciler.fatal(msg)
    end

    function testing.focus_entries()
        return focus_mod._entries()
    end

    function Harness:dispatch_event(event)
        input_mod._dispatch_event(event)
        self:_paint()
        return self
    end

    function testing.find_text_with_cursor(tree)
        local function walk(e)
            if not e then return nil end
            if e.kind == "text" and e._cursor_offset ~= nil then return e end
            for _, c in ipairs(e.children or {}) do
                local r = walk(c)
                if r then return r end
            end
        end
        return walk(tree)
    end

    function testing.find_by_kind(tree, kind)
        local function walk(e)
            if not e then return nil end
            if e.kind == kind then return e end
            for _, c in ipairs(e.children or {}) do
                local r = walk(c)
                if r then return r end
            end
        end
        return walk(tree)
    end

    function testing.find_all_by_kind(tree, kind)
        local out = {}
        local function walk(e)
            if not e then return end
            if e.kind == kind then out[#out + 1] = e end
            for _, c in ipairs(e.children or {}) do walk(c) end
        end
        walk(tree)
        return out
    end

    function testing.text_content(tree)
        local out = {}
        local function walk(e)
            if not e then return end
            if e.kind == "text" then
                out[#out + 1] = e.text or ""
            end
            for _, c in ipairs(e.children or {}) do walk(c) end
        end
        walk(tree)
        return out
    end

    function testing.load_app(path)
        if type(path) ~= "string" or #path == 0 then
            error("load_app: path must be a non-empty string", 2)
        end

        local tui_mod = require "tui"
        local saved_render = tui_mod.render
        local captured = nil
        local call_count = 0

        tui_mod.render = function(root)
            captured = root
            call_count = call_count + 1
        end

        local chunk, load_err = loadfile(path)
        if not chunk then
            tui_mod.render = saved_render
            error("load_app: failed to load '" .. path .. "': " .. tostring(load_err), 2)
        end

        local ok, run_err = pcall(chunk)
        tui_mod.render = saved_render

        if not ok then
            error("load_app: error in '" .. path .. "': " .. tostring(run_err), 2)
        end
        if call_count == 0 then
            error("load_app: '" .. path .. "' did not call tui.render()", 2)
        end

        return captured
    end
end

return M
