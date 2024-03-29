local BASENAME = "async_controller:controller"
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

local function remove_functions(x)
	local tp = type(x)
	if tp == "function" then
		return nil
	end
	-- Make sure to not serialize the same table multiple times, otherwise
	-- writing mem.test = mem in the Luacontroller will lead to infinite recursion
	local seen = {}
	local someone_is_abusing_the_serializer = false 
	local function rfuncs(x)
		if x == nil then return end
		if seen[x] then 
			someone_is_abusing_the_serializer = true
			return
		end
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
	if not someone_is_abusing_the_serializer then
		return x
	else
		return {"no weird tables :/"}
	end
end




local function load_memory(meta)
	return minetest.deserialize(meta:get_string("lc_memory"), true) or {}
end


local function save_memory(pos, meta, mem)
	-- local memstring = minetest.serialize(remove_functions(mem))
	local memstring = minetest.serialize(mem) -- mem gets actually serialized and deserialized before this, so uh yeah we are also removing functions in run_async to prevent segfault
	local memsize_max = async_controller.env.settings.memsize

	if (#memstring <= memsize_max) then
		meta:set_string("lc_memory", memstring)
		meta:mark_as_private("lc_memory")
	else
		print("Error: Luacontroller memory overflow. "..memsize_max.." bytes available, "
				..#memstring.." required. Controller overheats.")
		burn_controller(pos)
	end
end

async_controller.env.burn_controller=burn_controller
async_controller.env.overheat=overheat
async_controller.env.remove_functions=remove_functions
async_controller.env.save_memory=save_memory
async_controller.env.load_memory=load_memory