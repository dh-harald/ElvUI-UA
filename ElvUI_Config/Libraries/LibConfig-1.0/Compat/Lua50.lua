-- Lua 5.1 stdlib shims for clients that only have Lua 5.0 (e.g. WoW 1.12.1).
--
-- Every shim below is guarded by "if not X then" so this file is a no-op on a
-- Lua 5.1+ client (e.g. a future WoW 3.3.5a Wrath build), where the functions
-- exist natively. That means this file can be copied as-is into a Lua 5.1
-- client build without any changes or conditionals at the call site.
--
-- NOTE: `...` as a vararg *expression* and `select(...)` cannot be shimmed this
-- way, because Lua 5.0 does not support `...` as an expression at all (only as
-- a parameter declaration, auto-populating the local `arg` table). Code that
-- needs to run on the 1.12 client must use `arg`/`arg.n` directly instead of
-- `...`/`select('#', ...)`.

if not string.gmatch then
    string.gmatch = string.gfind
end

if not string.match then
    function string.match(str, pattern, index)
        if type(str) ~= "string" then
            error(string.format("bad argument #1 to 'match' (string expected, got %s)", type(str)), 2)
        end
        local start, finish, cap1 = string.find(str, pattern, index)
        if cap1 ~= nil then
            -- string.find already returned the captures; hand them back.
            local results = { string.find(str, pattern, index) }
            table.remove(results, 1) -- start
            table.remove(results, 1) -- finish
            if table.getn(results) > 0 then
                return unpack(results)
            end
            return cap1
        elseif start then
            return string.sub(str, start, finish)
        end
        return nil
    end
end
