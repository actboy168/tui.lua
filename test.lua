-- test.lua — entry point for `luamake test` (equivalent to `luamake lua test.lua`).
local lt = require "ltest"

require "test.test_element"
require "test.test_reconciler"
require "test.test_scheduler"
require "test.test_keys"

os.exit(lt.run(), true)
