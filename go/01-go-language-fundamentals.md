# Go Language Fundamentals — Complete Guide
### For Flutter/Dart Developers Transitioning to Backend

---

## 1. Why Go? (Context for a Flutter Dev)

In Flutter, Dart handles everything — UI, logic, state, networking. In backend, Go plays a similar role to what Dart does in Flutter but for servers. Think of it this way:

| Flutter/Dart World | Go Backend World |
|---|---|
| `main.dart` entry point | `main.go` entry point |
| Packages via `pubspec.yaml` | Modules via `go.mod` |
| `dart run` | `go run main.go` |
| Compiled to native (AOT) | Compiled to native binary |
| Null safety | No null — uses zero values |
| `async/await` | Goroutines & Channels |
| Isolates | Goroutines (much lighter) |

Go is **statically typed**, **compiled**, and built for **concurrency** — perfect for APIs, microservices, and backend systems.

---

## 2. Setup & Environment

### Install Go

```bash
# macOS
brew install go

# Ubuntu/Debian
sudo apt install golang-go

# Or download from https://go.dev/dl/
```

### Verify Installation

```bash
go version
# go version go1.22.0 linux/amd64

go env GOPATH
# /home/yourname/go
```

### Project Structure (Go Modules)

```bash
mkdir my-api && cd my-api
go mod init github.com/gautam/my-api
```

This creates `go.mod` — similar to `pubspec.yaml`:

```
module github.com/gautam/my-api

go 1.22
```

### Your First Go Program

```go
// main.go
package main

import "fmt"

func main() {
    fmt.Println("Hello from Go!")
}
```

```bash
go run main.go      # Run directly (like dart run)
go build main.go    # Compile to binary (like flutter build)
./main              # Execute the binary
```

> **Key Difference from Dart:** Go compiles to a **single static binary**. No runtime needed. You can copy that one file to any server and it just works. This is massive for deployment.

---

## 3. Variables & Types

### Declaration Styles

```go
package main

import "fmt"

func main() {
    // Style 1: Full declaration (like Dart's explicit typing)
    var name string = "Gautam"

    // Style 2: Type inferred (like Dart's var)
    var age = 25

    // Style 3: Short declaration — MOST COMMON (only inside functions)
    city := "Bangalore"

    // Constants (like Dart's const/final)
    const pi = 3.14159

    fmt.Println(name, age, city, pi)
}
```

### Dart vs Go Type Comparison

```go
// Dart                    // Go
// String name = "Go"      var name string = "Go"     or  name := "Go"
// int age = 25             var age int = 25           or  age := 25
// double pi = 3.14         var pi float64 = 3.14      or  pi := 3.14
// bool active = true       var active bool = true     or  active := true
// List<int> nums           var nums []int             (slices, covered later)
// Map<String,int>          var m map[string]int       (maps, covered later)
```

### Zero Values (Go Has NO null)

This is a **critical difference** from Dart. In Dart, you have `null`. In Go, every type has a **zero value**:

```go
func main() {
    var s string   // ""  (empty string, NOT null)
    var n int      // 0
    var f float64  // 0.0
    var b bool     // false
    var p *int     // nil (only pointers, interfaces, slices, maps, channels)

    fmt.Println(s, n, f, b, p)
    // Output:  0 0 false <nil>
}
```

> **Flutter Mental Model:** In Dart, `String? name` can be null. In Go, `var name string` is always `""` — never null. Only pointers can be `nil`.

### Multiple Declaration

```go
// Declare multiple at once
var (
    firstName string = "Gautam"
    lastName  string = "Kumar"
    age       int    = 25
)

// Multiple return values — Go uses this EVERYWHERE
a, b := 10, 20
```

### Type Conversions (No Implicit Casting)

```go
// Go NEVER converts types implicitly — you must be explicit
var i int = 42
var f float64 = float64(i)    // int -> float64
var u uint = uint(f)          // float64 -> uint

// String conversions
import "strconv"
s := strconv.Itoa(42)        // int -> string = "42"
n, err := strconv.Atoi("42") // string -> int (returns error too!)
```

---

## 4. Control Flow

### If-Else

```go
// Standard
if age >= 18 {
    fmt.Println("Adult")
} else if age >= 13 {
    fmt.Println("Teen")
} else {
    fmt.Println("Child")
}

// Go special: Init statement in if (very common pattern)
// Like declaring a variable ONLY for the if-else scope
if err := doSomething(); err != nil {
    fmt.Println("Error:", err)
    // err is only available inside this if-else block
}
```

> **Dart Comparison:** In Dart you'd write `if (condition)` with parentheses. In Go, **no parentheses** around condition but **braces are mandatory**.

### For Loop (Go's ONLY loop — no while, no do-while)

```go
// Standard for loop (like C/Dart)
for i := 0; i < 10; i++ {
    fmt.Println(i)
}

// While-style loop
count := 0
for count < 10 {
    count++
}

// Infinite loop (like while(true))
for {
    // do forever
    break // use break to exit
}

// Range loop (like Dart's for-in)
nums := []int{10, 20, 30}
for index, value := range nums {
    fmt.Printf("Index: %d, Value: %d\n", index, value)
}

// If you don't need the index, use _
for _, value := range nums {
    fmt.Println(value)
}

// Range over map
m := map[string]int{"a": 1, "b": 2}
for key, value := range m {
    fmt.Printf("%s: %d\n", key, value)
}

// Range over string (gives runes/characters)
for i, ch := range "Hello" {
    fmt.Printf("%d: %c\n", i, ch)
}
```

### Switch

```go
// Go switch — NO fallthrough by default (opposite of C/C++)
// No break needed!
day := "Monday"
switch day {
case "Monday":
    fmt.Println("Start of week")
case "Friday":
    fmt.Println("TGIF")
case "Saturday", "Sunday": // Multiple matches
    fmt.Println("Weekend!")
default:
    fmt.Println("Midweek")
}

// Switch with no condition (clean if-else chain)
hour := 15
switch {
case hour < 12:
    fmt.Println("Morning")
case hour < 17:
    fmt.Println("Afternoon")
default:
    fmt.Println("Evening")
}

// Type switch (used with interfaces — covered later)
var val interface{} = "hello"
switch v := val.(type) {
case string:
    fmt.Println("String:", v)
case int:
    fmt.Println("Int:", v)
}
```

---

## 5. Functions

### Basic Functions

```go
// Simple function
func greet(name string) string {
    return "Hello, " + name
}

// Multiple parameters of same type
func add(a, b int) int {
    return a + b
}

// MULTIPLE RETURN VALUES — Go's signature feature
// This is how Go handles errors (no try-catch!)
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, fmt.Errorf("cannot divide by zero")
    }
    return a / b, nil
}

func main() {
    result, err := divide(10, 3)
    if err != nil {
        fmt.Println("Error:", err)
        return
    }
    fmt.Println("Result:", result)
}
```

> **Critical Concept:** Go has **no exceptions, no try-catch**. Errors are just values returned from functions. You check them with `if err != nil`. This is the #1 pattern you'll use in Go.

### Named Return Values

```go
func rectangleProps(length, width float64) (area, perimeter float64) {
    area = length * width
    perimeter = 2 * (length + width)
    return // "naked return" — returns named values
}
```

### Variadic Functions (Like Dart's ... spread)

```go
func sum(nums ...int) int {
    total := 0
    for _, n := range nums {
        total += n
    }
    return total
}

func main() {
    fmt.Println(sum(1, 2, 3))       // 6
    fmt.Println(sum(1, 2, 3, 4, 5)) // 15

    nums := []int{1, 2, 3}
    fmt.Println(sum(nums...))        // Spread a slice with ...
}
```

### Functions as Values (First-Class Functions)

```go
// Functions are first-class citizens, like in Dart
func applyOp(a, b int, op func(int, int) int) int {
    return op(a, b)
}

func main() {
    add := func(a, b int) int { return a + b }
    mul := func(a, b int) int { return a * b }

    fmt.Println(applyOp(3, 4, add)) // 7
    fmt.Println(applyOp(3, 4, mul)) // 12
}
```

### Closures

```go
func counter() func() int {
    count := 0
    return func() int {
        count++
        return count
    }
}

func main() {
    next := counter()
    fmt.Println(next()) // 1
    fmt.Println(next()) // 2
    fmt.Println(next()) // 3
}
```

### Defer (Unique to Go — Super Important)

```go
// defer schedules a function call to run AFTER the surrounding function returns
// Think of it like Dart's try-finally block
func readFile() {
    file, err := os.Open("data.txt")
    if err != nil {
        log.Fatal(err)
    }
    defer file.Close() // This runs when readFile() returns, no matter what

    // ... read file content ...
    // file.Close() is guaranteed to run even if there's a panic
}

// Multiple defers run in LIFO (stack) order
func main() {
    defer fmt.Println("1")
    defer fmt.Println("2")
    defer fmt.Println("3")
    // Output: 3, 2, 1
}
```

### Init Functions

```go
// init() runs automatically before main() — used for setup
// Like Dart's static initializers
func init() {
    fmt.Println("Initializing...")
    // setup database connections, load configs, etc.
}

func main() {
    fmt.Println("Main running")
}
// Output:
// Initializing...
// Main running
```

---

## 6. Data Structures

### Arrays (Fixed Size — Rarely Used Directly)

```go
// Arrays have FIXED size — part of the type
var arr [5]int                    // [0, 0, 0, 0, 0]
arr2 := [3]string{"a", "b", "c"}
arr3 := [...]int{1, 2, 3}        // Compiler counts: size = 3
```

### Slices (Dynamic — What You'll Actually Use)

```go
// Slices are like Dart's List<T> — dynamic, flexible
nums := []int{1, 2, 3, 4, 5}

// Accessing elements
fmt.Println(nums[0])   // 1
fmt.Println(nums[1:3]) // [2, 3] (slicing, like Python/Dart sublist)

// Append (like Dart's .add())
nums = append(nums, 6, 7)

// Length and Capacity
fmt.Println(len(nums)) // 7 (current length)
fmt.Println(cap(nums)) // capacity (underlying array size)

// Make a slice with specific length and capacity
s := make([]int, 5)     // length=5, capacity=5 (all zeros)
s2 := make([]int, 0, 10) // length=0, capacity=10 (empty but pre-allocated)

// Copy a slice (shallow copy)
src := []int{1, 2, 3}
dst := make([]int, len(src))
copy(dst, src)

// Remove element at index i
i := 2
nums = append(nums[:i], nums[i+1:]...)

// Nil slice vs empty slice
var nilSlice []int        // nil, len=0, cap=0
emptySlice := []int{}     // not nil, len=0, cap=0
// Both work with append, len, range — but nil checks differ
```

> **Slice Gotcha:** Slices are **reference types**. When you slice a slice, both share the same underlying array. Modifying one can affect the other!

```go
original := []int{1, 2, 3, 4, 5}
sub := original[1:3] // [2, 3] — shares memory with original
sub[0] = 99
fmt.Println(original) // [1, 99, 3, 4, 5] — original is modified!

// To avoid this, use copy() or append to a new slice
safe := make([]int, len(sub))
copy(safe, sub) // Now safe is independent
```

### Maps (Like Dart's Map)

```go
// Declaration
ages := map[string]int{
    "Alice": 30,
    "Bob":   25,
}

// Or with make
scores := make(map[string]int)
scores["math"] = 95
scores["science"] = 88

// Access (returns zero value if key doesn't exist)
age := ages["Alice"]       // 30
unknown := ages["Charlie"] // 0 (zero value for int)

// Check if key exists — IMPORTANT PATTERN
age, exists := ages["Charlie"]
if !exists {
    fmt.Println("Charlie not found")
}

// Delete
delete(ages, "Bob")

// Iterate (order is NOT guaranteed — unlike Dart's LinkedHashMap)
for name, age := range ages {
    fmt.Printf("%s is %d\n", name, age)
}

// Length
fmt.Println(len(ages))
```

> **Dart Comparison:** Dart maps are ordered (insertion order). Go maps are **unordered** — iteration order changes between runs.

---

## 7. Structs (Go's "Classes")

Go has **no classes**. Structs are the equivalent. No inheritance, no constructors.

### Basic Struct

```go
// Define a struct (like a Dart class with only fields)
type User struct {
    ID        int
    Name      string
    Email     string
    IsActive  bool
}

func main() {
    // Create instances
    u1 := User{
        ID:       1,
        Name:     "Gautam",
        Email:    "gautam@example.com",
        IsActive: true,
    }

    // Positional (fragile — avoid)
    u2 := User{2, "Alice", "alice@example.com", true}

    // Partial (unset fields get zero values)
    u3 := User{Name: "Bob"} // ID=0, Email="", IsActive=false

    // Access fields
    fmt.Println(u1.Name) // "Gautam"
    u1.Email = "new@email.com" // Mutate
}
```

### Methods on Structs

```go
// Methods are functions with a "receiver" — this is how Go does OOP
type Rectangle struct {
    Width  float64
    Height float64
}

// Value receiver — gets a COPY (like Dart methods)
func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

// Pointer receiver — can MODIFY the original (like Dart, since Dart objects are references)
func (r *Rectangle) Scale(factor float64) {
    r.Width *= factor
    r.Height *= factor
}

func main() {
    rect := Rectangle{Width: 10, Height: 5}
    fmt.Println(rect.Area())  // 50

    rect.Scale(2)
    fmt.Println(rect.Area())  // 200 (modified!)
}
```

> **When to use pointer vs value receiver?**
> - **Pointer receiver `(r *Type)`**: When the method modifies the struct, or when the struct is large (avoids copying)
> - **Value receiver `(r Type)`**: When the method only reads data and the struct is small
> - **Rule of thumb**: If any method needs a pointer receiver, make ALL methods use pointer receiver (consistency)

### Constructor Pattern (Go Convention)

```go
// Go has no constructors — use factory functions prefixed with New
type Server struct {
    host string
    port int
}

func NewServer(host string, port int) *Server {
    if port == 0 {
        port = 8080
    }
    return &Server{
        host: host,
        port: port,
    }
}

func main() {
    s := NewServer("localhost", 3000)
    fmt.Println(s.host, s.port)
}
```

### Struct Embedding (Go's "Inheritance")

```go
// Go uses COMPOSITION over inheritance
type Address struct {
    City    string
    Country string
}

type Employee struct {
    Name    string
    Address // Embedded — Employee "has an" Address
    // All Address fields are promoted to Employee
}

func main() {
    emp := Employee{
        Name: "Gautam",
        Address: Address{
            City:    "Bangalore",
            Country: "India",
        },
    }

    // Access embedded fields directly
    fmt.Println(emp.City)    // "Bangalore" (promoted from Address)
    fmt.Println(emp.Country) // "India"
}
```

### Struct Tags (Critical for JSON APIs)

```go
// Tags tell encoders/decoders how to map struct fields
// You'll use these CONSTANTLY for API development
type User struct {
    ID        int    `json:"id"`
    FirstName string `json:"first_name"`
    Email     string `json:"email"`
    Password  string `json:"-"`           // "-" means NEVER include in JSON
    Age       int    `json:"age,omitempty"` // Omit if zero value
}

// When you marshal this to JSON:
// {"id":1,"first_name":"Gautam","email":"g@e.com"}
// Password is excluded, Age is omitted if 0
```

> **Flutter Mental Model:** Struct tags are like what `json_serializable` annotations do in Dart (`@JsonKey(name: 'first_name')`), but built into the language syntax.

---

## 8. Pointers

Go has pointers like C/C++, but **no pointer arithmetic**. Safer than C, more explicit than Dart.

```go
func main() {
    x := 42
    p := &x  // & = "address of" — p is a pointer to x
    fmt.Println(*p)  // * = "dereference" — read value through pointer: 42

    *p = 100  // Modify value through pointer
    fmt.Println(x) // 100 — x is changed!

    // Pointers are useful for:
    // 1. Modifying values in functions
    // 2. Avoiding copies of large structs
    // 3. Indicating "optional" (nil pointer)
}

// Without pointer — function gets a COPY
func doubleCopy(n int) {
    n = n * 2 // Only changes local copy
}

// With pointer — function modifies original
func doublePtr(n *int) {
    *n = *n * 2 // Changes original value
}

func main() {
    val := 10
    doubleCopy(val)
    fmt.Println(val) // Still 10

    doublePtr(&val)
    fmt.Println(val) // Now 20
}
```

> **Dart Comparison:** In Dart, objects (classes) are always passed by reference. Primitives (int, bool) are passed by value. In Go, EVERYTHING is passed by value unless you use pointers. Structs are copied, slices/maps pass a header (but share underlying data).

### Pointer Gotcha with Nil

```go
type Config struct {
    Debug bool
}

func main() {
    var c *Config // nil pointer
    // fmt.Println(c.Debug) // PANIC: nil pointer dereference!

    // Always check for nil
    if c != nil {
        fmt.Println(c.Debug)
    }
}
```

---

## 9. Interfaces (Go's Polymorphism)

This is where Go gets **really different** from Dart. Go interfaces are **implicit** — no `implements` keyword.

### Basic Interface

```go
// Define what something can DO
type Shape interface {
    Area() float64
    Perimeter() float64
}

// Any type that has these methods automatically satisfies the interface
// NO "implements" keyword needed!

type Circle struct {
    Radius float64
}

func (c Circle) Area() float64 {
    return 3.14159 * c.Radius * c.Radius
}

func (c Circle) Perimeter() float64 {
    return 2 * 3.14159 * c.Radius
}

type Rectangle struct {
    Width, Height float64
}

func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

func (r Rectangle) Perimeter() float64 {
    return 2 * (r.Width + r.Height)
}

// Both Circle and Rectangle satisfy Shape interface — automatically!
func printShapeInfo(s Shape) {
    fmt.Printf("Area: %.2f, Perimeter: %.2f\n", s.Area(), s.Perimeter())
}

func main() {
    c := Circle{Radius: 5}
    r := Rectangle{Width: 10, Height: 5}

    printShapeInfo(c) // Works!
    printShapeInfo(r) // Works!
}
```

> **Dart Comparison:**
> - Dart: `class Circle implements Shape { ... }` — explicit
> - Go: Just have the methods. The compiler figures it out. This is called **structural typing** or "duck typing at compile time."

### The Empty Interface (interface{} / any)

```go
// interface{} means "any type" — like Dart's dynamic or Object
// Go 1.18+ added 'any' as an alias
func printAnything(val any) {
    fmt.Println(val)
}

func main() {
    printAnything(42)
    printAnything("hello")
    printAnything(true)
    printAnything([]int{1, 2, 3})
}

// Type assertion — getting the concrete type back
func describe(val any) {
    // Check and extract type
    if str, ok := val.(string); ok {
        fmt.Println("It's a string:", str)
    } else if num, ok := val.(int); ok {
        fmt.Println("It's an int:", num)
    }
}
```

### Common Interfaces (Stringer, Error)

```go
// fmt.Stringer — like Dart's toString()
type User struct {
    Name string
    Age  int
}

func (u User) String() string {
    return fmt.Sprintf("%s (age %d)", u.Name, u.Age)
}

func main() {
    u := User{Name: "Gautam", Age: 25}
    fmt.Println(u) // "Gautam (age 25)" — String() called automatically
}

// error interface — the foundation of Go error handling
type error interface {
    Error() string
}

// Create custom errors
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed on %s: %s", e.Field, e.Message)
}
```

---

## 10. Error Handling (No try-catch!)

This is the **biggest paradigm shift** from Dart. Go treats errors as values, not exceptions.

### The Pattern

```go
// EVERY function that can fail returns an error as the last return value
func fetchUser(id int) (*User, error) {
    if id <= 0 {
        return nil, fmt.Errorf("invalid user ID: %d", id)
    }
    // ... fetch from database
    return &User{ID: id, Name: "Gautam"}, nil
}

func main() {
    user, err := fetchUser(1)
    if err != nil {
        log.Fatal("Failed to fetch user:", err)
    }
    fmt.Println(user.Name)
}
```

### Error Wrapping (Go 1.13+)

```go
import (
    "errors"
    "fmt"
)

// Wrap errors to add context (like a stack trace)
func getUser(id int) (*User, error) {
    user, err := db.FindByID(id)
    if err != nil {
        return nil, fmt.Errorf("getUser(%d): %w", id, err) // %w wraps the error
    }
    return user, nil
}

// Unwrap and check errors
func main() {
    _, err := getUser(1)

    // Check if error is a specific type
    var notFound *NotFoundError
    if errors.Is(err, ErrNotFound) {
        fmt.Println("User not found")
    } else if errors.As(err, &notFound) {
        fmt.Println("Not found:", notFound.Resource)
    }
}
```

### Sentinel Errors

```go
// Define known errors as package-level variables
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
    ErrInternal     = errors.New("internal error")
)

func findUser(id int) (*User, error) {
    if id == 0 {
        return nil, ErrNotFound
    }
    return &User{}, nil
}

// Check with errors.Is()
if errors.Is(err, ErrNotFound) {
    // handle 404
}
```

### Panic & Recover (Use Sparingly)

```go
// panic = like throwing an unrecoverable exception
// Only use for truly unrecoverable situations (not normal errors!)
func mustParseConfig(path string) Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic("config file missing: " + err.Error())
    }
    // ...
}

// recover = catch a panic (like catch in try-catch)
// Only used in middleware, not business logic
func safeHandler() {
    defer func() {
        if r := recover(); r != nil {
            fmt.Println("Recovered from panic:", r)
        }
    }()

    panic("something went wrong")
}
```

> **Rule:** Use `error` returns for expected failures (network issues, invalid input, not found). Use `panic` only for programmer bugs (index out of range, nil pointer that shouldn't be nil).

---

## 11. Goroutines & Channels (Concurrency)

This is Go's **superpower**. Where Dart has Isolates (heavy, separate memory), Go has goroutines (lightweight, shared memory).

### Goroutines

```go
// A goroutine is a lightweight thread — starts with the 'go' keyword
func printNumbers() {
    for i := 1; i <= 5; i++ {
        time.Sleep(100 * time.Millisecond)
        fmt.Println(i)
    }
}

func printLetters() {
    for _, ch := range "abcde" {
        time.Sleep(100 * time.Millisecond)
        fmt.Printf("%c\n", ch)
    }
}

func main() {
    go printNumbers() // Runs concurrently
    go printLetters() // Runs concurrently

    time.Sleep(1 * time.Second) // Wait (bad way — use WaitGroup instead)
}
```

### WaitGroup (Proper Way to Wait)

```go
import "sync"

func worker(id int, wg *sync.WaitGroup) {
    defer wg.Done() // Signal completion when function returns

    fmt.Printf("Worker %d starting\n", id)
    time.Sleep(time.Second)
    fmt.Printf("Worker %d done\n", id)
}

func main() {
    var wg sync.WaitGroup

    for i := 1; i <= 5; i++ {
        wg.Add(1) // Increment counter
        go worker(i, &wg)
    }

    wg.Wait() // Block until all workers are done
    fmt.Println("All workers completed")
}
```

### Channels (Communication Between Goroutines)

```go
// Channels are typed pipes for goroutine communication
// Think of it as a StreamController in Dart

func main() {
    // Create a channel
    ch := make(chan string)

    // Send data in a goroutine
    go func() {
        ch <- "Hello from goroutine!" // Send to channel
    }()

    // Receive data (blocks until data arrives)
    msg := <-ch // Receive from channel
    fmt.Println(msg)
}

// Buffered channels (like a queue with capacity)
func main() {
    ch := make(chan int, 3) // Buffer size 3

    ch <- 1 // Doesn't block (buffer has space)
    ch <- 2
    ch <- 3
    // ch <- 4 // This WOULD block (buffer full)

    fmt.Println(<-ch) // 1
    fmt.Println(<-ch) // 2
}

// Range over channel
func producer(ch chan<- int) { // chan<- = send-only channel
    for i := 0; i < 5; i++ {
        ch <- i
    }
    close(ch) // Signal no more data
}

func main() {
    ch := make(chan int)
    go producer(ch)

    for val := range ch { // Reads until channel is closed
        fmt.Println(val)
    }
}
```

### Select (Switch for Channels)

```go
// select lets you wait on multiple channels
func main() {
    ch1 := make(chan string)
    ch2 := make(chan string)

    go func() {
        time.Sleep(1 * time.Second)
        ch1 <- "result from ch1"
    }()

    go func() {
        time.Sleep(2 * time.Second)
        ch2 <- "result from ch2"
    }()

    // Wait for whichever arrives first
    select {
    case msg := <-ch1:
        fmt.Println(msg)
    case msg := <-ch2:
        fmt.Println(msg)
    case <-time.After(3 * time.Second):
        fmt.Println("Timeout!")
    }
}
```

### Mutex (Protecting Shared Data)

```go
import "sync"

type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Increment() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

func (c *SafeCounter) Value() int {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.count
}
```

---

## 12. Packages & Modules

### Package Rules

```go
// Every Go file starts with a package declaration
package main    // Executable entry point
package utils   // Library package
package models  // Library package

// IMPORTANT naming rules:
// - Package name = folder name
// - Exported (public) = Capitalized    (User, GetName, MaxRetries)
// - Unexported (private) = lowercase   (user, getName, maxRetries)

// In Dart, you use _ prefix for private. In Go, just lowercase first letter.
```

### Project Layout

```
my-api/
├── go.mod
├── go.sum
├── main.go
├── internal/          # Private to this module (can't be imported externally)
│   ├── handlers/
│   │   └── user.go
│   ├── models/
│   │   └── user.go
│   ├── repository/
│   │   └── user_repo.go
│   └── service/
│       └── user_service.go
├── pkg/               # Public packages (can be imported by others)
│   └── utils/
│       └── helpers.go
└── config/
    └── config.go
```

### Importing

```go
import (
    "fmt"                           // Standard library
    "net/http"                      // Standard library (nested)
    "github.com/gin-gonic/gin"     // Third-party (installed via go get)
    "github.com/gautam/my-api/internal/models" // Local package
)

// Alias imports
import (
    "fmt"
    mydb "github.com/gautam/my-api/internal/database" // alias
    _ "github.com/lib/pq"  // Import for side effects only (init() runs)
)
```

### Adding Dependencies

```bash
# Add a package (like pub add in Dart)
go get github.com/gin-gonic/gin

# Tidy up — removes unused, adds missing
go mod tidy

# Vendor dependencies (copy into project)
go mod vendor
```

---

## 13. Generics (Go 1.18+)

```go
// Type parameters — like Dart generics
func Map[T any, U any](slice []T, fn func(T) U) []U {
    result := make([]U, len(slice))
    for i, v := range slice {
        result[i] = fn(v)
    }
    return result
}

func main() {
    nums := []int{1, 2, 3, 4}
    doubled := Map(nums, func(n int) int { return n * 2 })
    fmt.Println(doubled) // [2, 4, 6, 8]

    strs := Map(nums, func(n int) string { return fmt.Sprintf("%d", n) })
    fmt.Println(strs) // ["1", "2", "3", "4"]
}

// Generic struct
type Result[T any] struct {
    Data  T
    Error error
}

// Constraints (restrict what types are allowed)
type Number interface {
    int | int32 | int64 | float32 | float64
}

func Sum[T Number](nums []T) T {
    var total T
    for _, n := range nums {
        total += n
    }
    return total
}
```

---

## 14. Testing

```go
// File: math.go
package math

func Add(a, b int) int {
    return a + b
}

// File: math_test.go (MUST end with _test.go)
package math

import "testing"

func TestAdd(t *testing.T) {
    result := Add(2, 3)
    if result != 5 {
        t.Errorf("Add(2, 3) = %d; want 5", result)
    }
}

// Table-driven tests — Go idiom
func TestAddTable(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        expected int
    }{
        {"positive", 2, 3, 5},
        {"negative", -1, -1, -2},
        {"zero", 0, 0, 0},
        {"mixed", -1, 5, 4},
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            result := Add(tc.a, tc.b)
            if result != tc.expected {
                t.Errorf("Add(%d, %d) = %d; want %d", tc.a, tc.b, result, tc.expected)
            }
        })
    }
}
```

```bash
go test ./...           # Run all tests
go test -v ./...        # Verbose output
go test -cover ./...    # With coverage
go test -bench=. ./...  # Run benchmarks
```

---

## 15. Common Go Commands Cheat Sheet

```bash
# Build & Run
go run main.go          # Compile and run
go build -o myapp       # Compile to binary
go install              # Build and install to $GOPATH/bin

# Modules
go mod init <module>    # Initialize module
go mod tidy             # Clean up dependencies
go get <package>        # Add dependency
go get -u <package>     # Update dependency

# Testing
go test ./...           # Run all tests
go test -v -run TestName ./path  # Run specific test

# Code Quality
go fmt ./...            # Format code (ALWAYS run this)
go vet ./...            # Find common mistakes
golint ./...            # Style suggestions (install separately)

# Documentation
go doc fmt.Println      # Read docs for a function
go doc net/http         # Read docs for a package

# Tools
go generate ./...       # Run code generators
go env                  # Print Go environment
```

---

## Quick Reference: Dart → Go Translation

| Concept | Dart | Go |
|---|---|---|
| Entry point | `void main()` | `func main()` |
| Print | `print("hi")` | `fmt.Println("hi")` |
| String interpolation | `"$name is $age"` | `fmt.Sprintf("%s is %d", name, age)` |
| Null | `null` | `nil` (only for pointers/interfaces/slices/maps) |
| Null check | `if (x != null)` | `if x != nil` |
| Optional | `String?` | `*string` (pointer) |
| List | `List<int>` | `[]int` (slice) |
| Map | `Map<String,int>` | `map[string]int` |
| Class | `class User {}` | `type User struct {}` |
| Constructor | `User(this.name)` | `func NewUser(name string) *User` |
| Method | `void greet()` | `func (u User) Greet()` |
| Interface | `abstract class / implements` | `type X interface{}` (implicit) |
| Private | `_privateName` | `privateName` (lowercase) |
| Public | `publicName` | `PublicName` (uppercase) |
| Async | `Future<T>` / `async/await` | Goroutines + Channels |
| Try-catch | `try {} catch (e) {}` | `if err != nil {}` |
| Package | `pubspec.yaml` | `go.mod` |
| Import | `import 'pkg'` | `import "pkg"` |
| Ternary | `a ? b : c` | No ternary — use if-else |
| Spread | `...list` | `list...` (for variadic funcs) |
| Lambda | `(a) => a * 2` | `func(a int) int { return a * 2 }` |
