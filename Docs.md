# Features that async_controller lacks 
- No mesecon I/O - makes things way simpler

# Enviroment
*if you are not familiar with the luacontroller environment, you can get started by doing `print(_G)` or by going to* https://mesecons.net/luacontroller - but keep in mind that it is **way too** outdated
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
  - does not make a `program` event, you will need to `interrupt(0.1)` so that the code gets ran
  - limited to `server.conf.modify_self_max_code_len` characters
  - makes an error to stop any more execution

### server.*
- `server.us_time()` - is just `minetest.get_us_time`
- I might add stuff to this in the future
### server.conf.* 
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
