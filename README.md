# Async controller (experimental!)

Fork of [mesecons_luacontroller](https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller) in the mesecons modpack 

**Async controller is a luacontroller that is... async (mostly, there are some things that simply can't be done async)**

This means that whatever is inside the sandbox won't freeze the server, so we can get away with giving the luacontroller more *power*

### i don't know if this is important to mention but
the behaviour of 
```lua
digiline_send("womp","blomp")
error("no you aint sending")
```
is different in the async controller (it sends the message, the normal luacontroller doesn't)
# Configuration
**async_controller.maxevents**

- "how many things can this luacontroller execute before timing out"
- By default it's set to ***10 times*** the normal luacontroller's limit (because the sandbox doesn't freeze the server)

**async_controller.max_digiline_messages_per_event**
- "how many digiline messages can this luacontroller send per event"
- default is 150, (that's less than what a default luacontroller can pull off) 


*Also note: async_controller ignores the* `luacontroller_string_rep_max` *setting, and instead uses the default value of 64000*

# Async controller metatool

This was done because metatool didn't allow me to add support for my node to the luatool

It's basically a copy of the luatool, does not work in machines 

# TODOs
- Ratelimiting (maybe based off microseconds used in the sandbox, or just leave it alone)
- more testing (maybe)

# License

Code:
- LGPLv3

Media:
- textures/jeija_luac*
  - CC-BY-SA 3.0 https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller/textures
