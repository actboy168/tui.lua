-- test.lua — entry point for `luamake test` (equivalent to `luamake lua test.lua`).
local lt = require "ltest"

require "test.test_element"

os.exit(lt.run(), true)
