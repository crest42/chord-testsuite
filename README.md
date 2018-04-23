# chord-testsuite
Testsuite &amp; example implementation for chord and CHash
- https://github.com/crest42/chord
- https://github.com/crest42/CHash

Testing:

```
make TARGS="<test args>" test
test args:
  --verbose | -v: Verbose mose
  --kill n | -k n: kill a child every n seconds
  --nodes | -n n: spawn n nodes

make autotest

You can also run the testsuite in interactive mode. This enables you to check the topology, spawn and kill nodes on demand:
perl testsuite.pl -i
```

USAGE:

``` bash
./example master <bind addr> [silent|interactive]
./example slave <bind addr> <master addr> [silent|interactive]
```
