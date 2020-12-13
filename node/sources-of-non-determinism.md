## ES builtins

List of builtins for ES can be obtained from [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects).

V8 adds some builtins e.g. WeakRef, V8 builtins are implemented in C++/torque [here](https://github.com/v8/v8/tree/master/src/builtins).


## Sources of non-determinism

- `Math.random()` - [https://www.npmjs.com/package/seedrandom](https://www.npmjs.com/package/seedrandom)
- `Date.now()` - easily mockable
- `new Date()` - easily mockable
- `hrtime()` - not a part of v8, can be injected
- `setInterval()` + `clearInterval()`
- `setTimeout()` + `clearTimeout()`
- `setImmediate()` + `clearImmediate()`
- Allocation failure - catchable ([https://github.com/laverdet/isolated-vm#examples](https://github.com/laverdet/isolated-vm#examples))
- [Floating point arithmetic](https://bugs.chromium.org/p/v8/issues/detail?id=436#c6) - Does the problem exist on x86-64?
- `async / await` + `Promise` completion
    - Promises can be overridden in the global scope
    - async function doesn't create Promises with the global Promise object, see if there's a way to allow using it, Problematic example: `await (async () => 1)()`
    - async await can be compiled to generator + promises with typescript es6 target
- WeakRef - we'd have to avoid these since you can't programatically stop the v8 garbage collector, [example](https://v8.dev/blog/v8-release-84#javascript) - remove from globals.
- WeakSet, WeakMap - same as above
- Array, Object, Map, Set - all have deterministic iteration order
- Hashes are randomized - from `node --v8-options`, `TODO`: check what this is exactly:
    ```
    --randomize-hashes (randomize hashes to avoid predictable hash collisions (with snapshots this option cannot override the baked-in seed))
    --hash-seed (Fixed seed to use to hash property keys (0 means random)(with snapshots this option cannot override the baked-in seed))
    ```
