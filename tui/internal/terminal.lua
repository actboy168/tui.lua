local M = {}

local <const> IS_WINDOWS = package.config:sub(1,1) == "\\"

-- ---------------------------------------------------------------------------
-- Terminal type detection

local function detect_term_type()
    local term_program = os.getenv("TERM_PROGRAM") or ""
    local term         = os.getenv("TERM") or ""

    if term_program == "iTerm.app" then
        return "iterm2"
    elseif term_program == "Apple_Terminal" then
        return "apple_terminal"
    elseif term_program == "WezTerm" then
        return "wezterm"
    elseif term_program == "Alacritty" then
        return "alacritty"
    elseif term_program == "vscode" then
        return "vscode"
    elseif term_program == "ghostty" then
        return "ghostty"
    elseif term_program == "Hyper" then
        return "hyper"
    elseif term_program == "mintty" then
        return "mintty"
    end

    if os.getenv("WT_SESSION") then
        return "windows_terminal"
    end

    if IS_WINDOWS and (os.getenv("WEZTERM_EXECUTABLE") or "") ~= "" then
        return "wezterm"
    end

    if os.getenv("ALACRITTY_WINDOW_ID") then
        return "alacritty"
    end

    if os.getenv("KITTY_WINDOW_ID") then
        return "kitty"
    end

    if os.getenv("ZED_TERM") then
        return "zed"
    end

    if os.getenv("TMUX") then
        return "tmux"
    end

    if term == "xterm-kitty" then
        return "kitty"
    elseif term == "xterm-ghostty" then
        return "ghostty"
    elseif term == "foot" or term == "foot-direct" then
        return "foot"
    elseif term == "wezterm" then
        return "wezterm"
    elseif term:find("alacritty", 1, true) then
        return "alacritty"
    elseif term:find("kitty", 1, true) then
        return "kitty"
    elseif term:find("foot", 1, true) then
        return "foot"
    end

    if IS_WINDOWS then
        return "windows_legacy"
    end

    return "unknown"
end

-- ---------------------------------------------------------------------------
-- Color depth detection

local function detect_color_level(term_type)
    local colorterm = os.getenv("COLORTERM") or ""
    if colorterm == "truecolor" or colorterm == "24bit" then
        return 2
    end

    local TRUECOLOR_TERMS = {
        kitty = true, wezterm = true, iterm2 = true, ghostty = true,
        alacritty = true, foot = true, windows_terminal = true, zed = true,
    }
    if TRUECOLOR_TERMS[term_type] then return 2 end

    local term = os.getenv("TERM") or ""
    if term:find("256color", 1, true) or term_type == "tmux" then
        return 1
    end

    return 0
end

-- ---------------------------------------------------------------------------
-- Capability detection

local CAPABILITIES = {
    iterm2  = { ime_osc1337 = true },
    kitty   = { osc_st      = true },
}

local KITTY_KBD_TERMS = {
    kitty            = true,
    wezterm          = true,
    ghostty          = true,
    foot             = true,
    alacritty        = true,
    iterm2           = true,
    windows_terminal = true,
    vscode           = true,
    zed              = true,
    hyper            = true,
}

local function check_sync_output(term_type)
    if term_type == "tmux" then return false end
    if term_type == "iterm2" then return true end
    if term_type == "wezterm" then return true end
    if term_type == "ghostty" then return true end
    if term_type == "kitty" then return true end
    if term_type == "vscode" then return true end
    if term_type == "alacritty" then return true end
    if term_type == "foot" then return true end
    if term_type == "zed" then return true end
    if term_type == "windows_terminal" then return true end
    local vte = os.getenv("VTE_VERSION")
    if vte then
        local version = tonumber(vte)
        if version and version >= 6800 then return true end
    end
    return false
end

local function check_cursor_shape(term_type)
    if term_type == "apple_terminal" then return false end
    if term_type == "windows_legacy" then return false end
    if term_type == "unknown" then return false end
    return true
end

local function check_alt_screen(term_type)
    if term_type == "apple_terminal" then return false end
    if term_type == "unknown" then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Environment detection (CI / TTY)

local function is_ci()
    if os.getenv("CI") then return true end
    if os.getenv("GITHUB_ACTIONS") then return true end
    if os.getenv("JENKINS_URL") then return true end
    if os.getenv("TRAVIS") then return true end
    if os.getenv("CIRCLECI") then return true end
    if os.getenv("GITLAB_CI") then return true end
    if os.getenv("BUILDKITE") then return true end
    if os.getenv("TF_BUILD") then return true end
    return false
end

local function is_tty()
    return (os.getenv("TERM") ~= nil) or IS_WINDOWS
end

-- ---------------------------------------------------------------------------
-- Interactive mode

function M.interactive()
    return is_tty() and not is_ci()
end

-- ---------------------------------------------------------------------------
-- Capability detection entry point

local function check_kitty_keyboard(term_type)
    if KITTY_KBD_TERMS[term_type] then return true end
    local vte = os.getenv("VTE_VERSION")
    if vte then
        local version = tonumber(vte)
        if version and version >= 6800 then return true end
    end
    local konsole = os.getenv("KONSOLE_VERSION")
    if konsole then
        local version = tonumber(konsole)
        if version and version >= 220400 then return true end
    end
    local xterm = os.getenv("XTERM_VERSION")
    if xterm then
        local ver = xterm:match("%((%d+)%)")
        if ver then
            local version = tonumber(ver)
            if version and version >= 369 then return true end
        end
    end
    return false
end

function M.detect_capabilities(forced_term_type)
    local term_type = forced_term_type or detect_term_type()
    local base = CAPABILITIES[term_type] or {}
    return {
        terminal_type   = term_type,
        color_level     = detect_color_level(term_type),
        sync_output     = check_sync_output(term_type),
        cursor_shape    = check_cursor_shape(term_type),
        alt_screen      = check_alt_screen(term_type),
        kitty_keyboard  = check_kitty_keyboard(term_type),
        osc_st          = base.osc_st      and true or false,
        ime_osc1337     = base.ime_osc1337 and true or false,
        legacy_windows  = term_type == "windows_legacy",
    }
end

-- vterm default capabilities
M.default_vterm_capabilities = {
    terminal_type   = "vterm",
    color_level     = 2,
    sync_output     = true,
    cursor_shape    = true,
    alt_screen      = true,
    kitty_keyboard  = true,
    osc_st          = false,
    ime_osc1337     = false,
    legacy_windows  = false,
}

return M
