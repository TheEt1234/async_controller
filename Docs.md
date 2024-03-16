# Docs
Basically the same as the normal luacontroller... except

# Enviroment
standard luacontroller enviroment but...
- You have access to the `pos` variable
- No mesecon I/O
- `print(string)` - prints to the print log
- `clearterm()` - clears the print log
- `get_code_events()` - gives you the amount of code events, use for benchmarking 
    - not to be confused with regular events, code events are basically uhh.... every time something in your code happens it will increment
- `code_events_max` - "how many code events can i have before the luac times out"
### `modify_self(code)`
- replaces the async controller's code with the code provided to the function
- **does not make a `program` event, you will need to interrupt(0.1) so that the code gets ran**
- limited to 50 000 characters
- makes an error to stop any more execution (kinda hacky, i should make it less hacky or just leave execution alone)

# Notes
- You are forced to use lightweight interrupts (so no iid, but you can `interrupt(0)`)
- You can't send 2 000 messages at that digistuff noteblock to blow people's ears off, *by default* it will only send 150 per event
- When an error occurs, an edited version of the traceback is provided
