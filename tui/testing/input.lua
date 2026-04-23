local M = {}

-- Raw terminal bytes for named keys accepted by Harness:press()/Bare:press().
local KEYS = {
    enter         = "\r",
    ["return"]    = "\r",
    escape        = "\27",
    esc           = "\27",
    tab           = "\t",
    ["shift+tab"] = "\27[Z",
    backtab       = "\27[Z",
    backspace     = "\127",
    up            = "\27[A",
    down          = "\27[B",
    right         = "\27[C",
    left          = "\27[D",
    home          = "\27[H",
    ["end"]       = "\27[F",
    insert        = "\27[2~",
    delete        = "\27[3~",
    pageup        = "\27[5~",
    pagedown      = "\27[6~",
    f1            = "\27OP",
    f2            = "\27OQ",
    f3            = "\27OR",
    f4            = "\27OS",
    f5            = "\27[15~",
    f6            = "\27[17~",
    f7            = "\27[18~",
    f8            = "\27[19~",
    f9            = "\27[20~",
    f10           = "\27[21~",
    f11           = "\27[23~",
    f12           = "\27[24~",
}

local MODIFIED_KEYS = {
    ctrl = {
        backspace = "\27[127;5u",
        enter = "\27[13;5u",
    },
    shift = {
        enter = "\27[13;2u",
    },
}

--- Wrap text with bracketed-paste markers for dispatch()/Harness:dispatch().
function M.paste(text)
    if type(text) ~= "string" then
        error("paste: expected string, got " .. type(text), 2)
    end
    return "\x1b[200~" .. text .. "\x1b[201~"
end

--- Translate one key spec ("enter", "left", "ctrl+c") into raw terminal bytes.
-- Returns nil for printable UTF-8, so callers can delegate to type()-style
-- per-codepoint dispatch when they need real typing semantics.
-- This is the canonical encoding used by Harness:press() and Bare:press().
function M.resolve_key(name)
    if type(name) ~= "string" or #name == 0 then
        error("press/keys: expected non-empty string, got " .. tostring(name), 2)
    end

    local modifier_codes = {
        shift = 2,
        meta  = 3,
        ctrl  = 5,
    }

    local cx = name:match("^ctrl%+(.)$") or name:match("^%^(.)$")
    if cx then
        local b = cx:lower():byte()
        if b < 97 or b > 122 then
            error("press: ctrl+<letter> required, got " .. name, 2)
        end
        return string.char(b - 96)
    end

    local mod, sk = name:match("^(%a+)%+(.+)$")
    if mod and sk and modifier_codes[mod] then
        local special = MODIFIED_KEYS[mod] and MODIFIED_KEYS[mod][sk:lower()]
        if special then
            return special
        end
        local base = KEYS[sk:lower()]
        if not base then
            error("press: unknown key '" .. name .. "'", 2)
        end
        local mod_code = modifier_codes[mod]
        if base:sub(1, 2) == "\27[" then
            if #base == 3 then
                return "\27[1;" .. tostring(mod_code) .. base:sub(-1)
            end
            return base:sub(1, -2) .. ";" .. tostring(mod_code) .. base:sub(-1)
        elseif base:sub(1, 2) == "\27O" then
            return "\27[1;" .. tostring(mod_code) .. base:sub(3)
        end
    end

    local raw = KEYS[name:lower()]
    if raw then
        return raw
    end

    if #name >= 1 and #name <= 4 then
        local b0 = name:byte(1)
        local expected_len
        if b0 >= 0x20 and b0 <= 0x7E then
            expected_len = 1
        elseif b0 >= 0xC0 and b0 <= 0xDF then
            expected_len = 2
        elseif b0 >= 0xE0 and b0 <= 0xEF then
            expected_len = 3
        elseif b0 >= 0xF0 and b0 <= 0xF4 then
            expected_len = 4
        end
        if expected_len and #name == expected_len then
            return nil
        end
    end

    error("press: unknown key '" .. name .. "'", 2)
end

return M
