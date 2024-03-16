



local function create_sandbox(code, env, maxevents, luacontroller_dynamic_values)
	
    local function traceback(...)
		local args = { ... }
		local errmsg = args[1]
		if type(errmsg)~="string" then
			-- exit the string sandbox so you can error your _G's (why am i doing this)
			local string_meta = getmetatable("")
			local sandbox = string_meta.__index
			string_meta.__index = string -- Leave string sandbox temporarily
			errmsg=dump(errmsg)
			string_meta.__index = sandbox
		end
		local t=debug.traceback() -- without args because if the errmsg is an exotic type... guess what... it just returns that?
		t=t:split("[C]: in function 'xpcall'")
		local index = 1
		if t[index] then return errmsg.."\nTraceback:\n"..t[index]
		else 
			return errmsg.."\nCould not provide traceback."
		end
	end
    
    local function timeout()
        debug.sethook() -- Clear hook
        error("Code timed out!", 2)
    end
	
    if code:byte(1) == 27 then
		return nil, "Binary code prohibited."
	end
	local f, msg = loadstring(code)
	if not f then return nil, msg end
	setfenv(f, env)

    -- turn JIT off for the lua code for count events
	if rawget(_G, "jit") then
		jit.off(f, true)
	end
	local events = 0
    local hardcoded_hook_time = 1
    -- TODO: name this better
        -- but basically its "how often does the hook code execute"
        -- less is slower but more accurate for the luacontroller
        -- more is faster but less accurate for the luacontroller
	return function(...)
		-- NOTE: This runs within string metatable sandbox, so the setting's been moved out for safety
		-- Use instruction counter to stop execution
		-- after luacontroller_maxevents
		debug.sethook(
            function(...)
                events=events + hardcoded_hook_time
                if events >= maxevents then
                    timeout()
                else
                    luacontroller_dynamic_values.events = events
                    -- expose to luac
                end
            end
		, "", hardcoded_hook_time)
		local ok, ret = xpcall(f, traceback,...)
		debug.sethook()  -- Clear hook
		if not ok then error(ret, 0) end
		return ret
	end
end
async_controller.env.create_sandbox = create_sandbox