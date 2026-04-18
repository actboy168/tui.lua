-- test.lua — entry point for `luamake test` (equivalent to `luamake lua test.lua`).
local lt = require "ltest"
local fs = require "bee.filesystem"

local files = {}
for entry in fs.pairs("test") do
    local name = entry:filename():string()
    if name:match("^test_.+%.lua$") then
        files[#files + 1] = name:gsub("%.lua$", "")
    end
end
table.sort(files)
for _, mod in ipairs(files) do
    require("test." .. mod)
end

os.exit(lt.run(), true)
