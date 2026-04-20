-- tui/testing.lua — public test helpers and harness entrypoints.

local input   = require "tui.testing.input"
local mouse   = require "tui.testing.mouse"
local capture = require "tui.testing.capture"
local harness = require "tui.testing.harness"
local snapshot = require "tui.testing.snapshot"
local inspect = require "tui.testing.inspect"

local M = {
    input = input,
    mouse = mouse,
    render = harness.render,
    mount_bare = harness.mount_bare,
    capture_stderr = capture.capture_stderr,
    capture_writes = capture.capture_writes,
}

snapshot.install(harness.Harness)
inspect.install(M, harness.Harness)

return M
