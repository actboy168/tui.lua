local M = {}

local time = require "bee.time"
local thread = require "bee.thread"
local platform = require "bee.platform"

function M.monotonic()
    return time.monotonic()
end

function M.sleep(ms)
    thread.sleep(ms)
end

function M.os()
    return platform.os
end

return M
