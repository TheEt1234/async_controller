local function create_sandbox(code, env, async_env, luacontroller_dynamic_values)
	local function traceback(...)
		local args = { ... }
		local errmsg = args[1]
		local string_meta = getmetatable("")
		local sandbox = string_meta.__index
		string_meta.__index = string -- Leave string sandbox temporarily
		if type(errmsg) ~= "string" then errmsg = "Unknown error of type: " .. type(errmsg) end

		local t = debug.traceback()
		string_meta.__index = sandbox
		--[[
		t=t:split("[C]: in function 'xpcall'")
		local index = 1
		if t[index] then return errmsg.."\nTraceback:\n"..t[index]
		else
			return errmsg.."\nCould not provide traceback."
		end
		--]]
		return errmsg .. "\n" .. t
	end

	local function timeout(reason)
		debug.sethook() -- Clear hook
		error("Code timed out! Reason: " .. reason, 2)
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
	local execution_time_limit = async_env.settings.execution_time_limit
	local old = minetest.get_us_time()
	local hook_time = async_env.settings.hook_time
	local maxevents = async_env.settings.maxevents
		-- TODO: name this better
		-- but basically its "how often does the hook code execute"
		-- less is slower but more accurate for the luacontroller
		-- more is zfaster but less accurate for the luacontroller
	return function(...)
		-- NOTE: This runs within string metatable sandbox, so the setting's been moved out for safety
		-- Use instruction counter to stop execution
		-- after luacontroller_maxevents
		debug.sethook(
			function(...)
				local cur = minetest.get_us_time()
				local diff = cur - old
				events = events + hook_time
				if events >= maxevents then
					timeout("Too many code events!")
				elseif diff >= execution_time_limit then
					timeout("Execution time reached the " .. tostring(execution_time_limit / 1000) .."ms limit!")
				else
					luacontroller_dynamic_values.events = events
					-- expose to luac
				end
			end
			, "", hook_time)
		local ok, ret = xpcall(f, traceback, ...)
		debug.sethook() -- Clear hook
		if not ok then error(ret, 0) end
		return ret
	end
end
async_controller.env.create_sandbox = create_sandbox
