 -- This is a non standard luacontroller, doesn't support ports at all
-- And also forces lightweight interrupts


local max_digi_messages_per_event = tonumber(minetest.settings:get("async_controller.max_digiline_messages_per_event")) or 150
local BASENAME = "async_controller:controller"

async_controller = {
	env={}
	-- does this mean that some mod can just mess with the insides of async_controller?
	-- YES and i would love if someone actually attempted that....

	-- does this aproach make the code confusing?
	-- yes

}

local MP = minetest.get_modpath("async_controller")

dofile(MP.."/env.lua")
dofile(MP.."/sandbox.lua")
dofile(MP.."/misc.lua")
dofile(MP.."/frontend.lua")
local function reset_meta(pos, code, errmsg)
	local meta = minetest.get_meta(pos)
	async_controller.env.reset_formspec(meta, code, errmsg)
	meta:set_int("luac_id", math.random(1, 65535))
	meta:set_string("print","")
end


local function run_async(pos, mem, event, code, async_env) -- this is the thing that executes it, has async enviroment
	async_env.luacontroller_dynamic_values = {
		events = 0
	}
	
	
	-- 'Last warning' label.
	local warning = ""
	local function send_warning(str)
		warning = "Warning: " .. str
	end

	local itbl = {}
	local start_time=minetest.get_us_time()
	local env = async_env.create_environment(pos, mem, event, itbl, async_env, async_env.create_environment_imports, send_warning, async_env.luacontroller_dynamic_values)
	if not env then return false, "Env does not exist. Controller has been moved?", mem, pos, itbl, {start_time, minetest.get_us_time()} end

	local success, msg
	-- Create the sandbox and execute code
	local f
	f, msg = async_env.create_sandbox(code, env, async_env.maxevents, async_env.luacontroller_dynamic_values)
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
					args.reset_formspec=async_controller.env.reset_formspec
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
			async_controller.env.reset_formspec(meta, code, errmsg)
		end
	else
		meta:set_int("has_modified_code",0)
	end
	async_controller.env.save_memory(pos, minetest.get_meta(pos), mem)
end


local function run_inner(pos, code, event) -- this is the thing that gets called BEFORE it executes
	local meta = minetest.get_meta(pos)
	-- Note: These return success, presumably to avoid changing LC ID.
	if async_controller.env.overheat(pos) then return true, "" end

	-- Load mem from meta
	local mem  = async_controller.env.load_memory(meta)

	local heat = mesecon.get_heat(pos)
	local maxevents = tonumber(minetest.settings:get("async_controller.maxevents")) or (10000*10)

	local luac_id = meta:get_int("luac_id")
	local chan_maxlen = mesecon.setting("luacontroller_digiline_channel_maxlen", 256)
	local maxlen = mesecon.setting("luacontroller_digiline_maxlen", 50000)
	-- Async hell begins

	--[[
	local async_env = {
		create_environment=create_environment,heat=heat, heat_max=mesecon.setting("overheat_max", 20),
		get_interrupt=get_interrupt, get_digiline_send=get_digiline_send, safe_globals=safe_globals,
		create_sandbox=create_sandbox, maxevents=maxevents, timeout=timeout, luac_id=luac_id,
		more_globals=more_globals,chan_maxlen=chan_maxlen, maxlen=maxlen,
		clean_and_weigh_digiline_message=clean_and_weigh_digiline_message,
	}
	--]]

	local async_env = async_controller.env
	async_env.heat = heat
	async_env.heat_max=mesecon.setting("overheat_max",20)
	async_env.maxevents = maxevents
	async_env.luac_id = luac_id
	async_env.maxlen = maxlen
	async_env.chan_maxlen = chan_maxlen

	minetest.handle_async(run_async,run_callback, pos, mem, event, code, async_env)
end


-- run_inner = run basically
local function run(pos, event)
	local meta = minetest.get_meta(pos)
	local code = meta:get_string("code")
	run_inner(pos, code, event)
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

async_controller.env.run = run
async_controller.env.set_program = set_program

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
			msg = async_controller.env.clean_and_weigh_digiline_message(msg, nil, async_controller.env.clean_and_weigh_digiline_message)
			run(pos, {type = "digiline", channel = channel, msg = msg})
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
	groups = {dig_immediate=2, overheat = 1},
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
	description = "Burnt async controller (you hacker you!)\n(ok but seriously if you got this your server has an issue.....)",
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
local silicon = "mesecons_materials:silicon"
minetest.register_craft({
	output = BASENAME,
	recipe = {
		{silicon, silicon, wire},
		{silicon, silicon, wire},
		{wire,    wire,    ''  },
	}
})


-- Register a fancy tool because luatool doesnt allow me to add support
if metatool ~= nil then
	dofile(MP.."/metatool.lua")
end