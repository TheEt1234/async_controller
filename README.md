# Async controller (experimental!)

Fork of [mesecons_luacontroller](https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller) in the mesecons modpack 

**Async controller is a luacontroller that is... async (mostly, there are some things that simply can't be done async)**

This means that whatever is inside the sandbox won't freeze the server
so we can get away with giving the luacontroller more *power*

# Features
  See Docs.md

# Attempts to fix/fixes to bad bugz
- https://github.com/minetest-mods/mesecons/issues/415
   - when it sees table shenanigans in mem, it will replace it with `{"no weird tables :/"}`
- https://github.com/minetest-mods/mesecons/issues/516
  - introduces a different kind of ratelimit, still uses hooks but hard-limits the program to 5 miliseconds
  - makes the maxevents sorta obsolete maybe
  - also makes an attempt at a memory limit
    - if you want async_controllers to be 100% reliable you should probably disable that one

# TODOs

- in-game docs
- make it better looking idk
- more testing (maybe)

# License

Code:
- LGPLv3

Media:
- textures/*
  - CC-BY-SA 3.0 https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller/textures
