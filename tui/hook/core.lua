-- tui/hook/core.lua — shared hook infrastructure.
--
-- Provides the module-level state (current instance, cursor slot index,
-- dev-mode flag) and helpers used by all hook sub-modules.  The reconciler
-- calls _begin_render / _end_render / _flush_effects / _unmount through
-- this module.

local scheduler = require "tui.internal.scheduler"

local M = {}

-- ---------------------------------------------------------------------------
-- Dev mode (Stage 17). When enabled:
--   * Hook order is validated across renders; drift is a [tui:fatal] error.
--   * useState/useReducer setters warn if called synchronously during render.
--   * Reconciler warns on >1 element children with any unkeyed child.
-- Disabled by default -> all checks compile out behind a single `if` each.

local dev_mode = false

function M._set_dev_mode(on)
    dev_mode = on and true or false
end

function M._is_dev_mode() return dev_mode end

-- Walk up the call stack to find the first frame whose source file is NOT
-- inside the framework itself (tui/*.lua or tui_core). That's the user code
-- that triggered the warning — far more useful than a hook-internal line.
-- Returns "file.lua:NN: " ready to be prepended, or "" if no user frame was
-- found (framework-internal call path).
local function _source_prefix()
    for lvl = 2, 20 do
        local info = debug.getinfo(lvl, "Sl")
        if not info then break end
        local src = info.source or ""
        -- Skip C frames, =[C] tags, and any source inside the framework tree.
        -- Match on "/tui/" or "\tui\" — cross-platform path separators.
        if src:sub(1, 1) == "@"
            and not src:find("[/\\]tui[/\\]", 1, false)
            and not src:find("[/\\]ltest%.lua$")
        then
            -- Strip leading "@" and any directory prefix for readability.
            local path = src:sub(2)
            local tail = path:match("[^/\\]+$") or path
            return tail .. ":" .. tostring(info.currentline) .. ": "
        end
    end
    return ""
end
M._source_prefix = _source_prefix

local function _warn(msg)
    if dev_mode then
        io.stderr:write("[tui:dev] " .. _source_prefix() .. msg .. "\n")
    end
end
M._warn = _warn

-- ---------------------------------------------------------------------------
-- Current instance (set by reconciler during a render pass)

local current   = nil
local cursor    = 0

-- Set while a component fn is actively executing; cleared when it returns.
-- setState/dispatch compare against this to detect synchronous state writes
-- inside render (an anti-pattern). Post-commit effects run with this cleared,
-- so `setN(...)` inside useEffect bodies is legal and won't warn.
M._rendering_inst = nil

function M._begin_render(instance)
    current = instance
    cursor  = 0
    instance.hooks         = instance.hooks         or {}
    instance.pending_fx    = {}
    if dev_mode then
        instance._hook_kinds = {}
    end
    M._rendering_inst = instance
end

function M._end_render()
    if dev_mode and current then
        local prev = current._prev_hook_kinds
        local curr = current._hook_kinds
        if prev and curr then
            if #prev ~= #curr then
                local err = ("[tui:fatal] hook count mismatch: last render used %d hooks, this render used %d")
                    :format(#prev, #curr)
                current._prev_hook_kinds = nil
                current._hook_kinds = nil
                M._rendering_inst = nil
                current = nil
                cursor = 0
                error(err, 0)
            end
            for i = 1, #curr do
                if prev[i] ~= curr[i] then
                    local err = ("[tui:fatal] hook order violation at slot %d: expected %s, got %s")
                        :format(i, tostring(prev[i]), tostring(curr[i]))
                    current._prev_hook_kinds = nil
                    current._hook_kinds = nil
                    M._rendering_inst = nil
                    current = nil
                    cursor = 0
                    error(err, 0)
                end
            end
        end
        current._prev_hook_kinds = curr
        current._hook_kinds = nil
    end
    M._rendering_inst = nil
    current = nil
    cursor  = 0
end

-- ---------------------------------------------------------------------------
-- Shared helpers

-- Shallow-equal for two arrays of deps (rawequal per element, same length).
function M.deps_equal(a, b)
    if a == nil or b == nil then return false end
    if #a ~= #b then return false end
    for i = 1, #a do
        if not rawequal(a[i], b[i]) then return false end
    end
    return true
end

-- Message handler for xpcall: wraps error into {message, trace} so
-- boundaries receive a structured object rather than a bare string.
-- Idempotent so re-throws across nested boundaries don't double-wrap.
-- Fatal errors (with the [tui:fatal] prefix) are NOT wrapped — they bypass
-- boundaries entirely, so wrapping adds no value and complicates callers.
function M.wrap_err(e)
    if type(e) == "table" and e.message ~= nil then return e end
    if type(e) == "string" and e:sub(1, 12) == "[tui:fatal] " then return e end
    return { message = e, trace = debug.traceback(e, 2) }
end

local reconciler_mod   -- lazy require to avoid init cycle
local function ensure_reconciler()
    reconciler_mod = reconciler_mod or require "tui.internal.reconciler"
    return reconciler_mod
end

function M.route_effect_error(instance, err)
    local rec = ensure_reconciler()
    if rec.is_fatal(err) then error(err, 0) end

    local boundary = instance.nearest_boundary
    if boundary then
        boundary.caught_error = err
        boundary.dirty = true   -- pokes harness stabilization + main loop
        scheduler.requestRedraw()
        return
    end
    -- No boundary: unwrap to the original message string so that callers
    -- above (framework pcall, test pcall) see a plain error, not a table.
    error(type(err) == "table" and err.message or err, 0)
end

-- Wrap a user-supplied event handler (useInput, useFocus onInput) so any
-- error raised during dispatch routes to the nearest ErrorBoundary set on
-- the owning component instance at subscribe time. The instance reference
-- is captured *once* here; its `.nearest_boundary` field is refreshed by
-- the reconciler every render so the lookup stays current.
--
-- The wrapped closure has the same calling convention as `fn`. Returning
-- fn's first result would complicate the happy path for no benefit since
-- input handlers are fire-and-forget — we just preserve nil.
function M.wrap_handler_for_boundary(instance, fn)
    return function(...)
        local ok, err = xpcall(fn, M.wrap_err, ...)
        if not ok then M.route_effect_error(instance, err) end
    end
end

function M._route_handler_error(instance, err)
    M.route_effect_error(instance, err)
end

-- ---------------------------------------------------------------------------
-- Access current instance without advancing the cursor.
-- Used by hooks that don't have their own slot (useInput, useFocusManager, etc.)
-- but need to validate they're called during render and/or capture the instance.

function M._current()
    assert(current, "hook called outside of a component render")
    return current
end

-- ---------------------------------------------------------------------------
-- Hook slot allocation + dev-mode plain-function detection

-- When a plain function (not a registered component) calls a hook, Lua's
-- `current` at hook time points at the *parent* component whose render is
-- on the call stack — not nil. So `assert(current, ...)` won't catch this
-- footgun; the hook silently tacks itself onto the parent's slot list,
-- and a later conditional render produces a hook count mismatch somewhere
-- far from the real cause.
--
-- Dev-mode detection: every `_begin_render` records the component's `fn`
-- on the instance. `require_instance` finds the first user-code frame
-- above itself (skipping all tui/hook/*.lua frames — internal hooks like
-- useInterval call useEffect across sub-modules) and checks whether that
-- frame's function is the currently-rendering component. If not, some
-- intermediate helper function is the direct caller — raise with its
-- source location.
local function detect_plain_function_hook()
    if not dev_mode then return end
    if not current then return end
    local expected = current._component_fn
    if not expected then return end

    local user_lvl
    for lvl = 3, 30 do
        local info = debug.getinfo(lvl, "S")
        if not info then break end
        -- Skip any source inside the tui/hook/ tree (all hook sub-modules).
        if info.source:find("tui/hook/", 1, true) then
            -- continue walking
        else
            user_lvl = lvl
            break
        end
    end
    if not user_lvl then return end

    local info = debug.getinfo(user_lvl, "Sfl")
    if not info then return end
    if info.func == expected then return end

    local where = (info.source or "?") .. ":" .. tostring(info.currentline)
    error("[tui:fatal] hook called from a plain function (" .. where ..
          ") inside the render of another component; wrap it with " ..
          "`{ kind='component', fn=..., props=... }` (see tui/builtin/spinner.lua) " ..
          "so its hooks live on their own instance.", 0)
end

function M.require_instance(kind)
    assert(current, "hook called outside of a component render")
    detect_plain_function_hook()
    cursor = cursor + 1
    if dev_mode and kind then
        current._hook_kinds[cursor] = kind
    end
    return current, cursor
end

return M
