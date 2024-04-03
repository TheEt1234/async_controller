local function print_log_formspec(meta)
	local print_log = minetest.formspec_escape(meta:get_string("print") or "")
	local fs = {
		"size[15,12]",
		"real_coordinates[true]",
		"style_type[label,textarea;font=mono;bgcolor=black;textcolor=white]",
		"textarea[0,0;14.9,12;;;" .. print_log .. "]",
		"tabheader[0,0;tab;Editor,Print log;2]"
	}
	local fs = table.concat(fs, "")

	meta:set_string("formspec", fs)
end
local function reset_formspec(meta, code, errmsg)
	local code = code
	local errmsg = errmsg
	if code ~= nil then
		meta:set_string("code", code)
		meta:mark_as_private("code")
		code = minetest.formspec_escape(code or "")
		errmsg = minetest.formspec_escape(tostring(errmsg or ""))
	else
		-- used when switching tabs
		code = minetest.formspec_escape(meta:get_string("code") or "")
		errmsg = ""
	end
	local state = meta:get_string("state") or ""
	if state == "editor" or state == "" then
		local fs = {
			"size[12,10]",
			"style_type[label,textarea;font=mono]",
			"background[-0.2,-0.25;12.4,10.75;jeija_luac_background.png]",
			"label[0.1,8.3;" .. errmsg .. "]",
			"textarea[0.2,0.2;12.2,9.5;code;;" .. code .. "]",
			"image_button[4.75,8.75;2.5,1;jeija_luac_runbutton.png;program;]",
			"image_button_exit[11.72,-0.25;0.425,0.4;jeija_close_window.png;exit;]",
			"tabheader[0,0;tab;Editor,Print log;1]",
		}
		local fs = table.concat(fs, "")
		meta:set_string("formspec", fs)
	elseif state == "print_log" then
		print_log_formspec(meta)
	end
end
local function on_receive_fields(pos, _, fields, sender)
	local name = sender:get_player_name()
	if minetest.is_protected(pos, name) and not minetest.check_player_privs(name, { protection_bypass = true }) then
		minetest.record_protection_violation(pos, name)
		return
	end
	local meta = minetest.get_meta(pos)
	if fields.program then
		async_controller.env.set_program(pos, fields.code)
	elseif fields.tab then
		if fields.tab == "1" then
			meta:set_string("state", "editor")
			reset_formspec(meta, nil, nil)
		elseif fields.tab == "2" then
			meta:set_string("state", "print_log")
			print_log_formspec(meta)
		end
	else
		return
	end
end
async_controller.env.reset_formspec = reset_formspec
async_controller.env.on_receive_fields = on_receive_fields
