-- test.lua — entry point for `luamake test` (equivalent to `luamake lua test.lua`).
local lt = require "ltest"

require "test.test_element"
require "test.test_reconciler"
require "test.test_scheduler"
require "test.test_keys"
require "test.test_wcwidth"
require "test.test_text_wrap"
require "test.test_static"
require "test.test_text_input"
require "test.test_chat_flow"
require "test.test_snapshots"
require "test.test_dirty"

os.exit(lt.run(), true)
