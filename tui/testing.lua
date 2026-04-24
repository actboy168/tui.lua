-- tui/testing.lua — public test helpers and harness entrypoints.

local input   = require "tui.testing.input"
local mouse   = require "tui.testing.mouse"
local capture = require "tui.testing.capture"
local harness = require "tui.testing.harness"
local bare    = require "tui.testing.bare"
local snapshot = require "tui.testing.snapshot"
local inspect = require "tui.testing.inspect"


local M = {
    input = input,
    mouse = mouse,
    harness = harness.harness,
    bare = bare.bare,
    capture_stderr = capture.capture_stderr,
}

snapshot.install(harness.Harness)
inspect.install(M, harness.Harness)

return M
