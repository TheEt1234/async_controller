-- Optional environment that can be enabled in the server's config

async_controller_async = async_controller_async or {}



local safe = {}
local env_plus = {}



local function escape_string_sandbox(f, outside_args) -- someone can override string.rep or string.gsub, thats bad, this makes it so that when "":sub happens it won't call the sandboxed function
    return function(...)
        local string_metatable = getmetatable("")
        local sandbox = string_metatable.__index
        string_metatable.__index = string

        local retvalues
        if outside_args == nil or #outside_args == 0 then
            retvalues = { f(...) }
        else
            retvalues = { f(unpack(outside_args), ...) }
        end
        string_metatable.__index = sandbox
        return unpack(retvalues)
    end
end


local HARDCODED_SANE_STRING_LENGTH = 64000
local function limit_string_length(f, alternative_string_length)
    local string_length = alternative_string_length or HARDCODED_SANE_STRING_LENGTH
    return function(...)
        for k, v in pairs({ ... }) do
            if type(v) == "string" then
                assert(#v < string_length, "String too long!")
            end
        end

        return f(...)
    end
end

local function the_pcall_sandbox(f) -- Detect if the hook is dead, if it is, throw an error, this is how pcall is sandboxed
    return function(...)
        local retvalues = { f(...) }

        if not debug.gethook() then
            error("The hook went poof (timeout caught by pcall?)... cannot continue execution", 2)
        end
        return unpack(retvalues)
    end
end

function safe.xpcall(f1, f2, ...)
    local xpcall_stuffs = { xpcall(f1, function(...)
        if not debug.gethook() then
            error("The hook went poof (timeout caught by pcall?)... cannot continue execution", 2)
        end

        return f2(...)
    end, ...) }

    if not debug.gethook() then
        error("The hook went poof (timeout caught by pcall?)... cannot continue execution", 2)
    end

    return unpack(xpcall_stuffs)
end

function safe.pcall(f1, ...)
    local pcall_stuffs = { pcall(f1, ...) }

    if not debug.gethook() then
        error("The hook went poof (timeout caught by pcall?)... cannot continue execution", 2)
    end

    return unpack(pcall_stuffs)
end

function safe.get_loadstring(env)
    return function(code)
        assert(type(code) == "string", "The code should be string last time i checked")
        assert(#code < HARDCODED_SANE_STRING_LENGTH, "code too long")
        if code:byte(1) == 27 then
            return nil, "Dont try to sneak in bytecode"
        end
        local f, msg = loadstring(code)

        if not f then return nil, msg end
        setfenv(f, env)


        if rawget(_G, "jit") then
            jit.off(f, true)
        end

        return f
    end
end

function safe.get_game_info()
    local info = minetest.get_game_info()
    info.path = nil
    return info
end

function safe.get_vector()
    local vector_funcs = table.copy(vector)
    vector_funcs.metatable = nil
    return vector_funcs
end

local function do_sandbox_stuff(f, ...)
    -- THIS SHOULD NOT BE INCLUDED IN STUFF THAT ACCEPTS AND RUNS USER ARBITRARY FUNCTIONS/CODE
    -- (due to lack of string sandboxing, a user could get the unsafe version of string.rep for example, and kill the server)
    return the_pcall_sandbox(limit_string_length(escape_string_sandbox(f, { ... })))
end



function env_plus.get_env_plus(pos, mem, event, itbl, async_env, env)
    return {
        arg_test = do_sandbox_stuff(function(...)
            minetest.debug(dump({ ... }))
            return #{ ... }
        end),
        minetest = {
            get_game_info = safe.get_game_info(),
            is_singleplayer = minetest.is_singleplayer(),
            features = minetest.features,
            get_version = minetest.get_version(),

            sha1 = do_sandbox_stuff(minetest.sha1),
            sha256 = do_sandbox_stuff(minetest.sha256),

            colorspec_to_colorstring = do_sandbox_stuff(minetest.colorspec_to_colorstring),
            colorspec_to_bytes = do_sandbox_stuff(minetest.colorspec_to_bytes),

            urlencode = do_sandbox_stuff(minetest.urlencode),

            formspec_escape = do_sandbox_stuff(minetest.formspec_escape),

            explode_scrollbar_event = do_sandbox_stuff(minetest.explode_scrollbar_event),
            explode_table_event = do_sandbox_stuff(explode_table_event),
            explode_textlist_event = do_sandbox_stuff(minetest.explode_textlist_event),

            inventorycube = do_sandbox_stuff(minetest.inventorycube),
            --[[
            serialize = do_sandbox_stuff(minetest.serialize),
            deserialize = do_sandbox_stuff(minetest.deserialize),
            --]]

            compress = do_sandbox_stuff(minetest.compress),
            decompress = do_sandbox_stuff(minetest.decompress),

            rgba = do_sandbox_stuff(minetest.rgba),

            encode_base64 = do_sandbox_stuff(minetest.encode_base64),
            decode_base64 = do_sandbox_stuff(minetest.decode_base64),
            encode_png = do_sandbox_stuff(minetest.encode_png),
        },
        bit = table.copy(bit),
        pcall = safe.pcall,
        xpcall = safe.xpcall,
        vector = safe.get_vector(),

        loadstring = safe.get_loadstring(env),

        dump = do_sandbox_stuff(dump),
        dump2 = do_sandbox_stuff(dump2),

    }
end

function env_plus.apply_env_plus(pos, mem, event, itbl, async_env, env)
    local env_plus = env_plus.get_env_plus(pos, mem, event, itbl, async_env, env)

    for k, v in pairs(env_plus) do
        if env[k] == nil then
            env[k] = v
        end
    end

    return env
end

async_controller_async.env_plus = env_plus
