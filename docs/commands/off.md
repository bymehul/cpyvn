# off

**Syntax**
```vn
off <name>;
off <name> <transition> <seconds>;
```

**Description**
Removes a sprite from the scene. Optional `<transition>` animates it out.

Supported transitions:
`fade | wipe | slide | dissolve | zoom | blur | flash | shake | none`

**Example**
```vn
off alice;
off alice slide 0.35;
off alice dissolve 0.4;
```
