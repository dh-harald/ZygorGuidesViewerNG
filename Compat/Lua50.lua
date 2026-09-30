-- Lua 5.1 stdlib shims for clients that only have Lua 5.0 (e.g. WoW 1.12.1).
--
-- Every shim below is guarded by "if not X then" so this file is a no-op on
-- clients that already run Lua 5.1+ (e.g. WoW 3.3.5a Wrath), where these
-- functions exist natively. That means this file can be copied as-is into a
-- Lua 5.1 client build without any changes or conditionals at the call site.
--
-- NOTE: `...` as a vararg *expression* and `select(...)` cannot be shimmed
-- this way, because Lua 5.0 does not support `...` as an expression at all
-- (only as a parameter declaration, auto-populating the local `arg` table).
-- Code that needs to run on the 1.12 client must use `arg`/`arg.n` directly
-- instead of `...`/`select('#', ...)`.

local find, sub = string.find, string.sub

if not string.gmatch then
    string.gmatch = string.gfind
end

if not string.match then
    function string.match(str, pattern, index)
        if type(str) ~= "string" and type(str) ~= "number" then
            error(format("bad argument #1 to 'match' (string expected, got %s)", str ~= nil and type(str) or "no value"), 2)
        elseif type(pattern) ~= "string" and type(pattern) ~= "number" then
            error(format("bad argument #2 to 'match' (string expected, got %s)", pattern ~= nil and type(pattern) or "no value"), 2)
        elseif index and type(tonumber(index)) ~= "number" then
            error(format("bad argument #3 to 'match' (number expected, got %s)", index ~= nil and type(index) or "no value"), 2)
        end

        local i1, i2, match, match2 = find(str, pattern, index)

        if not match and i2 and i2 >= i1 then
            return sub(str, i1, i2)
        elseif match2 then
            local matches = {find(str, pattern, index)}
            tremove(matches, 2)
            tremove(matches, 1)
            return unpack(matches)
        end

        return match
    end
end
