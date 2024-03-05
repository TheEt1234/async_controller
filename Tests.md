# "" Tests ""

I am too lazy to do unit tests, doing it the old way works i think

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
    error("it worked")
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
        error(event.channel.." "..event.msg)

    end
    ```

expected result:
- async controller 2:
```
    (load):2: hello world
```