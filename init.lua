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
-- 	NO server lag compared to the luacontroller
-- 	10x more timeout "resistance"
-- 	And no ratelimits will work here :p (the async controller doesn't freeze the server, so there's nothing to ratelimit really)
-- also adds pos to the enviroment WHY WASN'T IT THERE ALREADY

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


local S = minetest.get_translator(minetest.get_current_modname())

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
	if mesecon.do_overheat(pos) then -- If too hot
		burn_controller(pos)
		return true
	end
end

-------------------------
-- Parsing and running --
-------------------------
local safe_print
if mesecon.setting("luacontroller_print_behavior", "log")=="log" then
	function safe_print(param)
		local string_meta = getmetatable("")
		local sandbox = string_meta.__index
		string_meta.__index = string -- Leave string sandbox temporarily
		minetest.log("action", string.format("[async_controller] print(%s)", dump(param)))
		string_meta.__index = sandbox -- Restore string sandbox
		return true
	end
else
	function safe_print(_) return false end
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
	elseif t == "number" then
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
		return nil, 0
	end
end


-- itbl: Flat table of functions to run after sandbox cleanup, used to prevent various security hazards
local function get_digiline_send(pos, itbl, send_warning, luac_id_prov, mesecon_queue, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
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
					-- Runs outside of string metatable sandbox
					ret.mesecon_queue:add_action(ret.pos, "lc_digiline_relay", {ret.channel, ret.luac_id, ret.msg})
				end
			,{
				luac_id=luac_id_prov,mesecon_queue=mesecon_queue,pos=pos,
				msg=msg,channel=channel,	
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
	safe_print = safe_print,
}

local function create_environment(pos, mem, event, itbl, send_warning, heat, heat_max, get_interrupt, get_digiline_send, safe_globals, luac_id, mesecon_queue, more_globals, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
	-- Gather variables for the environment
	-- Create new library tables on each call to prevent one Luacontroller
	-- from breaking a library and messing up other Luacontrollers.
	local env = {
		pos = pos,
		event = event,
		mem = mem,
		heat = heat,
		heat_max = heat_max,
		print = more_globals.safe_print,
		interrupt = get_interrupt(pos, itbl, send_warning, mesecon_queue),
		digiline_send = get_digiline_send(pos, itbl, send_warning, luac_id, mesecon_queue, chan_maxlen, maxlen, clean_and_weigh_digiline_message),
		string = {
			byte = string.byte,
			char = string.char,
			format = string.format,
			len = string.len,
			lower = string.lower,
			upper = string.upper,
			rep = more_globals.safe_string_rep,
			reverse = string.reverse,
			sub = string.sub,
			find = more_globals.safe_string_find,
			split = more_globals.safe_string_split,
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

	for _, name in pairs(safe_globals) do
		env[name] = _G[name]
	end

	return env
end


local function timeout()
	debug.sethook() -- Clear hook
	error("Code timed out!", 2)
end


local function create_sandbox(code, env, maxevents, timeout)
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

	return function(...)
		-- NOTE: This runs within string metatable sandbox, so the setting's been moved out for safety
		-- Use instruction counter to stop execution
		-- after luacontroller_maxevents
		debug.sethook(timeout, "", maxevents)
		local ok, ret = pcall(f, ...)
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

local function reset_formspec(meta, code, errmsg, pos)
	local meta = meta
	if meta==nil then meta=minetest.get_meta(pos) end
	meta:set_string("code", code)
	meta:mark_as_private("code")
	code = minetest.formspec_escape(code or "")
	errmsg = minetest.formspec_escape(tostring(errmsg or ""))
	meta:set_string("formspec", "size[12,10]"
		.."style_type[label,textarea;font=mono]"
		.."background[-0.2,-0.25;12.4,10.75;jeija_luac_background.png]"
		.."label[0.1,8.3;"..errmsg.."]"
		.."textarea[0.2,0.2;12.2,9.5;code;;"..code.."]"
		.."image_button[4.75,8.75;2.5,1;jeija_luac_runbutton.png;program;]"
		.."image_button_exit[11.72,-0.25;0.425,0.4;jeija_close_window.png;exit;]"
		)
end

local function reset_meta(pos, code, errmsg)
	local meta = minetest.get_meta(pos)
	reset_formspec(meta, code, errmsg)
	meta:set_int("luac_id", math.random(1, 65535))
end


-- Returns NOTHIINGGG yes this did break like one useless feature that logged errors into the console
-- run (as opposed to run_inner) is responsible for setting up meta according to this output
	-- thats a lie, it's responsible for... oh god... don't look below 
local function run_inner(pos, code, event)
	local meta = minetest.get_meta(pos)
	-- Note: These return success, presumably to avoid changing LC ID.
	if overheat(pos) then return true, "" end

	-- Load mem from meta
	local mem  = load_memory(meta)

	-- 'Last warning' label.
	local warning = ""
	local function send_warning(str)
		warning = "Warning: " .. str
	end
	local heat = mesecon.get_heat(pos)
	local maxevents= mesecon.setting("async_controller_maxevents", 10000*10) 
	-- *10 to make it not sneaky, the reason this was done is because it doesn't freeze the main game
	local luac_id = minetest.get_meta(pos):get_int("luac_id")
	local chan_maxlen = mesecon.setting("luacontroller_digiline_channel_maxlen", 256)
	local maxlen = mesecon.setting("luacontroller_digiline_maxlen", 50000)
	-- Async hell begins
	-- Ignore the function arguments, add more if needed
	minetest.handle_async(function(pos, mem, event, code, create_environment, heat, heat_max, get_interrupt, get_digiline_send, safe_globals, create_sandbox, maxevents, timeout, luac_id, mesecon_queue, more_globals, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
		local itbl = {}
		local env = create_environment(pos, mem, event, itbl, send_warning, heat, heat_max, get_interrupt, get_digiline_send, safe_globals, luac_id, mesecon_queue, more_globals, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
		if not env then return false, "Env does not exist. Controller has been moved?", mem ,pos end

		local success, msg
		-- Create the sandbox and execute code
		local f
		f, msg = create_sandbox(code, env, maxevents, timeout)
		if not f then return false, msg, env.mem, pos end
		-- Start string true sandboxing
		local onetruestring = getmetatable("")
		-- If a string sandbox is already up yet inconsistent, something is very wrong
		assert(onetruestring.__index == string)
		onetruestring.__index = env.string
		success, msg = pcall(f)
		onetruestring.__index = string
		-- End string true sandboxing
		if not success then return false, msg, env.mem, pos end
		return false, "", env.mem, pos, itbl
	end,function(ok,errmsg,mem, pos, itbl)
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
					v[2].mesecon_queue=mesecon.queue
					local failure = v[1](v[2])
					if failure then
						ok=false
						errmsg=failure
					end
				end
			end
			ok=true 
			errmsg=warning
		end
		if not ok then
			reset_meta(pos, code, errmsg)
		else
			reset_formspec(nil,code, errmsg, pos)
		end
		save_memory(pos, meta, mem)
	end,pos,mem,event,code, create_environment, heat, mesecon.setting("overheat_max", 20),get_interrupt, get_digiline_send, safe_globals, create_sandbox, maxevents, timeout, luac_id, mesecon.queue, more_globals, chan_maxlen, maxlen, clean_and_weigh_digiline_message)
end



-- literally run_inner now, no you won't get the values back this is async :p
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
			msg = clean_and_weigh_digiline_message(msg)
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
	return run(pos, {type="program"})
end

local function on_receive_fields(pos, _, fields, sender)
	if not fields.program then
		return
	end
	local name = sender:get_player_name()
	if minetest.is_protected(pos, name) and not minetest.check_player_privs(name, {protection_bypass=true}) then
		minetest.record_protection_violation(pos, name)
		return
	end
	set_program(pos, fields.code)
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
	description = S("Async Controller"),
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
