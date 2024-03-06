# Async controller (experimental!)

Fork of [mesecons_luacontroller](https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller) in the mesecons modpack 

**Async controller is a luacontroller that is... async (mostly, there are some things that simply can't be done async)**

This means that whatever is inside the sandbox won't freeze the server, so we can get away with giving the luacontroller more *power*

# Notes
- This is not a standard luacontroller
- doesn't suport mesecon I/O 
- forces lightweight interrupts
- **By default, maxevents (the setting dictating timeouts) is configured to be *10* times larger than default**

# Configuration
The only setting that this adds is **async_controller.maxevents**, other settings are re-used from the luacontroller

*Also note: async_controller ignores the* `luacontroller_string_rep_max` *setting, and instead uses the default value of 64000*

# Async controller metatool

This was done because metatool didn't allow me to add support for my node to the luatool

It's basically a copy of the luatool, does not work in machines 

# TODOs:
- Better print (maybe do what mooncontroller did)
- Support for re-programming the luacontroller with digilines
- Ratelimiting (maybe based off microseconds used in the sandbox, or just leave it alone)
- more testing (maybe)
