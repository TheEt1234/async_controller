--   ______
--  |
--  |
--  |         __       ___  _   __         _  _
--  |        |  | |\ |  |  |_| |  | |  |  |_ |_|
--  |______  |__| | \|  |  | \ |__| |_ |_ |_ |\
-- Its not micro, its an async here
-- This is a non standard luacontroller, doesn't support ports at all
-- And also forces lightweight interrupts
-- What do you get from all of this?
-- Reference
-- reset_formspec(pos, code, errmsg): installs new code and prints error messages, without resetting LCID
-- reset_meta(pos, code, errmsg): performs a software-reset, installs new code and prints error message
-- run(pos, event): a wrapper for run_inner which gets code & handles errors via reset_meta

-- The Sandbox
-- The whole code of the controller runs in a sandbox,
-- a very restricted environment.
-- Actually the only way to damage the server is to
-- use too much memory from the sandbox.
-- You can add more functions to the environment
-- (see where local env is defined)
-- Something nice to play is is appending minetest.env to it.

local max_digi_messages_per_event = tonumber(minetest.settings:get("async_controller.max_digiline_messages_per_event")) or 150
local BASENAME = "async_controller:controller"



-----------------
-- Overheating --
-----------------
local function burn_controller(pos)
	local node = minetest.get_node(pos)
	node.name = BASENAME.."_burnt"
	minetest.swap_node(pos, node)
	minetest.get_meta(pos):set_string("lc_memory", "");
end

local function overheat(pos)
	if mesecon.do_overheat(pos) then -- This code is responsible for increasing the heat of the luacontroller AND checking if it's overheated, how elegant
		burn_controller(pos)
		return true
	end
end

-------------------------
-- Parsing and running --
-------------------------


local function get_modify_self(pos, itbl, send_warning)
	local hardcoded_max_code_len= 50000
	return function(code)
		if type(code)~="string" then send_warning("Code in modify_self is the wrong type!") return end
		if #code>=hardcoded_max_code_len then send_warning("Code in modify_self is too large!") return end
		table.insert(itbl,{
			function(ret)
				local meta = ret.get_meta(ret.pos)
				ret.reset_formspec(meta,ret.code)
				meta:set_int("luac_id", math.random(1, 65535))
				meta:set_int("has_modified_code",1)
			end,
			{
				pos=pos,code=code
			}
		})
		error("Changing code... (don't worry about it :p)",2)
	end
end

local function get_clearterm(pos, itbl)
	return function()
		table.insert(itbl,{
			function(ret) ret.get_meta(ret.pos):set_string("print","") end,
			{
				pos=pos
			}
		})
	end
end

local function get_safe_print(pos, itbl)
	return function(text_to_print)
		local string_meta = getmetatable("")
		local sandbox = string_meta.__index
		string_meta.__index = string -- Leave string sandbox temporarily
		-- i get why that wasn't sandboxed now... i couldnt do print(_G) because "string.find: 'plain' (fourth parameter) must always be true in a Luacontroller"
		if type(text_to_print)~="string" then 
			text_to_print=dump(text_to_print) -- if ya print too much tables ya time out
		end
		if text_to_print~=nil then
			table.insert(itbl,{
				function(ret)
					local meta = ret.get_meta(ret.pos)
					local oldtext = meta:get_string("print")
					if oldtext==nil then oldtext="" end
					local newtext=string.sub(oldtext.."\n"..ret.text_to_print,-50000,-1) -- https://github.com/mt-mods/mooncontroller/blob/master/controller.lua#L74 this time its 50k chars before ya cant print
					meta:set_string("print",newtext)
				end,{
					text_to_print=text_to_print,
					pos=pos,
				}
			}
		)
		string_meta.__index = sandbox -- Restore string sandbox
		end
	end
end

local function safe_date()
	return(os.date("*t",os.time()))
end

-- string.rep(str, n) with a high value for n can be used to DoS
-- the server. Therefore, limit max. length of generated string.

-- honestly no idea why luacontroller_string_rep_max is a setting
-- ill disrespect it
local function safe_string_rep(str, n)
	if #str * n > 64000 then
		debug.sethook() -- Clear hook
		error("string.rep: string length overflow", 2)
	end

	return string.rep(str, n)
end

-- string.find with a pattern can be used to DoS the server.
-- Therefore, limit string.find to patternless matching.
local function safe_string_find(...)
	if (select(4, ...)) ~= true then
		debug.sethook() -- Clear hook
		error("string.find: 'plain' (fourth parameter) must always be true in a Luacontroller")
	end

	return string.find(...)
end

-- do not allow pattern matching in string.split (see string.find for details)
local function safe_string_split(...)
	if select(5, ...) then
		debug.sethook() -- Clear hook
		error("string.split: 'sep_is_pattern' (fifth parameter) may not be used in a Luacontroller")
	end

	return string.split(...)
end

local function remove_functions(x)
	local tp = type(x)
	if tp == "function" then
		return nil
	end

	-- Make sure to not serialize the same table multiple times, otherwise
	-- writing mem.test = mem in the Luacontroller will lead to infinite recursion
	local seen = {}

	local function rfuncs(x)
		if x == nil then return end
		if seen[x] then return end
		seen[x] = true
		if type(x) ~= "table" then return end

		for key, value in pairs(x) do
			if type(key) == "function" or type(value) == "function" then
				x[key] = nil
			else
				if type(key) == "table" then
					rfuncs(key)
				end
				if type(value) == "table" then
					rfuncs(value)
				end
			end
		end
	end

	rfuncs(x)

	return x
end


-- Force lightweight interrupts
-- yes i know lame but
-- supporting both would be a pain
get_interrupt = function(pos, itbl, send_warning)
	return (function(time, iid)
		if type(time) ~= "number" then error("Delay must be a number") end
		if iid ~= nil then send_warning("Interrupt IDs are disabled on this server") end
		table.insert(itbl, {function(ret) minetest.get_node_timer(ret.pos):start(ret.time) end,{pos=pos,time=time}})
	end)
end


-- Given a message object passed to digiline_send, clean it up into a form
-- which is safe to transmit over the network and compute its "cost" (a very
-- rough estimate of its memory usage).
--
-- The cleaning comprises the following:
-- 1. Functions (and userdata, though user scripts ought not to get hold of
--    those in the first place) are removed, because they break the model of
--    Digilines as a network that carries basic data, and they could exfiltrate
--    references to mutable objects from one Luacontroller to another, allowing
--    inappropriate high-bandwidth, no-wires communication.
-- 2. Tables are duplicated because, being mutable, they could otherwise be
--    modified after the send is complete in order to change what data arrives
--    at the recipient, perhaps in violation of the previous cleaning rule or
--    in violation of the message size limit.
--
-- The cost indication is only approximate; it’s not a perfect measurement of
-- the number of bytes of memory used by the message object.
--
-- Parameters:
-- msg -- the message to clean
-- back_references -- for internal use only; do not provide
--
-- Returns:
-- 1. The cleaned object.
-- 2. The approximate cost of the object.
local function clean_and_weigh_digiline_message(msg, back_references, clean_and_weigh_digiline_message)
	local t = type(msg)
	if t == "string" then
		-- Strings are immutable so can be passed by reference, and cost their
		-- length plus the size of the Lua object header (24 bytes on a 64-bit
		-- platform) plus one byte for the NUL terminator.
		return msg, #msg + 25
	elseif t == "number" and msg == msg then -- Doesn't let NaN thru, this was done because like... nobody checks for nan, and that can lead to pretty funny behaviour, see https://github.com/BuckarooBanzay/digibuilder/issues/20 and 
		-- Numbers are passed by value so need not be touched, and cost 8 bytes
		-- as all numbers in Lua are doubles.
		return msg, 8
	elseif t == "boolean" then
		-- Booleans are passed by value so need not be touched, and cost 1
		-- byte.
		return msg, 1
	elseif t == "table" then
		-- Tables are duplicated. Check if this table has been seen before
		-- (self-referential or shared table); if so, reuse the cleaned value
		-- of the previous occurrence, maintaining table topology and avoiding
		-- infinite recursion, and charge zero bytes for this as the object has
		-- already been counted.
		back_references = back_references or {}
		local bref = back_references[msg]
		if bref then
			return bref, 0
		end
		-- Construct a new table by cleaning all the keys and values and adding
		-- up their costs, plus 8 bytes as a rough estimate of table overhead.
		local cost = 8
		local ret = {}
		back_references[msg] = ret
		for k, v in pairs(msg) do
			local k_cost, v_cost
			k, k_cost = clean_and_weigh_digiline_message(k, back_references, clean_and_weigh_digiline_message)
			v, v_cost = clean_and_weigh_digiline_message(v, back_references, clean_and_weigh_digiline_message)
			if k ~= nil and v ~= nil then
				-- Only include an element if its key and value are of legal
				-- types.
				ret[k] = v
			end
			-- If we only counted the cost of a table element when we actually
			-- used it, we would be vulnerable to the following attack:
			-- 1. Construct a huge table (too large to pass the cost limit).
			-- 2. Insert it somewhere in a table, with a function as a key.
			-- 3. Insert it somewhere in another table, with a number as a key.
			-- 4. The first occurrence doesn’t pay the cost because functions
			--    are stripped and therefore the element is dropped.
			-- 5. The second occurrence doesn’t pay the cost because it’s in
			--    back_references.
			-- By counting the costs regardless of whether the objects will be
			-- included, we avoid this attack; it may overestimate the cost of
			-- some messages, but only those that won’t be delivered intact
			-- anyway because they contain illegal object types.
			cost = cost + k_cost + v_cost
		end
		return ret, cost
	else
		return nil, 0, clean_and_weigh_digiline_message
	end
end

-- itbl: Flat table of functions (or tables) to run after sandbox cleanup, used to prevent various security hazards
local function get_digiline_send(pos, itbl, send_warning, luac_id, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
	return function(channel, msg)
		-- NOTE: This runs within string metatable sandbox, so don't *rely* on anything of the form (""):y
		--        or via anything that could.
		-- Make sure channel is string, number or boolean
		if type(channel) == "string" then
			if #channel > chan_maxlen then
				send_warning("Channel string too long.")
				return false
			end
		elseif (type(channel) ~= "string" and type(channel) ~= "number" and type(channel) ~= "boolean") then
			send_warning("Channel must be string, number or boolean.")
			return false
		end

		local msg_cost
		msg, msg_cost = clean_and_weigh_digiline_message(msg, nil, clean_and_weigh_digiline_message)
		if msg == nil or msg_cost > maxlen then
			send_warning("Message was too complex, or contained invalid data.")
			return false
		end

		table.insert(itbl, {
			function (ret)
				ret.mesecon_queue:add_action(ret.pos, "lc_digiline_relay", {ret.channel, ret.luac_id, ret.msg})
			end,{
				luac_id=luac_id, pos=pos, msg=msg, channel=channel -- mesecon_queue gets automatically provided
				,is_digiline=true
			}}
		)
		return true
	end
end


local safe_globals = {
	-- Don't add pcall/xpcall unless willing to deal with the consequences (unless very careful, incredibly likely to allow killing server indirectly)
	"assert", "error", "ipairs", "next", "pairs", "select",
	"tonumber", "tostring", "type", "unpack", "_VERSION"
}
local more_globals = {
	safe_string_rep = safe_string_rep,
	safe_string_find = safe_string_find,
	safe_string_split = safe_string_split,
	get_safe_print = get_safe_print,
	get_clearterm = get_clearterm,
	get_modify_self = get_modify_self,
	get_code_events = function(v)
		return function() 
			return v.events -- mmm
		end
	end
}

local function create_environment(pos, mem, event, itbl, async_env, send_warning, variables)

	-- Gather variables for the environment
	-- Create new library tables on each call to prevent one Luacontroller
	-- from breaking a library and messing up other Luacontrollers.
	local env = {
		pos = pos,
		event = event,
		mem = mem,
		heat = async_env.heat,
		heat_max = async_env.heat_max,
		code_events_max = async_env.maxevents,
		get_code_events = async_env.more_globals.get_code_events(variables), -- i had to make this a function because uh
		print = async_env.more_globals.get_safe_print(pos, itbl),
		clearterm = async_env.more_globals.get_clearterm(pos, itbl),
		modify_self = async_env.more_globals.get_modify_self(pos, itbl, send_warning),
		interrupt = async_env.get_interrupt(pos, itbl, send_warning, async_env.mesecon_queue),
		digiline_send = async_env.get_digiline_send(pos, itbl, send_warning, async_env.luac_id, async_env.chan_maxlen, async_env.maxlen, async_env.clean_and_weigh_digiline_message),
		string = {
			byte = string.byte,
			char = string.char,
			format = string.format,
			len = string.len,
			lower = string.lower,
			upper = string.upper,
			rep = async_env.more_globals.safe_string_rep,
			reverse = string.reverse,
			sub = string.sub,
			find = async_env.more_globals.safe_string_find,
			split = async_env.more_globals.safe_string_split,
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
	}
	env._G = env

	for _, name in pairs(async_env.safe_globals) do
		env[name] = _G[name]
	end

	return env
end


local function timeout()
	debug.sethook() -- Clear hook
	error("Code timed out!", 2)
end


local function create_sandbox(code, env, maxevents, timeout, variables)
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
	
	if code:byte(1) == 27 then
		return nil, "Binary code prohibited."
	end
	local f, msg = loadstring(code)
	if not f then return nil, msg end
	setfenv(f, env)

	-- Turn off JIT optimization for user code so that count
	-- events are generated when adding debug hooks
	if rawget(_G, "jit") then
		jit.off(f, true)
	end
	local read_only_events = 0 -- luac cant write to this variable
	return function(...)
		-- NOTE: This runs within string metatable sandbox, so the setting's been moved out for safety
		-- Use instruction counter to stop execution
		-- after luacontroller_maxevents
		debug.sethook(
		function(_type)
			read_only_events=read_only_events+1
			if read_only_events >= maxevents then
				timeout()
			else
				variables.events = read_only_events
				-- expose the amount of events executed to luacontroller
				-- useful for benchmarking and like detecting if its about to timeout
			end

		end
		, "", 1)
		local ok, ret = xpcall(f, traceback,...)
		debug.sethook()  -- Clear hook
		if not ok then error(ret, 0) end
		return ret
	end
end


local function load_memory(meta)
	return minetest.deserialize(meta:get_string("lc_memory"), true) or {}
end


local function save_memory(pos, meta, mem)
	local memstring = minetest.serialize(remove_functions(mem))
	local memsize_max = mesecon.setting("luacontroller_memsize", 100000)

	if (#memstring <= memsize_max) then
		meta:set_string("lc_memory", memstring)
		meta:mark_as_private("lc_memory")
	else
		print("Error: Luacontroller memory overflow. "..memsize_max.." bytes available, "
				..#memstring.." required. Controller overheats.")
		burn_controller(pos)
	end
end
local function print_log_formspec(meta)
	local print_log=minetest.formspec_escape(meta:get_string("print")) 
	if print_log==nil then print_log="" end -- why do i have to do all of this to the size.... whatever
	meta:set_string("formspec", "size[15,12]" -- real coordinates size is cursed... so i have to trick the user into believing that the background made the editor formspec bigger
		.."real_coordinates[true]"
		.."style_type[label,textarea;font=mono;bgcolor=black;textcolor=white]"
		.."textarea[0,0;14.9,12;;;"..print_log.."]"
		.."tabheader[0,0;tab;Editor,Print log;2]"
		)
end
local function reset_formspec(meta, code, errmsg)
	local code=code
	local errmsg=errmsg
	if code~=nil then
		meta:set_string("code", code)
		meta:mark_as_private("code")
		code = minetest.formspec_escape(code or "")
		errmsg = minetest.formspec_escape(tostring(errmsg or ""))
	else
		-- used when switching tabs
		code=minetest.formspec_escape(meta:get_string("code") or "")
		errmsg=""
	end
	local state=meta:get_string("state")
	if state=="editor" or state==nil or state=="" then
		meta:set_string("formspec", "size[12,10]"
			.."style_type[label,textarea;font=mono]"
			.."background[-0.2,-0.25;12.4,10.75;jeija_luac_background.png]"
			.."label[0.1,8.3;"..errmsg.."]"
			.."textarea[0.2,0.2;12.2,9.5;code;;"..code.."]"
			.."image_button[4.75,8.75;2.5,1;jeija_luac_runbutton.png;program;]"
			.."image_button_exit[11.72,-0.25;0.425,0.4;jeija_close_window.png;exit;]"
			.."tabheader[0,0;tab;Editor,Print log;1]"
		)
	elseif state=="print_log" then
		print_log_formspec(meta)
	end
end

local function reset_meta(pos, code, errmsg)
	local meta = minetest.get_meta(pos)
	reset_formspec(meta, code, errmsg)
	meta:set_int("luac_id", math.random(1, 65535))
	meta:set_string("print","")
end
local function run_async(pos, mem, event, code, async_env) -- this is the thing that executes it, has async enviroment
	async_env.variables = {
		events = 0
	}
	
	
	-- 'Last warning' label.
	local warning = ""
	local function send_warning(str)
		warning = "Warning: " .. str
	end

	local itbl = {}
	local start_time=minetest.get_us_time()
	local env = async_env.create_environment(pos, mem, event, itbl, async_env, send_warning, async_env.variables)
	if not env then return false, "Env does not exist. Controller has been moved?", mem, pos, itbl, {start_time, minetest.get_us_time()} end

	local success, msg
	-- Create the sandbox and execute code
	local f
	f, msg = async_env.create_sandbox(code, env, async_env.maxevents, async_env.timeout, async_env.variables)
	if not f then return false, msg, env.mem, pos, itbl, {start_time, minetest.get_us_time()} end
	-- Start string true sandboxing
	local onetruestring = getmetatable("")
	-- If a string sandbox is already up yet inconsistent, something is very wrong
	assert(onetruestring.__index == string)
	onetruestring.__index = env.string
	success, msg = pcall(f)
	onetruestring.__index = string
	local end_time=minetest.get_us_time()
	-- End string true sandboxing
	if not success then return false, msg, env.mem, pos, itbl, {start_time, end_time}  end
	return false,  warning, env.mem, pos, itbl, {start_time, end_time}
end

local function run_callback(ok, errmsg, mem, pos, itbl, time) -- this is the thing that gets called AFTER the luac executes
	local meta = minetest.get_meta(pos)
	local code = meta:get_string("code")
	local time_took = math.abs(time[1]-time[2])
	local digiline_sends=0
	if not ok and itbl ~= nil then
		-- Execute deferred tasks
		for _, v in ipairs(itbl) do
			if type(v)~="table" then
				local failure = v()
				if failure then
					ok=false
					errmsg=failure
				end
			else
				local func = v[1]
				local args = v[2]
				if args.is_digiline then
					digiline_sends=digiline_sends+1
				end
				if args.is_digiline==false or digiline_sends<=max_digi_messages_per_event then
					args.mesecon_queue=mesecon.queue
					args.get_meta=minetest.get_meta
					args.reset_formspec=reset_formspec
					local failure = func(args)
					if failure then
						ok=false
						errmsg=failure
					end
				end
			end
		end
		ok=true
		errmsg=errmsg
	end
	if errmsg~=nil and errmsg~="" then
		if type(errmsg)~="string" then errmsg=dump(errmsg) end
		local meta = minetest.get_meta(pos)
		local oldtext = meta:get_string("print")
		if oldtext==nil then oldtext="" end
		local newtext=string.sub(oldtext.."\nErr: "..errmsg,-50000,-1) -- https://github.com/mt-mods/mooncontroller/blob/master/controller.lua#L74 this time its 50k chars before ya cant print
		meta:set_string("print",newtext)
	end
	if meta:get_int("has_modified_code")==0 or meta:get_int("has_modified_code")==nil then
		if not ok then
			reset_meta(pos, code, errmsg)
		else
			reset_formspec(meta, code, errmsg)
		end
	else
		meta:set_int("has_modified_code",0)
	end
	save_memory(pos, minetest.get_meta(pos), mem)
end


local function run_inner(pos, code, event) -- this is the thing that gets called BEFORE it executes
	local meta = minetest.get_meta(pos)
	-- Note: These return success, presumably to avoid changing LC ID.
	if overheat(pos) then return true, "" end

	-- Load mem from meta
	local mem  = load_memory(meta)

	local heat = mesecon.get_heat(pos)
	local maxevents = tonumber(minetest.settings:get("async_controller.maxevents"))
	if maxevents==nil then
		-- *10 to make it not sneaky
		-- the reason this was done is because it doesn't freeze the main game
		maxevents=10000*10
	end

	local luac_id = meta:get_int("luac_id")
	local chan_maxlen = mesecon.setting("luacontroller_digiline_channel_maxlen", 256)
	local maxlen = mesecon.setting("luacontroller_digiline_maxlen", 50000)
	-- Async hell begins

	local async_env = {
		create_environment=create_environment,heat=heat, heat_max=mesecon.setting("overheat_max", 20),
		get_interrupt=get_interrupt, get_digiline_send=get_digiline_send, safe_globals=safe_globals,
		create_sandbox=create_sandbox, maxevents=maxevents, timeout=timeout, luac_id=luac_id,
		more_globals=more_globals,chan_maxlen=chan_maxlen, maxlen=maxlen,
		clean_and_weigh_digiline_message=clean_and_weigh_digiline_message,
	}

	minetest.handle_async(run_async,run_callback, pos, mem, event, code, async_env)
end


-- run_inner = run basically
local function run(pos, event)
	local meta = minetest.get_meta(pos)
	local code = meta:get_string("code")
	run_inner(pos, code, event)
end

local function node_timer(pos)
	if minetest.registered_nodes[minetest.get_node(pos).name].is_burnt then
		return false
	end
	run(pos, {type="interrupt"})
	return false
end

-----------------------
-- A.Queue callbacks --
-----------------------

mesecon.queue:add_function("lc_interrupt", function (pos, luac_id, iid)
	-- There is no luacontroller anymore / it has been reprogrammed / replaced / burnt
	if (minetest.get_meta(pos):get_int("luac_id") ~= luac_id) then return end
	if (minetest.registered_nodes[minetest.get_node(pos).name].is_burnt) then return end
	run(pos, {type="interrupt", iid = iid})
end)

mesecon.queue:add_function("lc_digiline_relay", function (pos, channel, luac_id, msg)
	if not digiline then return end
	-- This check is only really necessary because in case of server crash, old actions can be thrown into the future
	if (minetest.get_meta(pos):get_int("luac_id") ~= luac_id) then return end
	if (minetest.registered_nodes[minetest.get_node(pos).name].is_burnt) then return end
	-- The actual work
	digiline:receptor_send(pos, digiline.rules.default, channel, msg)
end)

-----------------------
-- Node Registration --
-----------------------

local node_box = {
	type = "fixed",
	fixed = {
		{-8/16, -8/16, -8/16, 8/16, -7/16, 8/16}, -- Bottom slab
		{-5/16, -7/16, -5/16, 5/16, -6/16, 5/16}, -- Circuit board
		{-3/16, -6/16, -3/16, 3/16, -5/16, 3/16}, -- IC
	}
}

local selection_box = {
	type = "fixed",
	fixed = { -8/16, -8/16, -8/16, 8/16, -5/16, 8/16 },
}

local digiline = {
	receptor = {},
	effector = {
		action = function(pos, _, channel, msg)
			msg = clean_and_weigh_digiline_message(msg, nil, clean_and_weigh_digiline_message)
			run(pos, {type = "digiline", channel = channel, msg = msg})
		end
	}
}

local function get_program(pos)
	local meta = minetest.get_meta(pos)
	return meta:get_string("code")
end

local function set_program(pos, code)
	
	reset_meta(pos, code)

	if minetest.get_node(pos).name==BASENAME then 
		run(pos, {type="program"})
	elseif minetest.get_node(pos).name==BASENAME.."_burnt" then
		minetest.swap_node(pos, {name=BASENAME})
		run(pos, {type="program"})
	end
end

local function on_receive_fields(pos, _, fields, sender)
	local name = sender:get_player_name()
	if minetest.is_protected(pos, name) and not minetest.check_player_privs(name, {protection_bypass=true}) then
		minetest.record_protection_violation(pos, name)
		return
	end
	local meta=minetest.get_meta(pos)
	if fields.program then
		set_program(pos, fields.code)
	elseif fields.tab then
		if fields.tab=="1" then
			meta:set_string("state","editor")
			reset_formspec(meta, nil, nil)
		elseif fields.tab=="2" then
			meta:set_string("state","print_log")
			print_log_formspec(meta)
		end
	else
		return
	end
end

-- Node registration
local node_name = BASENAME

local mesecons = {
	luacontroller = {
		get_program = get_program,
		set_program = set_program,
	},
}

minetest.register_node(node_name, {
	description = "Async Controller",
	drawtype = "nodebox",
	tiles = {
		"async_controller_top.png",
		"jeija_microcontroller_bottom.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png"
	},
	inventory_image = "async_controller_top.png",
	paramtype = "light",
	is_ground_content = false,
	groups = {dig_immediate=2, overheat = 1},
	drop = BASENAME,
	sunlight_propagates = true,
	selection_box = selection_box,
	node_box = node_box,
	on_construct = reset_meta,
	on_receive_fields = on_receive_fields,
	sounds = mesecon.node_sound.stone,
	mesecons = mesecons,
	digiline = digiline,
	is_luacontroller = true,
	on_timer = node_timer,
	on_blast = mesecon.on_blastnode,
})

------------------------------
-- Overheated Luacontroller --
------------------------------

minetest.register_node(BASENAME .. "_burnt", {
	drawtype = "nodebox",
	tiles = {
		"async_controller_burnt_top.png",
		"jeija_microcontroller_bottom.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png",
		"jeija_microcontroller_sides.png"
	},
	description = "Burnt async controller (you hacker you!)",
	inventory_image = "async_controller_burnt_top.png",
	is_burnt = true,
	paramtype = "light",
	is_ground_content = false,
	groups = {dig_immediate=2, not_in_creative_inventory=1},
	drop = BASENAME,
	sunlight_propagates = true,
	selection_box = selection_box,
	node_box = node_box,
	on_construct = reset_meta,
	on_receive_fields = on_receive_fields,
	sounds = mesecon.node_sound.stone,
	on_blast = mesecon.on_blastnode,
})

------------------------
-- Craft Registration --
------------------------
local wire = "digilines:wire_std_00000000"
minetest.register_craft({
	output = BASENAME.." 2",
	recipe = {
		{'mesecons_materials:silicon', 'mesecons_materials:silicon', wire},
		{'mesecons_materials:silicon', 'mesecons_materials:silicon', wire},
		{wire, wire, ''},
	}
})

----------------------------------------
-- Register suppport for  fancy tools --
----------------------------------------
if metatool then
	MP = minetest.get_modpath("async_controller")
	dofile(MP.."/tool.lua")
end