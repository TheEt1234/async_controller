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
	-- *sadly* this has to be done, because an attacker could literally just do for i=1,1000000 do end and it would just not trigger any event
	-- or does it
	-- well... i will try


	if rawget(_G, "jit") then
		jit.off(f, true)
	end
	local events = 0
	local execution_time_limit = async_env.settings.execution_time_limit
	local time = minetest.get_us_time
	local old = time()
	local hook_time = async_env.settings.hook_time
	local maxevents = async_env.settings.maxevents
	-- perhaps the shittiest way of limiting memory... pls submit an issue or a pr if you have a better idea :D
	-- The main issue with it is outside influence
	-- which would make the async_controller unreliable
	-- so the memory limit has to be set really high
	local mem_old = collectgarbage("count")
	local max_mem = async_env.settings.max_sandbox_mem_size*1024 -- in kilobytes
	return function(...)
		debug.sethook(
			function(...)
				local cur = time()
				local time_use = cur - old
				local mem_cur = collectgarbage("count")
				local mem_use = mem_cur - mem_old
				events = events + hook_time
				if events >= maxevents then
					timeout("Too many code events! (limit: "..maxevents..")")
				elseif time_use >= execution_time_limit then
					timeout("Execution time reached the " .. tostring(execution_time_limit / 1000) .."ms limit!")
				elseif mem_use>max_mem then
					timeout("Sandbox memory usage exceeded! (limit: " .. max_mem/1024 .. "mb) if this was due to outside factors im sorry, there is no better way to limit memory i think, if there is please create an issue in the async_controller repo")
				else
					luacontroller_dynamic_values.events = events
					luacontroller_dynamic_values.ram_usage = mem_use
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
