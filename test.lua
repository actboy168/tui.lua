-- test.lua — entry point for `luamake test` (equivalent to `luamake lua test.lua`).
local lt = require "ltest"
local fs = require "bee.filesystem"

-- Register tui.* modules for coverage tracking (no-op without --coverage).
local COVERAGE_EXCLUDE = { testing = true }

for entry in fs.pairs("tui") do
    local name = entry:filename():string()
    local mod = name:match("^(.+)%.lua$")
    if mod and not COVERAGE_EXCLUDE[mod] then
        lt.moduleCoverage("tui." .. mod)
    end
end

local function collect_tests(dir, out)
    for file, status in fs.pairs(dir) do
        if status:is_directory() then
            collect_tests(file, out)
        else
            local name = file:filename():string()
            local path = file:string()
            if name:match("^test_.+%.lua$") then
                out[#out + 1] = path
            end
        end
    end
end

local files = {}
collect_tests("test", files)
table.sort(files)
for _, path in ipairs(files) do
    require(path:gsub("%.lua$", ""):gsub("[/\\]", "."))
end

os.exit(lt.run(), true)
