-- test/property/pbt.lua — minimal property-based testing helper.
--
-- Provides a deterministic RNG (Park-Miller LCG) and a check() runner that
-- exercises a property function N times.  On failure the seed and iteration
-- are included in the error message so the case can be reproduced with
-- PBT_SEED=<seed>.

local M = {}

local DEFAULT_SEED = 42

--- Create a random generator state.
--- seed: optional number (default 42, or PBT_SEED env var)
--- Returns: table with .seed and methods .next / .int / .bool / .pick / .graphemes
function M.new_rng(seed)
    seed = seed or tonumber(os.getenv("PBT_SEED")) or DEFAULT_SEED
    local state = seed
    local rng  = { seed = seed }

    --- Returns float in [0, 1)
    function rng.next()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end

    --- Integer in [lo, hi] (inclusive)
    function rng.int(lo, hi)
        return lo + math.floor(rng.next() * (hi - lo + 1))
    end

    --- Boolean with optional probability (default 0.5)
    function rng.bool(p)
        return rng.next() < (p or 0.5)
    end

    --- Pick one element from an array
    function rng.pick(t)
        return t[rng.int(1, #t)]
    end

    --- Generate a random string of grapheme clusters.
    --- len: number of grapheme clusters to generate
    --- Returns: UTF-8 string mixing ASCII, CJK, and combining marks
    function rng.graphemes(len)
        local <const> CHARS = {
            "a", "b", "c", "0", " ", "-", ".",
            "\228\184\173",  -- 中 (width 2)
            "\230\150\135",  -- 文 (width 2)
            "e\204\129",     -- e + combining acute (width 1, 2 codepoints)
        }
        local parts = {}
        for i = 1, len do
            parts[i] = rng.pick(CHARS)
        end
        return table.concat(parts)
    end

    return rng
end

--- Run a property check.
--- opts:
---   name:       string (property name for error messages)
---   iterations: number (default 100)
---   seed:       optional seed override
---   property:   function(rng, iteration) — must not error
function M.check(opts)
    local name     = opts.name or "property"
    local n        = opts.iterations or 100
    local rng      = M.new_rng(opts.seed)
    local property = opts.property

    for i = 1, n do
        local ok, err = pcall(property, rng, i)
        if not ok then
            error(("%s failed at iteration %d (seed=%d): %s")
                :format(name, i, rng.seed, tostring(err)), 0)
        end
    end
end

return M
