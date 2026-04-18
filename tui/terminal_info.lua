-- tui/terminal_info.lua — terminal emulator detection & IME capability query.
--
-- Detects the terminal emulator type via environment variables and exposes
-- IME capability flags so that set_ime_pos can choose the optimal sequence
-- for each terminal.
--
-- Detection priority (first match wins):
--   $TERM_PROGRAM  — primary indicator on macOS (iTerm2, Apple_Terminal, …)
--   $TERM          — fallback (xterm-kitty, alacritty, wezterm)
--
-- Capability flags:
--   ime_osc1337       — supports OSC 1337 for IME candidate positioning (iTerm2)
--   ime_kitty_proto   — supports kitty keyboard protocol IME features
--   ime_csi_cup       — fallback: standard CSI cursor positioning works

local M = {}

-- ---------------------------------------------------------------------------
-- Terminal type detection

--- Detect the current terminal emulator.
-- Returns a string identifier: "iterm2", "kitty", "apple_terminal",
-- "alacritty", "wezterm", or "unknown".
function M.detect()
    local term_program = os.getenv("TERM_PROGRAM") or ""
    local term         = os.getenv("TERM") or ""

    -- $TERM_PROGRAM takes priority (most reliable on macOS).
    if term_program == "iTerm.app" then
        return "iterm2"
    elseif term_program == "Apple_Terminal" then
        return "apple_terminal"
    elseif term_program == "WezTerm" then
        return "wezterm"
    end

    -- Fallback to $TERM for terminals that set it distinctively.
    if term == "xterm-kitty" then
        return "kitty"
    elseif term == "alacritty" then
        return "alacritty"
    elseif term == "wezterm" then
        return "wezterm"
    end

    return "unknown"
end

-- ---------------------------------------------------------------------------
-- IME capability table

-- Cache the detection result so repeated calls are free.
local cached_type = nil

local CAPABILITIES = {
    iterm2         = { ime_osc1337 = true, ime_kitty_proto = false, ime_csi_cup = true  },
    kitty          = { ime_osc1337 = false, ime_kitty_proto = true,  ime_csi_cup = true  },
    apple_terminal = { ime_osc1337 = false, ime_kitty_proto = false, ime_csi_cup = true  },
    alacritty      = { ime_osc1337 = false, ime_kitty_proto = false, ime_csi_cup = true  },
    wezterm        = { ime_osc1337 = false, ime_kitty_proto = false, ime_csi_cup = true  },
    unknown        = { ime_osc1337 = false, ime_kitty_proto = false, ime_csi_cup = true  },
}

--- Get the IME capability flags for the current terminal.
-- Returns a table with boolean fields:
--   ime_osc1337       — OSC 1337 IME positioning (iTerm2)
--   ime_kitty_proto   — kitty keyboard protocol IME features
--   ime_csi_cup       — standard CSI cursor positioning (universal fallback)
function M.capabilities()
    if not cached_type then cached_type = M.detect() end
    return CAPABILITIES[cached_type] or CAPABILITIES.unknown
end

--- Get the detected terminal type string (cached after first call).
function M.terminal_type()
    if not cached_type then cached_type = M.detect() end
    return cached_type
end

--- Force re-detection (useful if environment changes in tests).
function M._reset()
    cached_type = nil
end

return M
