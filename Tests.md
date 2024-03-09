# "" Tests ""

I am too lazy to do automated unit tests, doing it the manual way works i think

## 1) doesn't light the thread on fire
code:
```lua
repeat until timeout
```
expected result:
```
(load):1: Code timed out!
``` 
(or something along the lines of that)
## 2) doesn't light the thread on fire #2
code:

- async controller 1:
    ```lua
        interrupt(0.5)
        print("i work")
    ```
- async controller 2:
    ```lua
        for i=1,100 do
            digiline_send("burn","please") 
        end
    ```
expected result: async controller 1 should turn yellow, and no longer print `"i work"` into the console
## 3) doesn't OOM the server
code:
```lua
    mem=string.rep("a",64000)..string.rep("a",64000)
```
expected result: async controller should turn yellow and no longer work

## 4) Interrupts
code:
```lua
interrupt(0.5)
if event.type=="interrupt" then
    print("it worked")
end
```
expected result:
```
(load):3: it worked
```

## 5) Digilines
code:

- async controller 1:
    ```lua
    digiline_send("hello","world")
    ```

- async controller 2:
    ```lua
    if event.type=="digiline" then
        print(event.channel.." "..event.msg)

    end
    ```

expected result:
- async controller 2:
```
    (load):2: hello world
```

## 6) Printing
code:
```lua
print("Hi world")
```
expected result:
```
hi world
```

code:
```lua
print("Hi void")
clearterm()
```
expected result:
```

```
(yes nothing)

## 7) modify_self
### 1
code:
```lua
modify_self(string.rep("A",64000))
```

expected result: the code **shouldn't** be `AAAAAAAAAA....`
### 2
code:

```lua
modify_self("code!")
```
expected result (code):
```
code!
```
### 3
code:
```lua
mem="modify_self(mem)"
modify_self(mem)
```
expected result (code) (after some events):
```lua
    modify_self(mem)
```
### 4
code:
```lua
interrupt(1)
modify_self("modify_self('b')")
```

expected result (code):
```
b
```
## 8) digiline sending limits

setup:
- 1) Place a pipeworks autocrafter with the channel "autocrafter"
- 2) Put in a recipe and the required amount of nodes for it

code:
```lua
for i=1,1000 do
    digiline_send("autocrafter","single")
end
```

expected result:
- The autocrafter should have crafted only `async_controller.max_digiline_messages_per_event` (or `150`, that's the default) items
