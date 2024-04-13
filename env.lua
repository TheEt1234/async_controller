-- The thing responsible for the environment, aka what you like uhh... interract with


local function get_modify_self(pos, itbl, send_warning)
	local max_code_len = async_controller_async.settings.modify_self_max_code_len
	return function(code)
		if type(code) ~= "string" then
			send_warning("Code in modify_self is the wrong type!")
			return
		end
		if #code >= max_code_len then
			send_warning("Code in modify_self is too large!")
			return
		end
		table.insert(itbl, {
			function(ret)
				local meta = ret.get_meta(ret.pos)
				ret.reset_formspec(meta, ret.code)
				meta:set_int("luac_id", math.random(1, 65535))
				meta:set_int("has_modified_code", 1)
			end,
			{
				pos = pos, code = code
			}
		})
	end
end

local function get_clearterm(pos, itbl)
	return function()
		table.insert(itbl, {
			function(ret) ret.get_meta(ret.pos):set_string("print", "") end,
			{
				pos = pos
			}
		})
	end
end

local function get_safe_print(pos, itbl)
	return function(text_to_print)
		local string_meta = getmetatable("")
		local sandbox = string_meta.__index
		string_meta.__index = string


		if type(text_to_print) ~= "string" then
			text_to_print = dump(text_to_print) or ""
		end
		table.insert(itbl, {
			function(ret)
				local meta = ret.get_meta(ret.pos)
				local oldtext = meta:get_string("print") or ""
				local newtext = string.sub(oldtext .. ret.text_to_print .. "\n", -100000, -1) -- https://github.com/mt-mods/mooncontroller/blob/master/controller.lua#L74
				meta:set_string("print", newtext)
			end, {
			text_to_print = text_to_print,
			pos = pos,
		} })
		string_meta.__index = sandbox -- Restore string sandbox
	end
end

local function safe_date()
	return (os.date("*t", os.time()))
end

-- string.rep(str, n) with a high value for n can be used to DoS
-- the server. Therefore, limit max. length of generated string.

local function safe_string_rep(str, n)
	if #str * n > 64000 then
		--		debug.sethook() -- Clear hook
		error("string.rep: string length overflow", 2)
	end

	return string.rep(str, n)
end

-- string.find with a pattern can be used to DoS the server.
-- Therefore, limit string.find to patternless matching.
local function safe_string_find(...)
	if (select(4, ...)) ~= true then
		--		debug.sethook() -- Clear hook
		error("string.find: 'plain' (fourth parameter) must always be true in a Luacontroller")
	end

	return string.find(...)
end

-- do not allow pattern matching in string.split (see string.find for details)
local function safe_string_split(...)
	if select(5, ...) then
		--		debug.sethook() -- Clear hook
		error("string.split: 'sep_is_pattern' (fifth parameter) may not be used in a Luacontroller")
	end

	return string.split(...)
end

-- Force lightweight interrupts
-- yes i know lame but
-- supporting both would be a pain
get_interrupt = function(pos, itbl, send_warning)
	return (function(time, iid)
		if type(time) ~= "number" then error("Delay must be a number") end
		if iid ~= nil then send_warning("Interrupt IDs don't exist in async_controller (might change)") end
		table.insert(itbl, {
			function(ret) minetest.get_node_timer(ret.pos):start(ret.time) end,
			{
				pos = pos, time = time
			} })
	end)
end



local function clean_and_weigh_digiline_message(msg, back_references)
	local t = type(msg)
	if t == "string" then
		return msg, #msg + 25
	elseif t == "number" and msg == msg then
		-- Doesn't let NaN thru, this was done because like...
		-- nobody checks for nan, and that can lead to pretty funny behaviour, see https://github.com/BuckarooBanzay/digibuilder/issues/20 and

		return msg, 8
	elseif t == "boolean" then
		return msg, 1
	elseif t == "table" then
		back_references = back_references or {}
		local bref = back_references[msg]
		if bref then
			return bref, 0
		end
		local cost = 8
		local ret = {}
		back_references[msg] = ret
		for k, v in pairs(msg) do
			local k_cost, v_cost
			k, k_cost = clean_and_weigh_digiline_message(k, back_references)
			v, v_cost = clean_and_weigh_digiline_message(v, back_references)
			if k ~= nil and v ~= nil then
				-- Only include an element if its key and value are of legal
				-- types.
				ret[k] = v
			end
			cost = cost + k_cost + v_cost
		end
		return ret, cost
	else
		return nil, 0
	end
end

-- itbl: Flat table of functions (or tables) to run after sandbox cleanup, used to prevent various security hazards
-- ok no really what hazards????/ but i dont really care because it made my job initially a L O T easier
local function get_digiline_send(pos, itbl, send_warning, luac_id)
	return function(channel, msg)
		-- NOTE: This runs within string metatable sandbox, so don't *rely* on anything of the form (""):y
		--        or via anything that could.
		-- Make sure channel is string, number or boolean
		if type(channel) == "string" then
			if #channel > async_controller_async.settings.channel_maxlen then
				send_warning("Channel string too long.")
				return false
			end
		elseif (type(channel) ~= "string" and type(channel) ~= "number" and type(channel) ~= "boolean") then
			send_warning("Channel must be string, number or boolean.")
			return false
		end

		local msg_cost
		msg, msg_cost = clean_and_weigh_digiline_message(msg, nil)
		if msg == nil or msg_cost > async_controller_async.settings.message_maxlen then
			send_warning("Message was too complex, or contained invalid data.")
			return false
		end

		table.insert(itbl, {
			function(ret)
				ret.mesecon_queue:add_action(ret.pos, "lc_digiline_relay", { ret.channel, ret.luac_id, ret.msg })
			end, {
			luac_id = luac_id,
			pos = pos,
			msg = msg,
			channel = channel,
			is_digiline = true
		} }
		)
		return true
	end
end


local safe_globals = {
	"assert", "error", "ipairs", "next", "pairs", "select",
	"tonumber", "tostring", "type", "unpack", "_VERSION"
}



local function create_environment(pos, mem, event, itbl, async_env, send_warning, dynamic_values)
	local env = {
		pos = pos,
		event = event,
		mem = mem,
		heat = async_env.heat,
		heat_max = async_controller_async.settings.overheat_max,
		get_code_events = function()
			return dynamic_values.events
		end,
		get_ram_usage = function()
			return dynamic_values.ram_usage
		end,
		print = get_safe_print(pos, itbl),
		clearterm = get_clearterm(pos, itbl),
		modify_self = get_modify_self(pos, itbl, send_warning),
		interrupt = get_interrupt(pos, itbl, send_warning),
		digiline_send = get_digiline_send(pos, itbl, send_warning, async_env.luac_id),
		string = {
			byte = string.byte,
			char = string.char,
			format = string.format,
			len = string.len,
			lower = string.lower,
			upper = string.upper,
			rep = safe_string_rep,
			reverse = string.reverse,
			sub = string.sub,
			find = safe_string_find,
			split = safe_string_split,
			trim = string.trim -- added
		},
		math = {
			abs = math.abs,
			acos = math.acos,
			asin = math.asin,
			atan = math.atan,
			atan2 = math.atan2,
			ceil = math.ceil,
			cos = math.cos,
			cosh = math.cosh,
			deg = math.deg,
			exp = math.exp,
			floor = math.floor,
			fmod = math.fmod,
			frexp = math.frexp,
			huge = math.huge,
			ldexp = math.ldexp,
			log = math.log,
			log10 = math.log10,
			max = math.max,
			min = math.min,
			modf = math.modf,
			pi = math.pi,
			pow = math.pow,
			rad = math.rad,
			random = math.random,
			sin = math.sin,
			sinh = math.sinh,
			sqrt = math.sqrt,
			tan = math.tan,
			tanh = math.tanh,
			hypot = math.hypot, -- added
			sign = math.sign,  -- added
			factorial = math.factorial, -- added
			round = math.round, -- added


		},
		table = {
			concat = table.concat,
			insert = table.insert,
			maxn = table.maxn,
			remove = table.remove,
			sort = table.sort,
		},
		os = {
			clock = os.clock,
			difftime = os.difftime,
			time = os.time,
			datetable = safe_date,
		},
		conf = table.copy(async_controller_async.settings)
	}
	env._G = env

	for _, name in pairs(safe_globals) do
		env[name] = _G[name]
	end

	if async_controller_async.settings.env_plus then
		async_controller_async.env_plus.apply_env_plus(pos, mem, event, itbl, async_env, env)
	end
	return env
end

async_controller_async.create_environment = create_environment
async_controller_async.clean_and_weigh_digiline_message = clean_and_weigh_digiline_message
