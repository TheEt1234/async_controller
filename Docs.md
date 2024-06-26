# Features that async_controller lacks 
- No mesecon I/O - makes things way simpler, might re-introduce it later

# Enviroment
*if you are not familiar with the normal luacontroller environment, you can get started by doing `print(_G)` or by going to* https://mesecons.net/luacontroller - but keep in mind that it is **way too** outdated
### Global
- `pos` - position
- `print(string)` - prints to the print log
- `clearterm()` - clears the print log
- `get_code_events()` - gives you the amount of code events, use for benchmarking 
  - not to be confused with regular events, code events are basically uhh.... every time something in your code happens it will increment
- `get_ram_usage()` - Gives the total ram usage of the luacontroller sandbox
  - In kilobytes
  - Things that happen outside of the luacontroller are also counted
  - If this amount exceeds `server.conf.max_sandbox_mem_size` then the luac times out
    - (`server.conf.max_sandbox_mem_size` is usually very big to account for the fact that some things outside of the luac sandbox may be counted)
- `modify_self(code)`
  - replaces the async controller's code with the code provided to the function
  - does not make a `program` event, you will need to `interrupt(0)` so that the code gets ran
  - limited to `server.conf.modify_self_max_code_len` characters
  - makes an error to stop any more execution
  - *may get removed in the future in favour of env_plus's loadstring*


### conf 
 - exposes async_controller related settings: 
 - `code_events_max, heat_max, execution_time_limit, channel_maxlen, message_maxlen, memsize, max_digilines_messages_per_event, modify_self_max_code_len, max_sandbox_mem_size`

## limits
- If `get_code_events()` exceeds `server.conf.code_events_max` then the luacontroller times out
- Sandbox memory usage must not exceed `server.conf.max_sandbox_mem_size` or the luacontroller times out (unreliable)
- The sandbox cannot execute for more than `server.conf.execution_time_limit` microseconds, if it does it will timeout
- See `sandbox.lua` for more info

# Notes
- You are forced to use lightweight interrupts (so no iid, also you can `interrupt(0)`)
- You can't send 2 000 messages at that digistuff noteblock to blow people's ears off, *by default* it will only send 150 per event
- When an error occurs, the traceback is provided
- You can see memory errors now


# env_plus
- An experimental, way more powerful environment

  (most) functions in this environment are limited in theese ways:

  1) string sandbox gets escaped in functions that don't execute arbitrary user input/functions
      - what this means is that `string.sub = function(...) return "hehe" end` won't matter (i think it would only modify `"a":sub` but still)
  2) arguments get checked for string length, if it exceeds 64000 it will error
  3) if the hook dies it will throw an error
      - If the code times out under a pcall, it will catch it and the hook will still get destroyed
      - So if we detect that the hook is gone, we throw an error

  Here is the stuff:
  ## minetest
    - **Some things may not be functions but values**
    - `get_us_time = minetest.get_us_time`
    - `get_game_info = minetest.get_game_info() -- removes path from the output`
    - `is_singleplayer = minetest.is_singleplayer()`
    - `features = minetest.features`
    - `get_version = minetest.get_version()`
    - `sha1 = minetest.sha1`
    - `colorspec_to_colorstring = minetest.colorspec_to_colorstring`
    - `colorspec_to_bytes = minetest.colorspec_to_bytes`
    - `urlencode = minetest.urlencode`
    - `formspec_escape = minetest.formspec_escape`
    - `explode_scrollbar_event = minetest.explode_scrollbar_event`
    - `explode_table_event = explode_table_event`
    - `explode_textlist_event = minetest.explode_textlist_event`
    - `inventorycube = minetest.inventorycube`
    - `rgba = minetest.rgba`
    - `encode_base64 = minetest.encode_base64`
    - `decode_base64 = minetest.decode_base64`
    - `encode_png = minetest.encode_png `
  ## Things outside of minetest
    - `bit = table.copy(bit)`
    - `pcall = safe.pcall`
    - `xpcall = safe.xpcall`
    - `vector = safe.get_vector() -- doesnt have the vector.metatable`
    - `loadstring = safe.get_loadstring(env) -- doesnt allow bytecode and does other stuff`
    - `code = code -- is your code`
