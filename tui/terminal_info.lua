-- tui/terminal_info.lua — CI/TTY checks and interactive gate.

local M = {}

-- ---------------------------------------------------------------------------
-- Platform detection

local <const> IS_WINDOWS = (require "bee.platform").os == "windows"

-- ---------------------------------------------------------------------------
-- CI detection

--- Check if running in a CI environment.
function M.is_ci()
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

-- ---------------------------------------------------------------------------
-- TTY detection

local is_tty_cache = nil

function M.is_tty()
    if is_tty_cache ~= nil then return is_tty_cache end
    is_tty_cache = (os.getenv("TERM") ~= nil) or IS_WINDOWS
    return is_tty_cache
end

--- Override TTY detection (for production integrators or tests).
function M.set_tty(value)
    is_tty_cache = value and true or false
end

-- ---------------------------------------------------------------------------
-- Interactive mode

--- Check if the terminal is interactive (TTY + not in CI).
function M.interactive()
    return M.is_tty() and not M.is_ci()
end

--- Force re-detection (useful if environment changes in tests).
function M._reset()
    is_tty_cache = nil
end

return M
