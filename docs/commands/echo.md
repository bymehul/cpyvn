# echo

**Syntax**
```vn
echo "path" start;
echo "path" stop;
```

**Description**
Plays a looping ambient track on its own channel. Use `stop` to end it.

**Example**
```vn
echo "rain.wav" start;
wait 2.0;
echo "rain.wav" stop;
```
