# Async controller (experimental!)

Fork of [mesecons_luacontroller](https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller) in the mesecons modpack 

**Async controller is a luacontroller that is... async (mostly, there are some things that simply can't be done async)**

This means that whatever is inside the sandbox won't freeze the server, so we can get away with giving the luacontroller more *power*

# Async controller metatool

This was done because metatool didn't allow me to add support for my node to the luatool

It's basically a copy of the luatool, does not work in machines 

# Features
- print log
  - print(text) behaviour is different
  - added clearterm(e)
- pos
- modify_self(code)
- traceback in errors
- get_code_events() [also this allows benchmarking]

# Attempts to fix/fixes to bad bugz
- https://github.com/minetest-mods/mesecons/issues/415
 - when it sees table shenanigans in mem, it will replace it with {"no weird tables :/"}
- https://github.com/minetest-mods/mesecons/issues/516
 - introduces a different kind of ratelimit, still uses hooks but hard-limits the program to 5 miliseconds
 - makes the maxevents sorta obsolete maybe
- 
# TODOs
- Make the code better:tm:
- more testing (maybe)

# License

Code:
- LGPLv3

Media:
- textures/*
  - CC-BY-SA 3.0 https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller/textures
