local function traceback(...)
	local MP = minetest.get_modpath("async_controller")
	local args = { ... }
	local errmsg = tostring(args[1])
	local string_meta = getmetatable("")
	string_meta.__index = string -- Leave string sandbox permanently

	local traceback = "Traceback: " .. "\n"
	local level = 1
	while true do
		local info = debug.getinfo(level, "nlS")
		if not info then break end
		local name = info.name
		local text
		if name ~= nil then
			text = "In function " .. name
		else
			text = "In " .. info.what
		end
		if info.source == "=(load)" then
			traceback = traceback .. text .. " at line " .. info.currentline .. "\n"
		end
		level = level + 1
	end

	local base = MP:sub(1, #errmsg - #MP)
	return errmsg:gsub(base, "", 1) .. "\n" .. traceback
end

local function timeout(reason)
	debug.sethook() -- Clear hook, the only place that needs it i think
	error("Code timed out! Reason: " .. reason, 2)
end

local function create_sandbox(code, env, async_env, luacontroller_dynamic_values)
	if code:byte(1) == 27 then
		return nil, "Binary code prohibited."
	end
	local f, msg = loadstring(code)

	if not f then return nil, msg end
	setfenv(f, env)

	-- turn JIT off for the lua code for count events
	-- *sadly* this has to be done, because someone could literally just do for i=1,1000000 do end and it would just not trigger the debug hook


	if rawget(_G, "jit") then
		jit.off(f, true)
	end
	local events = 0
	local execution_time_limit = async_env.settings.execution_time_limit
	local time = minetest.get_us_time
	local old = time()
	local hook_time = async_env.settings.hook_time
	local instruction_limit = async_env.settings.maxevents
	-- perhaps the shittiest way of limiting memory... pls submit an issue or a pr if you have a better idea :D
	-- The main issue with it is outside influence
	-- which would make the async_controller unreliable
	-- so the memory limit has to be set really high
	local mem_old = collectgarbage("count")
	local max_mem = async_env.settings.max_sandbox_mem_size * 1024 -- in kilobytes
	return function(...)
		debug.sethook(
			function(...)
				local cur = time()
				local time_use = cur - old
				local mem_cur = collectgarbage("count")
				local mem_use = mem_cur - mem_old
				events = events + hook_time
				if events >= instruction_limit then
					timeout("Instruction limit exceeded! (limit: " .. instruction_limit .. ")")
				elseif time_use >= execution_time_limit then
					timeout("Execution time reached the " .. tostring(execution_time_limit / 1000) .. "ms limit!")
				elseif mem_use > max_mem then
					timeout("Sandbox memory usage exceeded! (limit: " ..
						max_mem / 1024 ..
						"mb) if this was due to outside factors im sorry, there is no better way to limit memory i think, if there is please create an issue in the async_controller repo")
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
async_controller_async.create_sandbox = create_sandbox
