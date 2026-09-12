---
title: "Interview Prep — Part 1: Go Language"
description: "Go language fundamentals, types & generics, concurrency, memory/GC, error handling, performance, testing, and web/networking: 75 interview Q&As."
url: "/interview-prep-language/"
aliases: ["/go-interview-prep-language/"]
nodate: true
hidemeta: true
nofeed: true
---

Part 1 of 7 · [Interview Prep](/interview-prep/) · Next: [Part 2 — Coding Patterns](/interview-prep-coding-patterns/) →

## Go Fundamentals

| # | Question | Answer |
|---|----------|--------|
| <span id="1"></span>1 | What is the zero value of a struct in Go, and why does Go have zero values at all? | Every field gets its type's zero value (0, "", nil, false) — a struct's zero value is all fields zeroed. Go does this so every variable is always in a valid, usable state immediately after declaration, with no uninitialized-memory bugs like in C. |
| <span id="2"></span>2 | What's the difference between an array and a slice in Go? | An array has a fixed size baked into its type (`[5]int` and `[10]int` are different types) and is copied by value. A slice is a header (pointer, length, capacity) over an underlying array, is reference-like, and can grow via `append`. |
| <span id="3"></span>3 | How does `append` work under the hood — when does it reallocate? | If the slice has enough capacity, `append` writes into the existing backing array and just bumps length. If not, Go allocates a new, larger backing array (roughly doubling for small slices, smaller growth factor for large ones), copies the old data over, and returns a slice pointing at the new array. |
| <span id="4"></span>4 | What is the difference between a value receiver and a pointer receiver on a method? | A value receiver gets a copy of the struct — mutations inside the method don't affect the original. A pointer receiver operates on the original via its address, so mutations persist. Pointer receivers are also required if the method needs to mutate state or if the struct is large enough that copying is wasteful. |
| <span id="5"></span>5 | When would passing a struct by value vs pointer matter for performance and correctness? | Correctness: pointer if the callee needs to mutate the caller's data or you want to avoid copying a large struct with each call. Performance: small structs (a few words) are often cheaper to pass by value (stack, no heap escape, no indirection); large structs or ones passed into interfaces are cheaper by pointer to avoid copy cost, at the tradeoff of potential heap escape and GC pressure. |
| <span id="6"></span>6 | What does `defer` do and when do deferred calls run, exactly? | `defer` schedules a function call to run when the surrounding function returns, regardless of how it returns (normal return or panic). Multiple defers run in LIFO order. Critically, the deferred function's *arguments* are evaluated immediately at the `defer` statement, not when it actually runs later. |
| <span id="7"></span>7 | What's the difference between `make` and `new`? | `new(T)` allocates zeroed memory for a `T` and returns a `*T` pointer to it — works for any type. `make` is only for slices, maps, and channels, and returns an initialized (not zero-value) value of that type, e.g., a slice with usable header fields, not just a pointer. |

#### 8 — Difference between `var x []int` and `x := []int{}`? {#8}
`var x []int` is a nil slice (len 0, cap 0, underlying array pointer nil). `x := []int{}` is a non-nil, empty slice. Both behave the same for `len()`, `append()`, and ranging, but they differ under `== nil` checks and when marshaled to JSON (nil slice → `null`, empty slice → `[]`).

```go
var x []int    // nil slice: len=0, cap=0, ptr=nil
y := []int{}   // non-nil, empty slice

x == nil       // true
y == nil       // false

json.Marshal(x) // -> null
json.Marshal(y) // -> []
```

#### 9 — Explain how a slice's length and capacity work, and a footgun with slicing a slice. {#9}
Length is the visible number of elements; capacity is how much room exists in the backing array from the slice's start point. Footgun: `s2 := s1[:3]` still shares the same backing array as `s1`, so writes through `s2` can mutate `s1`, and appending to `s2` can silently overwrite elements `s1` hasn't "seen" yet if capacity allows it.

```go
s1 := []int{1, 2, 3, 4, 5}
s2 := s1[:3]           // shares s1's backing array
s2[0] = 99             // mutates s1[0] too
s2 = append(s2, 100)   // overwrites s1[3] if cap allows it
```

#### 10 — What happens when a `nil` map is read from vs written to? {#10}
Reading from a nil map is safe and returns the zero value for the value type (as if the key isn't present). Writing to a nil map panics with "assignment to entry in nil map." Always `make()` a map before writing to it.

```go
var m map[string]int
v := m["missing"]   // ok, returns 0 (zero value)
m["key"] = 1         // panic: assignment to entry in nil map

m = make(map[string]int)
m["key"] = 1         // ok now
```

---

## Types, Interfaces & Generics

| # | Question | Answer |
|---|----------|--------|
| <span id="11"></span>11 | How does Go implement interfaces (structural typing) vs Java/C# explicit `implements`? | Go interfaces are satisfied implicitly — any type that has the required methods satisfies the interface, with no declaration needed. This is structural/duck typing checked at compile time, unlike Java/C# where a class must explicitly declare `implements InterfaceName`. |
| <span id="12"></span>12 | What is the empty interface `interface{}` (`any`) and what are its costs? | It's satisfied by every type, so it's used for "accept anything" (like `fmt.Println` args). The cost: you lose compile-time type safety, need runtime type assertions/switches to use the value meaningfully, and there's a boxing cost — storing a concrete value in an interface can cause a heap allocation if it escapes. |
| <span id="13"></span>13 | What is method embedding / struct embedding and how does it differ from inheritance? | Embedding a struct or interface inside another promotes its fields/methods to the outer type, so `outer.Method()` calls the embedded type's method if not overridden. Unlike inheritance, there's no polymorphism through the base type — it's composition with automatic delegation, not an is-a relationship, and there's no virtual dispatch. |
| <span id="14"></span>14 | What's the difference between an interface satisfied implicitly at compile time vs reflection-based duck typing? | Go's interface satisfaction is checked entirely at compile time — if a type doesn't have the methods, it's a compile error, and there is zero runtime cost to check it. Reflection (`reflect` package) is a runtime mechanism to inspect/call methods dynamically when you don't know the type at compile time — much slower and loses static safety, and should be reserved for generic libraries (like `encoding/json`) rather than everyday application code. |
| <span id="15"></span>15 | Explain how the Go compiler represents an interface value internally (itab/data pointer). | An interface value is a two-word structure: a pointer to an "itab" (interface table — holds the concrete type info and a pointer to its method set matching this interface), and a pointer to the actual data. This is why interface method calls have one extra indirection versus a direct concrete-type call, and why very small concrete values assigned to an interface can still escape to the heap. |
| <span id="16"></span>16 | When would you use generics vs `interface{}` + type switch, considering compile-time safety and performance? | Generics: when the operation is structurally identical across types (sorting, filtering, a cache) — you get compile-time type checking, no runtime type assertions, and no boxing/allocation overhead for the parameterized type. `interface{}` + type switch: when you genuinely need different runtime behavior per type, or you're building something like a serialization layer that must handle arbitrary/unknown types at runtime. |

#### 17 — Explain the "nil interface vs interface holding a nil pointer" gotcha. {#17}
An interface value is really a (type, value) pair. If you assign a nil `*MyStruct` to an `error` interface variable, the interface's type is set to `*MyStruct` and value is nil — the interface itself is *not* nil, because it has a concrete type. So `err != nil` can be true even though the underlying pointer is nil. Classic bug: returning a typed nil error from a function that declares a named return of type `error`.

```go
func doWork() *MyError { return nil }

func run() error {
    var err *MyError = doWork()
    return err // returns a NON-nil error interface!
}

if run() != nil {
    // always true, even though the *MyError itself is nil
}
```

#### 18 — What is type assertion vs type switch, and how do you safely do a type assertion? {#18}
Type assertion (`v, ok := x.(T)`) extracts the concrete value if `x` holds type `T`; the two-value form avoids a panic on mismatch (`ok` is false instead). A type switch (`switch v := x.(type)`) branches over multiple possible concrete types in one construct. Always prefer the two-value assertion form unless you're certain of the type.

```go
// two-value assertion: safe, no panic
v, ok := x.(string)
if !ok {
    // x is not a string
}

// type switch: branch over multiple concrete types
switch t := x.(type) {
case string:
    fmt.Println("string:", t)
case int:
    fmt.Println("int:", t)
default:
    fmt.Println("unknown type")
}
```

#### 19 — What are Go generics (type parameters) and when would you use them over interfaces? {#19}
Generics (`func Map[T, U any](s []T, f func(T) U) []U`) let you write functions/types parameterized over a type, checked at compile time, without runtime type assertions or reflection. Use them when you need the *same logic* across different concrete types with type safety and no boxing cost — interfaces are better when you need runtime polymorphism (different behavior per type, not just different data types).

```go
func Map[T, U any](s []T, f func(T) U) []U {
    out := make([]U, len(s))
    for i, v := range s {
        out[i] = f(v)
    }
    return out
}

squares := Map([]int{1, 2, 3}, func(n int) int { return n * n })
```

#### 20 — Explain type constraints / the `comparable` constraint. {#20}
A constraint restricts which types can satisfy a generic type parameter — e.g., `[T constraints.Ordered]` restricts `T` to types supporting `<`, `>`. `comparable` restricts `T` to types that support `==`/`!=` (needed if you're using the type as a map key inside a generic function).

```go
type Ordered interface {
    ~int | ~int64 | ~float64 | ~string
}

func Max[T Ordered](a, b T) T {
    if a > b {
        return a
    }
    return b
}

func Keys[K comparable, V any](m map[K]V) []K {
    keys := make([]K, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return keys
}
```

---

## Concurrency Deep Dive

| # | Question | Answer |
|---|----------|--------|
| <span id="21"></span>21 | What is a goroutine and how is it different from an OS thread? | A goroutine is a lightweight, user-space unit of concurrent execution managed by the Go runtime, starting with a tiny (~2KB) growable stack, versus an OS thread's fixed, much larger stack (often MBs) and kernel-level scheduling overhead. Go can run hundreds of thousands of goroutines cheaply; the runtime multiplexes them onto a much smaller number of OS threads. |
| <span id="22"></span>22 | What is the GMP scheduler model? | G = goroutine, M = OS thread (machine), P = logical processor (holds a run queue of goroutines and the resources needed to execute Go code). The runtime schedules Gs onto Ms via Ps — the number of Ps is typically `GOMAXPROCS`, and this design lets goroutines migrate between OS threads efficiently, including work-stealing when a P's queue is empty. |
| <span id="23"></span>23 | What is a data race, and how does the Go race detector find them? | A data race is two goroutines accessing the same memory location concurrently, with at least one being a write, and no synchronization ordering the accesses — the result is undefined behavior. `go run -race` / `go test -race` instruments memory accesses at compile time and tracks happens-before relationships at runtime to flag races when they actually occur during execution. |
| <span id="24"></span>24 | What happens if you close a channel twice, or send on a closed channel? | Closing an already-closed channel panics. Sending on a closed channel panics. Receiving from a closed channel never panics — it returns the zero value immediately (with `ok == false` in the two-value form), which is why "close, don't send" and "only the sender closes" are the standard rules. |
| <span id="25"></span>25 | Why is `context.WithValue` generally discouraged for anything beyond request-scoped metadata? | It's untyped (`interface{}` keys/values), so misuse isn't caught at compile time, it hides real dependencies (a function's real inputs aren't visible in its signature), and it can silently break if a key collides or is misspelled. It's meant for cross-cutting concerns like trace/request IDs, not for passing business logic parameters. |
| <span id="26"></span>26 | What is a goroutine leak, and give a concrete example. | A goroutine that's blocked forever and never exits, so it (and anything it references) is never garbage collected. Classic example: a goroutine sends on an unbuffered channel, but the receiver already returned (e.g., due to a timeout) and nothing will ever read from that channel again — the sender goroutine blocks forever. Fix: always give blocking sends/receives a `select` with a `ctx.Done()` or timeout escape hatch. |
| <span id="27"></span>27 | What's the difference between `atomic.AddInt64` and wrapping an int with a mutex? | Atomic operations use CPU-level instructions (compare-and-swap) to update memory without a full lock — much cheaper for simple operations like counters, but limited to specific primitive operations. A mutex protects an arbitrary critical section (multiple statements, complex invariants) at the cost of higher overhead and potential contention/blocking. |
| <span id="28"></span>28 | Explain the Go memory model's "happens-before" relationship, briefly. | It defines the conditions under which a write in one goroutine is guaranteed to be visible to a read in another. Without an explicit happens-before edge (via channel operations, mutex lock/unlock, `sync.Once`, goroutine start/WaitGroup, or atomics), the compiler and CPU are free to reorder or cache operations — that's a data race even if it "usually works." |

#### 29 — Difference between buffered and unbuffered channels; what does sending on an unbuffered channel block on? {#29}
An unbuffered channel has no internal storage — a send blocks until a receiver is ready to receive at the same moment (a rendezvous), and vice versa. A buffered channel (`make(chan T, n)`) lets sends succeed without a waiting receiver as long as the buffer isn't full; once full, sends block until space frees up.

```go
unbuffered := make(chan int)     // send blocks until a receiver is ready
buffered := make(chan int, 3)    // send succeeds until buffer is full

buffered <- 1 // ok, buffer has room
buffered <- 2 // ok
buffered <- 3 // ok, buffer now full
buffered <- 4 // blocks until something is received
```

#### 30 — How do you safely check whether a channel is closed while reading? {#30}
Use the two-value receive form: `v, ok := <-ch`. `ok` is `false` once the channel is closed and drained — this is the idiomatic way, versus racy approaches like checking length or a separate "isClosed" flag without synchronization.

```go
v, ok := <-ch
if !ok {
    // channel is closed and drained
    return
}
// use v
```

#### 31 — Explain `select` and how it's used for timeouts/cancellation. {#31}
`select` blocks until one of several channel operations is ready, choosing pseudo-randomly if multiple are ready simultaneously.

```go
select {
case res := <-ch:
    return res, nil
case <-time.After(2 * time.Second):
    return nil, errors.New("timeout")
}

select {
case <-ctx.Done():
    return ctx.Err()
case res := <-ch:
    return res, nil
}
```

#### 32 — What's the purpose of `context.Context`, and the difference between `WithCancel`, `WithTimeout`, `WithDeadline`, `WithValue`? {#32}
`Context` carries cancellation signals, deadlines, and request-scoped values across API boundaries and goroutines. `WithCancel` gives you a manual cancel function; `WithTimeout`/`WithDeadline` auto-cancel after a duration or at a wall-clock time; `WithValue` attaches a key-value pair for passing request-scoped metadata down a call chain — it should never be used to pass optional function parameters.

```go
ctx, cancel := context.WithCancel(parent)
defer cancel()

ctx, cancel = context.WithTimeout(parent, 5*time.Second)
defer cancel()

ctx, cancel = context.WithDeadline(parent, someTime)
defer cancel()

ctx = context.WithValue(parent, requestIDKey, "abc-123")
```

#### 33 — Explain `sync.WaitGroup` and a common misuse. {#33}
`WaitGroup` lets one goroutine wait for a group of others to finish: `Add(n)` before starting, `Done()` (usually deferred) in each goroutine, `Wait()` blocks until the counter hits zero. Common misuse: calling `Add` *after* `Wait()` has already started or concurrently with it — this is a race and can panic or hang.

```go
var wg sync.WaitGroup
for i := 0; i < n; i++ {
    wg.Add(1) // correct: Add before the goroutine starts
    go func() {
        defer wg.Done()
        // work
    }()
}
wg.Wait()
// BUG: calling Add() concurrently with/after Wait() is a race
```

#### 34 — Explain `sync.Once` and a real use case. {#34}
`sync.Once.Do(f)` guarantees `f` runs exactly once, even if called from many goroutines concurrently — all callers block until the first call to `f` completes. Real use: lazy-initializing a singleton, like a global config object or a database connection pool, safely under concurrent first access.

```go
var (
    once sync.Once
    db   *sql.DB
)

func GetDB() *sql.DB {
    once.Do(func() {
        db, _ = sql.Open("postgres", dsn)
    })
    return db
}
```

#### 35 — Design a worker pool in Go — what are the components? {#35}
A jobs channel that producers send work into; a fixed number N of worker goroutines that range over the jobs channel and process each item; a results channel for output; a `context.Context` passed down for cancellation; and a `sync.WaitGroup` to know when all work is drained.

```go
func workerPool(ctx context.Context, jobs <-chan Job, n int) <-chan Result {
    results := make(chan Result)
    var wg sync.WaitGroup

    for i := 0; i < n; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for {
                select {
                case job, ok := <-jobs:
                    if !ok {
                        return
                    }
                    results <- process(job)
                case <-ctx.Done():
                    return
                }
            }
        }()
    }

    go func() { wg.Wait(); close(results) }()
    return results
}
```

---

## Memory Management & GC

| # | Question | Answer |
|---|----------|--------|
| <span id="36"></span>36 | What is escape analysis and how does it decide stack vs heap allocation? | The compiler statically analyzes whether a variable's lifetime or visibility could outlive the function that created it. If it can prove the variable never escapes, it allocates on the stack (cheap, freed automatically on return); otherwise it "escapes to the heap" and becomes GC-managed. |
| <span id="37"></span>37 | How does Go's garbage collector work at a high level? | Go uses a concurrent, tri-color mark-and-sweep collector. It marks reachable objects (white → grey → black) mostly concurrently with the running program using write barriers, then sweeps unmarked (white) objects, minimizing stop-the-world pauses (typically sub-millisecond) at the cost of using more CPU concurrently with your program. |
| <span id="38"></span>38 | What is GC pressure and what causes it in a typical Go service? | GC pressure is the rate at which your program creates heap garbage, forcing more frequent/expensive collection cycles. Common causes: excessive small allocations in hot paths (string concatenation, boxing values into interfaces), large numbers of short-lived objects, and unbounded growth of slices/maps that get reallocated repeatedly. |
| <span id="39"></span>39 | How do you reduce allocations in a hot path? | Pre-size slices/maps with `make([]T, 0, expectedCap)`; reuse buffers via `sync.Pool`; avoid unnecessary boxing into `interface{}`; use `strings.Builder` instead of `+=` concatenation; pass pointers to large structs instead of copying; and profile with `pprof -alloc_objects` to find the actual hot spots rather than guessing. |
| <span id="40"></span>40 | What is `sync.Pool` and when is it a bad idea? | `sync.Pool` caches and reuses temporary objects (like byte buffers) to reduce allocation/GC churn, but pooled objects can be evicted at any time (notably during GC), so it's only for objects you can afford to lose and recreate cheaply — a bad idea for objects with meaningful state you need to persist. |
| <span id="41"></span>41 | Explain how string concatenation in a loop can cause performance issues. | Go strings are immutable, so `s += x` in a loop allocates a brand-new string and copies the old contents every iteration — O(n²) total work for n concatenations. Fix: use `strings.Builder` (or `bytes.Buffer`), which grows an internal buffer amortized O(1) per append. |
| <span id="42"></span>42 | How can Go leak memory despite having a GC? | Anything still *reachable* is never collected. Common patterns: a growing global cache/map with no eviction; a slice that keeps a reference to a much larger backing array after slicing out a small piece; goroutine leaks; and subscriber/listener lists that never unregister closed connections. |
| <span id="43"></span>43 | How would you investigate high memory usage in a running Go service in production? | Expose `net/http/pprof`, pull a heap profile to see allocation sources by call site; compare two heap snapshots over time (`-base`) to find what's growing; check goroutine count for leaks; and correlate with GC stats (`GODEBUG=gctrace=1`) to see if it's live heap growth vs just infrequent GC. |
| <span id="44"></span>44 | What is `GOGC` and how does tuning it trade off memory vs CPU? | `GOGC` sets the target heap growth percentage before a GC cycle triggers (default 100). Lowering it triggers GC more often — less peak memory, more CPU spent collecting. Raising it (or using `GOMEMLIMIT` as a hard cap) reduces GC frequency/CPU cost at the expense of higher peak memory usage. |
| <span id="45"></span>45 | Explain false sharing and struct field ordering for concurrent performance. | False sharing happens when two goroutines on different CPU cores modify different variables that happen to sit on the same CPU cache line — each write invalidates the other core's cache line, causing costly cache coherency traffic even though there's no actual data race. Fix: pad hot, independently-written fields so each lands on its own cache line. |

---

## Error Handling & Idioms

| # | Question | Answer |
|---|----------|--------|
| <span id="46"></span>46 | Why does Go use explicit error returns instead of exceptions? | It makes control flow and failure paths visible and explicit at every call site — a function's signature tells you it can fail, and the caller is forced to consciously handle or propagate the error. |
| <span id="47"></span>47 | When would you define a custom error type vs use `errors.New`? | `errors.New`/sentinel errors are fine when callers only need to check "did this specific failure happen" (`errors.Is`). A custom error type is better when the caller needs structured data about the failure that they'll extract with `errors.As`. |
| <span id="48"></span>48 | What's the idiomatic way to handle a "not found" case? | Define a sentinel error (`var ErrNotFound = errors.New("not found")`) or a well-known error type, return it wrapped with context, and let callers check with `errors.Is(err, ErrNotFound)` rather than string-matching the error message. |
| <span id="49"></span>49 | Explain panic/recover — when is it appropriate to use? | `panic` unwinds the stack running deferred calls until something `recover`s or the program crashes. Appropriate for truly unrecoverable programmer errors, or unwinding deeply nested code within a single package's internal boundary — an anti-pattern as a general substitute for error returns across API boundaries. |
| <span id="50"></span>50 | How do you avoid swallowing/hiding errors in a large codebase during code review? | Flag any `if err != nil { return }` without wrapping/logging context, any `_ = someFunc()` without a documented reason, and any blanket `recover()` that doesn't re-surface what was recovered. Lint with `errcheck`; review focuses on whether wrapped context is actually useful for debugging later. |
| <span id="51"></span>51 | Explain how retry logic could make an outage worse, and how you'd prevent it. | Naive fixed-interval retries across many clients synchronize into bursts that hit an already-struggling service at the same moment (thundering herd). Prevention: exponential backoff with jitter, a cap on total retry attempts/duration, and a circuit breaker that stops sending requests entirely once failure rate crosses a threshold. |

#### 52 — What is error wrapping and how do `errors.Is`/`errors.As` use it? {#52}
`fmt.Errorf("doing X: %w", err)` wraps an underlying error while adding context, preserving a chain accessible via `Unwrap()`. `errors.Is(err, target)` walks that chain checking for a matching sentinel error; `errors.As(err, &target)` walks the chain looking for an error of a specific concrete type.

```go
if err != nil {
    return fmt.Errorf("fetching user %d: %w", id, err)
}

if errors.Is(err, ErrNotFound) {
    // matches even through multiple layers of wrapping
}

var ve *ValidationError
if errors.As(err, &ve) {
    fmt.Println(ve.Field, ve.Code)
}
```

#### 53 — What is the "errgroup" pattern for handling multiple goroutine errors? {#53}
`golang.org/x/sync/errgroup` runs a group of goroutines, cancels a shared context if any of them returns an error, and `Wait()` returns the first non-nil error from the group — a clean way to fan out concurrent work and propagate the first failure without manually wiring channels and WaitGroups together.

```go
g, ctx := errgroup.WithContext(ctx)
for _, url := range urls {
    url := url
    g.Go(func() error {
        return fetch(ctx, url)
    })
}
if err := g.Wait(); err != nil {
    // first non-nil error from the group
    return err
}
```

---

## Performance & Profiling

| # | Question | Answer |
|---|----------|--------|
| <span id="54"></span>54 | What tools would you use to profile CPU vs memory usage in a Go service? | `net/http/pprof` exposed on a debug port, then `go tool pprof http://host/debug/pprof/profile` for a 30s CPU profile and `.../heap` for memory allocation sources. `go tool pprof -http=:8080` gives an interactive flame graph for either. |
| <span id="55"></span>55 | How do you find a goroutine leak in production? | Watch the goroutine count metric over time — a steady upward trend with no plateau under steady traffic indicates a leak. Pull a goroutine dump and look for many goroutines stuck in the same blocking call to identify the leaking code path. |
| <span id="56"></span>56 | What's the cost difference between a map lookup and a slice index? | A slice index is O(1) with a direct memory offset calculation — extremely cheap. A map lookup is also amortized O(1) but involves hashing the key and a bucket lookup, meaningfully more expensive per operation with worse cache locality. |
| <span id="57"></span>57 | Explain benchmark methodology in Go and how to avoid misleading results. | `go test -bench=. -benchmem` runs benchmark functions in a loop, reporting ns/op and allocations/op. Pitfalls: letting the compiler dead-code-eliminate the benchmarked work, not resetting the timer after expensive setup, and running on a noisy/shared machine. |
| <span id="58"></span>58 | What is inlining in Go and why might a function not get inlined? | Inlining substitutes a function call with its body directly at the call site. The compiler decides based on a complexity budget — functions with loops, closures, defer, panic/recover, or that are simply too large typically won't be inlined. |
| <span id="59"></span>59 | How would you reduce GC latency spikes in a low-latency service? | Minimize allocation rate in the hot path (object pooling, pre-sized buffers), tune `GOGC`/`GOMEMLIMIT` to match the workload's memory budget, and keep the live heap size predictable — the goal is fewer, more predictable GC cycles. |
| <span id="60"></span>60 | Explain the tradeoffs of reflection vs codegen for performance-critical serialization. | `encoding/json`'s reflection-based approach is convenient but pays a real runtime cost inspecting struct tags on every call. Codegen (like `easyjson`, protobuf-generated code) generates type-specific marshal/unmarshal code at build time — no reflection at runtime, significantly faster, at the cost of a build step. |
| <span id="61"></span>61 | How do you decide when to use struct-of-arrays vs array-of-structs for cache locality? | Array-of-structs is simplest and fine when you typically access all fields together. Struct-of-arrays improves cache locality when hot code only touches one or two fields across many items, at the cost of more complex code. |

---

## Testing & Tooling

| # | Question | Answer |
|---|----------|--------|
| <span id="62"></span>62 | What is table-driven testing and why is it idiomatic in Go? | A single test function iterates over a slice of struct literals, each defining an input/expected-output case, running `t.Run(name, ...)` per case as a subtest. Keeps test logic in one place and makes adding new cases trivial. |
| <span id="63"></span>63 | Difference between unit and integration tests, and how do you structure them in a Go project? | Unit tests exercise a single function/package in isolation with mocked dependencies and run fast. Integration tests exercise real dependencies and are slower/flakier — commonly separated with a build tag (`//go:build integration`) so CI can run them in a separate stage. |
| <span id="64"></span>64 | What is `httptest` used for? | `httptest.NewServer` spins up a real local HTTP server backed by your handler for full-stack testing, and `httptest.NewRecorder` captures a handler's response without a real network connection. |
| <span id="65"></span>65 | How would you test code that depends on time? | Inject time as a dependency rather than calling `time.Now()` directly — accept a `Clock` interface that production code satisfies with the real clock and tests satisfy with a fake, controllable clock. |
| <span id="66"></span>66 | Do you prefer interfaces + hand-written mocks or a mocking framework, and why? | Small, hand-written interfaces with hand-written fakes keep tests simple and work well when the interface is small and stable. A mocking framework pays off when you have many dependencies or need to assert call counts/arguments precisely. |
| <span id="67"></span>67 | What does `go vet` and `staticcheck` catch that the compiler doesn't? | `go vet` catches suspicious constructs that compile fine but are almost always bugs — wrong `Printf` verb, copying a struct containing a `sync.Mutex`. `staticcheck` goes further — unused struct fields, redundant code, deprecated API usage. |
| <span id="68"></span>68 | Explain fuzz testing and when it's worth using. | Go's built-in fuzzing (`go test -fuzz`) generates random/mutated inputs to a function and checks for panics or violated invariants — especially valuable for parsers, serializers, and anything handling untrusted input. |

---

## Go Web, Networking & Services

| # | Question | Answer |
|---|----------|--------|
| <span id="69"></span>69 | How does `net/http` handle concurrent requests by default? | The standard server spawns a new goroutine per incoming connection/request automatically — any shared state your handlers touch needs its own synchronization, since many goroutines will call into it simultaneously. |
| <span id="70"></span>70 | What is middleware in a Go HTTP server and how do you chain it? | Middleware wraps an `http.Handler` with another `http.Handler` that runs logic before/after calling the wrapped one — commonly `func(http.Handler) http.Handler`. Chaining is nested function composition or a router's built-in `Use()`. |
| <span id="71"></span>71 | How do you implement rate limiting in a Go API? | Token bucket (via `golang.org/x/time/rate.Limiter`) allows bursts up to a bucket size while enforcing a steady average rate. For a single instance, an in-memory limiter works; for multiple instances, you need a shared store. |
| <span id="72"></span>72 | How do you drain in-flight gRPC streams vs HTTP requests differently during shutdown? | HTTP: `server.Shutdown(ctx)` stops accepting new connections and waits for in-flight requests. gRPC: `server.GracefulStop()` similarly stops accepting new RPCs, but long-lived streaming RPCs also need application-level logic to signal the stream should wind down. |
| <span id="73"></span>73 | Difference between REST and gRPC, and when would you choose gRPC internally? | REST/JSON is human-readable and universally supported but has serialization overhead. gRPC uses HTTP/2 and protobuf binary serialization — faster, strongly-typed contracts, native streaming — a strong default for internal service-to-service calls. |
| <span id="74"></span>74 | How do you handle backward compatibility when evolving a protobuf/gRPC API? | Never change or reuse a field number, only add new fields with new numbers, make new fields optional with sensible defaults, and version the service (`v1`, `v2`) when a truly breaking change is unavoidable. |
| <span id="75"></span>75 | How would you implement connection pooling for a Postgres client in Go, and what happens if you don't? | Use `database/sql`'s built-in pool (`SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`) or `pgxpool`. Without it, each request opening a fresh connection incurs real latency and can exhaust Postgres's max connection limit under load. |

---

## Notes

**[Memory Management & GC](#memory-management--gc), [Performance & Profiling](#performance--profiling), [Testing & Tooling](#testing--tooling), and [Go Web, Networking & Services](#go-web-networking--services):** kept as plain tables — conceptual/tooling questions that don't lend themselves to diagrams, so time is better spent drilling them out loud than looking for a picture that isn't there.

---

Part 1 of 7 · [Interview Prep](/interview-prep/) · Next: [Part 2 — Coding Patterns](/interview-prep-coding-patterns/) →
