-- tui/builtin/spinner.lua — <Spinner> component.
--
-- Props:
--   type     : one of the built-in sets (default "dots"). Ignored when
--              `frames` is provided.
--   frames   : optional custom frame list; when set, `type` is ignored and
--              `interval` defaults to 80ms if also not given. Each frame
--              is rendered as a single Text row.
--   interval : per-frame ms. Default is the built-in's native cadence
--              (dots=80, line=80), or 80 for custom `frames`.
--   label    : optional text appended after the spinner glyph, separated
--              by one space. Empty / nil = glyph only.
--   color    : forwarded to the Text's color prop.
--
-- Lifecycle: Spinner runs unconditionally while mounted. To stop spinning,
-- unmount (e.g. `isLoading and tui.Spinner { ... } or nil`). This matches
-- Ink's ink-spinner; avoids an `isActive` prop that duplicates mount/unmount.
--
-- Passing both `type` and `frames` is an error (ambiguous intent).

local element = require "tui.element"
local hooks   = require "tui.hooks"

local M = {}

-- Built-in frame sets. Trimmed subset of cli-spinners (MIT); more can be
-- shipped later but the framework intentionally stays small — users drop
-- in their own via `frames = { ... }`.
local BUILTINS = {
    dots = {
        frames   = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        interval = 80,
    },
    line = {
        frames   = { "-", "\\", "|", "/" },
        interval = 80,
    },
}

local function resolve(props)
    if props.frames ~= nil then
        if props.type ~= nil then
            error("Spinner: pass either `type` or `frames`, not both", 3)
        end
        if type(props.frames) ~= "table" or #props.frames == 0 then
            error("Spinner: `frames` must be a non-empty array", 3)
        end
        return props.frames, (props.interval or 80)
    end
    local kind = props.type or "dots"
    local preset = BUILTINS[kind]
    if not preset then
        error("Spinner: unknown type '" .. tostring(kind) .. "' (known: dots, line). " ..
              "Pass custom `frames` for anything else.", 3)
    end
    return preset.frames, (props.interval or preset.interval)
end

local function SpinnerImpl(props)
    props = props or {}
    local frames, interval = resolve(props)

    local anim = hooks.useAnimation {
        interval = interval,
        isActive = true,
    }

    local glyph = frames[(anim.frame % #frames) + 1]
    local text = glyph
    if props.label and #props.label > 0 then
        text = glyph .. " " .. props.label
    end

    local text_props = { text }
    if props.color ~= nil then text_props.color = props.color end
    return element.Text(text_props)
end

function M.Spinner(props)
    props = props or {}
    local key = props.key
    props.key = nil
    return { kind = "component", fn = SpinnerImpl, props = props, key = key }
end

-- Exposed so tests / advanced users can introspect / extend.
M._BUILTINS = BUILTINS

return M
