-- tui/extra/init.lua — Extra components for tui.lua
--
-- These components are not part of the core framework but are commonly useful.
--
-- Usage:
--   local extra = require "tui.extra"
--   extra.TextInput { ... }

local M = {}

M.TextInput   = require("tui.extra.text_input").TextInput
M.Textarea    = require("tui.extra.textarea").Textarea
M.editing     = require("tui.extra.editing")
M.Static      = require("tui.extra.static").Static
M.Select      = require("tui.extra.select").Select
M.Spinner     = require("tui.extra.spinner").Spinner
M.ProgressBar = require("tui.extra.progress_bar").ProgressBar
M.Newline     = require("tui.extra.newline").Newline
M.Spacer      = require("tui.extra.newline").Spacer

return M
