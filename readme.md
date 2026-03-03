Lua minifier written in lua.

Note: 
This minifier is purely made and tested for https://github.com/KippTheKippster/CC-Tweaked-MOS.
There is no guarantee that it will work with your code.

There is also no error checking, the minifier assumes that the input is completly valid.

Usage:
```lua minify.lua <infile=""> <outfile="out.lua"> <log=false>```

Optimizations:
    Redefinable Members:
        Writing
            ---\*name\*---
        at the top of a file allows the minifier to rename members of that table.
        Example:
            ---\*tbl\*---
            local tbl = {}
            tbl.var1 = 1
        Becomes:
            local A={}A.B=1
