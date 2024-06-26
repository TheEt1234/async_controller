-- This is a non standard luacontroller (i guess), doesn't support ports at all
-- And also forces lightweight interrupts



local BASENAME = "async_controller:controller"

local function setting_or_default(setting, default, if_zero)
	local s = minetest.settings:get(setting)
	if tonumber(s) ~= nil then
		s = tonumber(s)
	end
	if s == 0 and if_zero ~= nil then
		return if_zero
	else
		return s or default
	end
end

async_controller = {
	env = {
		settings = {
			channel_maxlen = mesecon.setting("luacontroller_digiline_channel_maxlen", 256),
			message_maxlen = mesecon.setting("luacontroller_digiline_maxlen", 50000),
			memsize = mesecon.setting("luacontroller_memsize", 100000),
			overheat_max = mesecon.setting("overheat_max", 20),
			max_digilines_messages_per_event = setting_or_default("async_controller.max_digiline_messages_per_event", 150),
			maxevents = setting_or_default("async_controller.maxevents", 10000 * 10, math.huge),         -- setting to zero will disable maxevents ratelimiting, imo kinda useless
			execution_time_limit = setting_or_default("async_controller.execution_time_limit", 10000, math.huge), -- setting to zero will disable this ratelimiting
			hook_time = setting_or_default("async_controller.hook_time", 10),
			modify_self_max_code_len = setting_or_default("async_controller.modify_self_max_code_len", 50000),
			max_sandbox_mem_size = setting_or_default("async_controller.max_sandbox_mem_size", 50, math.huge),
			env_plus = setting_or_default("async_controller.env_plus", true),
			debug_mode = false,     -- console spammer
		},
		custom_callback = function() end, -- for use with other mods
	}
}

local function pass_down_to_async(thing, name)
	minetest.handle_async(function(thing, name)
		if not rawget(_G, "async_controller_async") then async_controller_async = {} end -- we use rawget here or minetest would warn us because undefined global
		async_controller_async[name] = thing
	end, function() end, thing, name)
end

pass_down_to_async(async_controller.env.settings, "settings")

local MP = minetest.get_modpath("async_controller")

minetest.register_async_dofile(MP .. "/async_init.lua")
minetest.register_async_dofile(MP .. "/env_plus.lua")
minetest.register_async_dofile(MP .. "/env.lua")
minetest.register_async_dofile(MP .. "/sandbox.lua")
dofile(MP .. "/misc.lua") -- both of theese don't talk with the async environment, well except remove_functions but whatever
dofile(MP .. "/frontend.lua")


local function reset_meta(pos, code, errmsg)
	local meta = minetest.get_meta(pos)
	async_controller.env.reset_formspec(meta, code, errmsg)
	meta:set_int("luac_id", math.random(1, 65535))
end


local function run_async(pos, mem, event, code, async_env) -- this is the thing that executes it, has async enviroment
	async_env.luacontroller_dynamic_values = {
		events = 0,
		ram_usage = 0
	}

	-- we have to rfuncs mem here btw because minetest.serialize(string.sub) => crash
	-- and minetest for some reason serializes everything that goes to/from the async environment (why why)

	-- 'Last warning' label.
	local warning = ""
	local function send_warning(str)
		warning = "Warning: " .. str
	end

	local time = minetest.get_us_time
	local rfuncs = async_env.remove_functions

	local itbl = {}
	local start_time = time()
	local env = async_controller_async.create_environment(pos, mem, event, itbl, async_env, send_warning,
		async_env.luacontroller_dynamic_values)
	if not env then
		return false, "Env does not exist. Controller has been moved?", rfuncs(mem), pos,
			itbl, { start_time, time() }
	end


	-- Create the sandbox and execute code

	local f, msg = async_controller_async.create_sandbox(code, env, async_env, async_env.luacontroller_dynamic_values)
	if not f then
		return false, msg, rfuncs(env.mem), pos, itbl, { start_time, time() }
	end

	-- Start string true sandboxing
	local onetruestring = getmetatable("")

	-- If a string sandbox is already up yet inconsistent, something is very wrong
	assert(onetruestring.__index == string, "Something went horribly wrong with the string sandboxing")

	onetruestring.__index = env.string

	local success, msg = pcall(f)
	onetruestring.__index = string
	-- End string true sandboxing

	return success, msg or warning, rfuncs(env.mem), pos, itbl, { start_time, time() }
end

local function exec_itbl(itbl)
	local ok, errmsg

	local digiline_sends = 0
	for _, v in ipairs(itbl) do
		if type(v) == "function" then
			local failure = v()
			if failure then
				ok = false
				errmsg = failure
				break
			end
		elseif type(v) == "table" then
			local func = v[1]
			local args = v[2]
			if args.is_digiline then
				digiline_sends = digiline_sends + 1
			end

			if digiline_sends >= async_controller.env.settings.max_digilines_messages_per_event then
				errmsg = "Warning: You've sent too many digilines messages in an event, only sending " ..
					async_controller.env.settings.max_digilines_messages_per_event
			end

			if args.is_digiline == false or digiline_sends <= async_controller.env.settings.max_digilines_messages_per_event then
				args.mesecon_queue = mesecon.queue
				args.get_meta = minetest.get_meta
				args.reset_formspec = async_controller.env.reset_formspec
				local failure = func(args)
				if failure then
					ok = false
					errmsg = failure
					break
				end
			end
		end
	end

	return ok, errmsg
end

local function run_callback(ok, errmsg, mem, pos, itbl, time) -- this is the thing that gets called AFTER the luac executes
	local meta = minetest.get_meta(pos)
	local code = meta:get_string("code")
	local time_took = math.abs(time[1] - time[2])

	local callback_time = minetest.get_us_time()

	if itbl ~= nil then
		-- Execute deferred tasks
		local new_ok, new_errmsg = exec_itbl(itbl)

		if ok == true and new_ok == false then
			ok = false
		end

		if errmsg == "" and not (new_errmsg == "" or new_errmsg == nil) and type(errmsg) == "string" then
			errmsg = new_errmsg
		end
	end

	if errmsg ~= nil and errmsg ~= "" then
		local errmsg = tostring(errmsg)
		local meta = minetest.get_meta(pos)
		local oldtext = meta:get_string("print") or " "
		local newtext = string.sub(oldtext .. "\nErr: " .. errmsg, -100000, -1) -- https://github.com/mt-mods/mooncontroller/blob/master/controller.lua#L74
		meta:set_string("print", newtext)
	end


	if meta:get_int("has_modified_code") == 0 or meta:get_int("has_modified_code") == nil then
		if not ok then
			reset_meta(pos, code, errmsg)
		else
			async_controller.env.reset_formspec(meta, code, errmsg)
		end
	else
		meta:set_int("has_modified_code", 0)
	end

	-- TODO: run under some sort of ratelimiter
	async_controller.env.save_memory(pos, minetest.get_meta(pos), mem)

	if async_controller.env.settings.debug_mode then
		minetest.log("action", "[async_controller] <async> Executed sandbox of async_controller at " ..
			minetest.pos_to_string(pos) ..
			", time took: " ..
			time_took / 1000 .. "ms + <sync> callback took " .. (minetest.get_us_time() - callback_time) / 1000 .. "ms")
	end

	async_controller.env.custom_callback(ok, errmsg, mem, pos, itbl, time)
end


local function run_inner(pos, code, event) -- this is the thing that gets called BEFORE it executes
	local meta = minetest.get_meta(pos)
	-- Note: These return success, presumably to avoid changing LC ID.
	if async_controller.env.overheat(pos) then return true, "" end

	-- Load mem from meta
	local mem         = async_controller.env.load_memory(meta)
	local heat        = mesecon.get_heat(pos)
	local luac_id     = meta:get_int("luac_id")
	local async_env   = async_controller.env
	async_env.heat    = heat
	async_env.luac_id = luac_id
	async_env.code    = code
	minetest.handle_async(run_async, run_callback, pos, mem, event, code, async_env)
end


-- run_inner = run basically
local function run(pos, event)
	local meta = minetest.get_meta(pos)
	local code = meta:get_string("code")
	run_inner(pos, code, event)
end


local function set_program(pos, code)
	minetest.get_meta(pos):set_string("print", "")
	reset_meta(pos, code)

	if minetest.get_node(pos).name == BASENAME then
		run(pos, { type = "program" })
	elseif minetest.get_node(pos).name == BASENAME .. "_burnt" then
		minetest.swap_node(pos, { name = BASENAME })
		run(pos, { type = "program" })
	end
end

async_controller.env.run = run
async_controller.env.set_program = set_program

local function node_timer(pos)
	if minetest.registered_nodes[minetest.get_node(pos).name].is_burnt then
		return false
	end
	run(pos, { type = "interrupt" })
	return false
end

-----------------------
-- A.Queue callbacks --
-----------------------

mesecon.queue:add_function("lc_digiline_relay", function(pos, channel, luac_id, msg)
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
		{ -8 / 16, -8 / 16, -8 / 16, 8 / 16, -7 / 16, 8 / 16 }, -- Bottom slab
		{ -5 / 16, -7 / 16, -5 / 16, 5 / 16, -6 / 16, 5 / 16 }, -- Circuit board
		{ -3 / 16, -6 / 16, -3 / 16, 3 / 16, -5 / 16, 3 / 16 }, -- IC
	}
}

local selection_box = {
	type = "fixed",
	fixed = { -8 / 16, -8 / 16, -8 / 16, 8 / 16, -5 / 16, 8 / 16 },
}

local function clean_and_weigh_digiline_message(msg, back_references) -- duplicated code, deal with it
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

local digiline = {
	receptor = {},
	effector = {
		action = function(pos, _, channel, msg)
			msg = clean_and_weigh_digiline_message(msg)
			run(pos, { type = "digiline", channel = channel, msg = msg })
		end
	}
}

local function get_program(pos)
	local meta = minetest.get_meta(pos)
	return meta:get_string("code")
end




local mesecons = {
	luacontroller = {
		get_program = get_program,
		set_program = async_controller.env.set_program,
	},
}

minetest.register_node(BASENAME, {
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
	groups = { dig_immediate = 2, overheat = 1 },
	drop = BASENAME,
	sunlight_propagates = true,
	selection_box = selection_box,
	node_box = node_box,
	on_construct = reset_meta,
	on_receive_fields = async_controller.env.on_receive_fields,
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
	description =
	"Burnt async controller (you hacker you!)\n(ok but seriously if you got this your server has an issue.....)",
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
	groups = { dig_immediate = 2, not_in_creative_inventory = 1 },
	drop = BASENAME,
	sunlight_propagates = true,
	selection_box = selection_box,
	node_box = node_box,
	on_construct = reset_meta,
	on_receive_fields = async_controller.env.on_receive_fields,
	sounds = mesecon.node_sound.stone,
	on_blast = mesecon.on_blastnode,
})

------------------------
-- Craft Registration --
------------------------

local luac = "mesecons_luacontroller:luacontroller0000"
local copp = "default:copperblock"
local heat = "digistuff:heatsink"
minetest.register_craft({
	output = BASENAME,
	recipe = {
		{ copp, heat, copp },
		{ luac, luac, luac },
		{ luac, luac, luac },
	}
})

if metatool ~= nil then
	dofile(MP .. "/metatool.lua")
end
