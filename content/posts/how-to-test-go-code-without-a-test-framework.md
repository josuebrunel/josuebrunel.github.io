---
title: "How to Test Go Code Without a Test Framework"
date: 2024-08-29
author: "Josué"
description: "Writing type-safe Go test helpers with generics, reflect.DeepEqual, and testing.Helper() - no external test framework required."
tags: ["golang", "testing"]
---

In Go, testing your code doesn't necessarily require a complex test framework. With the language's built-in capabilities, you can write robust and maintainable tests that cover a wide range of scenarios. In this post, we'll explore how to test Go code effectively without relying on any external test frameworks, focusing on leveraging reflection, generics, and the `testing.Helper()` function.

## tl;dr

- **Why?**: https://go.dev/doc/faq#assertions
- **Code**: https://github.com/josuebrunel/gopkg/tree/main/assert

## Using Reflection for Testing (Before Go 1.18)

Reflection in Go allows us to inspect the types and values of variables at runtime, enabling dynamic behavior in our tests. In the `Assert` function below, reflection is used to compare two values for equality:

```go
func Assert(t *testing.T, x, y any) {
    if !reflect.DeepEqual(x, y) {
        t.Fatalf("[ASSERT-FAILED] - %v != %v", x, y)
    }
}
```

The `Assert` function takes two values of any type (`x` and `y`) and compares them using `reflect.DeepEqual`. This allows us to write tests that can handle various types, from primitive types like `int` and `string` to more complex structs.

However, reflection has its downsides:

- **Performance Overhead**: Reflection is slower than direct type comparisons.
- **Verbosity**: Using `reflect.DeepEqual` can be less intuitive, especially for developers unfamiliar with reflection.

## Enter Generics: A Game Changer

Generics, introduced in Go 1.18, offer a more type-safe and efficient way to achieve what we did with reflection, but with cleaner code and better performance. Here's how we can rewrite our `Assert` function using generics:

```go
func AssertT[T comparable](t *testing.T, x, y T) {
    t.Helper()
    if x != y {
        t.Fatalf("[ASSERT-FAILED] - %v != %v", x, y)
    }
}
```

This version of `AssertT` is type-safe and does not incur the performance cost of reflection. The use of the `comparable` constraint ensures that the types passed to the function support equality checks (`==`), making it safer and more predictable.

The benefits of this approach include:

- **Type safety**: The compiler ensures that `x` and `y` are of the same type.
- **Performance**: No reflection is needed, leading to faster execution.
- **Clarity**: The function signature clearly communicates its purpose and constraints.

## Enhancing Test Helpers with testing.Helper()

The `t.Helper()` function is a small but powerful addition to our test helper functions. When a test fails, Go's testing library reports the line of code where the failure occurred. Without `t.Helper()`, this line would be inside the helper function itself, making it harder to diagnose issues.

By calling `t.Helper()` within our helper functions like `AssertT`, we tell the testing framework that this function is a helper. This way, when an assertion fails, the reported line number will point to the actual test case where the helper was called, not to the helper function's internal code. This significantly improves the readability and debuggability of our test failures.

```go
func TestAdd(t *testing.T) {
    t.Run("intAddition", func(t *testing.T) {
        result := Add(2, 3)
        AssertT(t, result, 5) // If this fails, it will point to this line, not inside AssertT
    })
}
```

If this test fails, the error messages will clearly indicate the lines in `TestAdd` where the assertions failed, making debugging much more straightforward.

Concretely, here's the difference. Without `t.Helper()`, a failing assertion points *inside* the helper:

```
--- FAIL: TestAdd/intAddition (0.00s)
    assert.go:41: [ASSERT-FAILED] - 6 != 5
```

`assert.go:41` is the `t.Fatalf` line inside `AssertT` itself - useless, because every failing assertion in the whole test suite reports that exact same line. With `t.Helper()` added, the same failure reports the actual call site:

```
--- FAIL: TestAdd/intAddition (0.00s)
    main_test.go:65: [ASSERT-FAILED] - 6 != 5
```

`main_test.go:65` is the `AssertT(t, result, 5)` line inside `TestAdd` - click it in your editor and you're looking at the exact case that failed, not the helper's internals.

## Writing Better Test Cases with Generics

Generics not only simplify the `AssertT` function but also enable us to write more flexible and reusable test cases. Consider the following test cases for different types:

```go
type (
	TestCase[T comparable, V comparable] struct {
		A, B T
		R    V
	}
	User struct {
		ID   int
		Name string
	}
)

func Add[T constraints.Ordered](a, b T) T {
	return a + b
}

var (
	uu = []User{
		{ID: 1, Name: "User1"},
		{ID: 2, Name: "User2"},
		{ID: 1, Name: "User1"},
	}
	tcInt   = []TestCase[int, int]{{1, 2, 3}, {10, 2, 12}}
	tcStr   = []TestCase[string, string]{{"hello", "world", "helloworld"}, {"pocket", "base", "pocketbase"}}
	tcUsers = []TestCase[User, bool]{
		{uu[0], uu[2], true},
		{uu[1], uu[2], false},
	}
)
```

These test cases are used in our tests as follows:

```go
// int
t.Run("intWithAssertT", func(t *testing.T) {
    for _, tc := range tcInt {
        Assert(t, Add(tc.A, tc.B), tc.R)
    }
})

// string
t.Run("strWithAssertT", func(t *testing.T) {
    for _, tc := range tcStr {
        Assert(t, Add(tc.A, tc.B), tc.R)
    }
})

// users
t.Run("userWithAssertT", func(t *testing.T) {
    for _, tc := range tcUsers {
        AssertT(t, tc.A == tc.B, tc.R) // direct comparison of structures (User satisfies the comparable requirement)
    }
})
```

The use of generics allows us to write one set of test logic that can be applied to different types (`int`, `string`, etc.), making our tests more concise and reducing code duplication.

## Benchmarks Need No Framework Either

The same standard-library-only approach covers performance testing. `testing.B` doesn't need `AssertT` or any helper at all - just a loop and `b.N`:

```go
func BenchmarkAssert(b *testing.B) {
    for i := 0; i < b.N; i++ {
        Assert(nil, 2+2, 4)
    }
}

func BenchmarkAssertT(b *testing.B) {
    for i := 0; i < b.N; i++ {
        AssertT(nil, 2+2, 4)
    }
}
```

Running `go test -bench=. -benchmem` on both is actually a good way to see the reflection overhead mentioned earlier made concrete: `Assert` (via `reflect.DeepEqual`) allocates and runs measurably slower per operation than `AssertT`'s direct `==` comparison. No framework needed to prove the point you already suspected from reading the code.

If you'd rather see generics applied to a different everyday problem, [Simple Concurrent Web Scraping in Go]({{< ref "simple-concurrent-web-scraping-in-go.md" >}}) uses the same `[T any]` pattern for a generic data exporter instead of a generic assertion.

## Conclusion

By leveraging Go's standard library, generics, and testing features like `testing.Helper()`, we can create a powerful, type-safe, and efficient testing solution without relying on external frameworks. This approach not only reduces dependencies but also deepens our understanding of Go's capabilities.

Remember, the goal of testing is to ensure code correctness and maintainability. Whether you choose to use these techniques or a full-fledged testing framework, the most important thing is to write clear, effective tests that give you confidence in your code.

Happy testing, Gophers!

## Resources

- **Why?**: https://go.dev/doc/faq#assertions
- **Code**: https://github.com/josuebrunel/gopkg/tree/main/assert
