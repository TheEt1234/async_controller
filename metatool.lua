-- adds async luac support to luatool
-- edit: crap i can't... well... a new metatool doesn't hurt!
local recipe = {
	{ '', '', 'default:mese_crystal' },
	{ '', 'async_controller:controller', '' },
	{ 'default:obsidian_shard', '', '' }
}

--luacheck: ignore unused argument player node
local tool = metatool:register_tool('async_luatool', {
	description = 'Async Luatool',
	name = 'Async LuaTool',
	texture = 'luatool_wand.png^[colorize:blue:100',
	recipe = recipe,
	settings = {
		machine_use_priv = "server"
	},
})

local ns = {
	info = function(pos, player, itemstack, mem, group, raw)
		metatool.form.show(player, 'luatool:mem_inspector', {
			group = group, -- tool storage group for stack manipulation
			itemstack = itemstack, -- tool itemstack
			name = "CPU at " .. minetest.pos_to_string(pos),
			mem = mem,
			raw = raw,
		})
	end,
} -- fixes a crash bug

tool:ns(ns)

local definition = {
	name = 'luacontroller',
	nodes = {"async_controller:controller"},
	group = 'lua controller',
	protection_bypass_read = "interact",
}

function definition:info(node, pos, player, itemstack)
	local meta = minetest.get_meta(pos)
	local mem = meta:get_string("lc_memory")
	return ns.info(pos, player, itemstack, mem, "lua controller")
end

function definition:copy(node, pos, player)
	local meta = minetest.get_meta(pos)

	-- get and store lua code
	local code = meta:get_string("code")

	-- return data required for replicating this controller settings
	return {
		description = string.format("Lua controller at %s", minetest.pos_to_string(pos)),
		code = code,
	}
end

function definition:paste(node, pos, player, data)
	-- restore settings and update lua controller, no api available
	local meta = minetest.get_meta(pos)
	if data.mem_stored then
		meta:set_string("lc_memory", data.mem)
	end
	local fields = {
		program = 1,
		code = data.code or meta:get_string("code"),
	}
	local nodedef = minetest.registered_nodes[node.name]
	nodedef.on_receive_fields(pos, "", fields, player)
end


tool:load_node_definition(definition)
