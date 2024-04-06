# Async controller (experimental!)

Fork of [mesecons_luacontroller](https://github.com/minetest-mods/mesecons/tree/master/mesecons_luacontroller) in the mesecons modpack 

**Async controller is a luacontroller that is... async (mostly, there are some things that simply can't be done async)**

This means that whatever is inside the sandbox won't freeze the server
so we can get away with giving the luacontroller more *power*

# Features
  See Docs.md

# Attempts to fix/fixes to bad bugz
- ~~https://github.com/minetest-mods/mesecons/issues/415~~
    - ~~when it sees table shenanigans in mem, it will replace it with `{"no weird tables :/"}`~~
      - ~~this fix was problematic, because it had false positives~~
    - ~~Runs the serializer under a debug hook, that's currently limited to 20 000 code events, if it exceeds that, it will **burn**~~
      - ~~`doesn't really make a difference in my machine, since the luacontroller already burns because it used up too much memory`~~
    - **ok so this isnt a problem anymore, because of improvements to the serializer, make sure to use the latest version of minetest with this mod and mesecons**
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
  - most of them were modified
