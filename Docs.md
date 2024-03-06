# Docs
Basically the same as the normal luacontroller... except

# Enviroment
standard luacontroller enviroment but...
- You have access to the `pos` variable
- No mesecon I/O
- `print(string)` - prints to the print log
- `clearterm()` - clears the print log
### `modify_self(code)`
- replaces the async controller's code with the code provided to the function 
- clears print log
- **does not make a `program` event**
- limited to 50 000 characters
- makes an error to stop any more execution
# Notes
- You are forced to use lightweight interrupts (so no iid, but you can `interrupt(0)`)
- You can't send 2 000 messages at that digistuff noteblock, *by default* it will only send 150 per event