# Async luacontroller (experimental!)
## Will need heavy testing to verify if everything works
This is a non standard luacontroller, doesn't support mesecon I/O at all
And also forces lightweight interrupts
What do you get from all of this?
 	NO server lag* compared to the luacontroller
 	10x more timeout "resistance"
 	And no ratelimits will work here :p (the async controller doesn't freeze the server, so there's nothing to ratelimit really)
    also adds pos to the enviroment (why wasn't it there already)
