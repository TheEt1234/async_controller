-- I've tried mineunit, it wasnt a good experience to say the least.....
-- So uh, i guess this works for automated tests
-- run tests with something like //luatransform async_controller.test(pos)

-- ok so this ended up being much more hack-y than i expected
-- ok update: i am not insane enough to do this


local test_queue = {}


function run_test()
    local t = table.remove(test_queue)
    if t ~= nil then
        t()
    end
end

local function it(name, func)
    test_queue[#test_queue + 1] = function()
        xpcall(func, function(...)
            minetest.log(name .. " NO")
            minetest.log(debug.traceback(...)) -- provide basic traceback (why doesnt mineunit have this wtf)
        end)

        -- intentionally don't log success
    end
end

local function get_set_program(pos) -- get the set_program function
    return function(code)
        minetest.get_meta(pos):set_string("code", code)
        async_controller.env.set_program(pos, code)
    end
end

local order = {}

local function execute_order(ok, errmsg)
    if #order ~= 0 then
        table.remove(order)(ok, errmsg)
    end
end

local function add_task(task) -- adds a task to execute once the async_Controller finished executing
    table.insert(order, 1, task)
end

function async_controller.test(pos) -- theese tests may be inconsistent depending on the hardware you are using i think, there is like a slight chance that might happen
    -- theres not really a good way to automatically test this
    async_controller.env.custom_callback = execute_order
    local set_program = get_set_program(pos)
    local function exec_program()
        async_controller.env.run(pos, {})
    end
    minetest.set_node(pos, {
        name = "async_controller:controller"
    })

    it("works", function()
        set_program([[]])
        minetest.log("[works] YES")
    end)

    it("rejects bytecode", function()
        set_program(string.dump(function() end))
        -- due to async we can't actually know if the program succeeded here.... so uh... umm.... yeah
        -- uhhh
        -- hey async_controller.env.custom_callback is here!

        add_task(function(ok, errmsg)
            if ok == true then
                minetest.log("[rejects bytecode] YES")
            else
                minetest.log("[rejects bytecode] YES")
            end

            run_test()
        end)
    end)

    it("memory", function()
        -- from https://github.com/minetest-mods/mesecons/blob/master/mesecons_luacontroller/spec/luac_spec.lua#L45C1-L53C7

        -- this one is an extremely tricky one, because it requires more events
        set_program([[
            clearterm()
			if not mem.x then
				mem.x = {}
				mem.x[mem.x] = {true, "", 1.2}
			else
				local b, s, n = unpack(mem.x[mem.x])
				if b == true and s == "" and n == 1.2 then
					print("success")
                else
                    print("failure")
                end
			end
        ]])
        add_task(exec_program) -- executes it twice
        add_task(function(ok, errmsg)
            if minetest.get_meta(pos):get_string("print") == "success\n" then
                minetest.log("[memory] YES")
            else
                minetest.log("[memory] NO; print text:" .. minetest.get_meta(pos):get_string("print"))
            end

            run_test()
        end)
    end)


    run_test()
end
