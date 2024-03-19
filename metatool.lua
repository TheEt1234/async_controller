-- credit: SX
local luatool = metatool.tool("luatool")
if luatool then
	-- grab existing luatool:ns() instance for info function usage:
	local ns = metatool.ns("luatool")
	-- and also add your own node definition:
	local definition = {
		name = 'async_luacontroller',
		nodes = { "async_controller:controller" },
		group = 'lua controller',
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

	-- Finally load new node definition for luatool
	luatool:load_node_definition(definition)
end
