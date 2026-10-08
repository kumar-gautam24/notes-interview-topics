# 01 · DSA Pack (C++)

Screening feedback: **coding 4/5. Good problem solving and C++; improve the recursive Fibonacci.**
So the fix isn't harder problems, it's *showing the optimisation path out loud*. All code below is tested in [solutions.cpp](code/solutions.cpp) (`g++ -std=c++17 -O2 solutions.cpp -o sol && ./sol`).

## The 4-step script for every problem
1. **Clarify:** in-place? keep order? empty input? duplicates? what to return if no answer?
2. **Brute force in one line**, with complexity. ("Nested loops, O(n²).")
3. **Optimal idea in one line**, then code. ("Two pointers, O(n) time, O(1) space.")
4. **Dry run** a small example, then edge cases: empty, size 1, all same, all zeros, negatives.

---

## 1. Fibonacci (the one to fix)

**Why naive recursion is bad:** `fib(n-1) + fib(n-2)` recomputes the same values. `fib(5)` computes `fib(3)` twice and `fib(2)` three times. The call tree has ~1.618ⁿ nodes, so it's **O(2ⁿ) time** (tight bound O(φⁿ)) and O(n) stack. `fib(50)` takes minutes.

**Walk the interviewer up this ladder:**

| Version | Time | Space | Key idea |
|---|---|---|---|
| Naive recursion | O(2ⁿ) | O(n) stack | Overlapping subproblems recomputed |
| Memoization (top-down DP) | O(n) | O(n) + O(n) stack | Cache each `fib(k)` the first time |
| Tabulation (bottom-up DP) | O(n) | O(n) | Fill `dp[0..n]` left to right, no recursion |
| **Two variables** | **O(n)** | **O(1)** | Only the last two values matter |
| Fast doubling / matrix power | O(log n) | O(log n) | `F(2k)=F(k)(2F(k+1)−F(k))`, `F(2k+1)=F(k)²+F(k+1)²` |

```cpp
// Memoization
long long go(int n, vector<long long>& memo) {
    if (n < 2) return n;
    if (memo[n] != -1) return memo[n];
    return memo[n] = go(n - 1, memo) + go(n - 2, memo);
}

// Tabulation
long long fibTab(int n) {
    if (n < 2) return n;
    vector<long long> dp(n + 1);
    dp[0] = 0; dp[1] = 1;
    for (int i = 2; i <= n; ++i) dp[i] = dp[i - 1] + dp[i - 2];
    return dp[n];
}

// Space-optimised: the default answer
long long fib(int n) {
    long long a = 0, b = 1;
    for (int i = 0; i < n; ++i) { long long t = a + b; a = b; b = t; }
    return a;
}

// O(log n) fast doubling — returns {F(k), F(k+1)}
pair<long long, long long> fibPair(int k) {
    if (k == 0) return {0, 1};
    auto [a, b] = fibPair(k >> 1);
    long long c = a * (2 * b - a), d = a * a + b * b;
    return (k & 1) ? make_pair(d, c + d) : make_pair(c, d);
}
```

**Lines that score:**
- "It has *overlapping subproblems* and *optimal substructure*, so it's DP."
- "`long long` overflows after F(92). For large n, problems ask mod 1e9+7, and fast doubling or matrix exponentiation with mod is O(log n)."
- "Deep recursion risks stack overflow, so for big n I'd use the iterative version."

---

## 2. Right-shift array by 1 (the client's own question)

`[1,2,3,4,5] → [5,1,2,3,4]`. Save the last element, shift right **walking backwards** (walking forwards overwrites values you still need), put it at index 0. **O(n), O(1).**

```cpp
void rightShiftByOne(vector<int>& a) {
    if (a.size() < 2) return;
    int last = a.back();
    for (int i = a.size() - 1; i > 0; --i) a[i] = a[i - 1];
    a[0] = last;
}
```

**Expected follow-up: shift by k.** Repeating k times is O(n·k). Do `k %= n`, then the **reversal trick**: reverse all, reverse first k, reverse rest. O(n), O(1).
`[1,2,3,4,5]`, k=2 → `[5,4,3,2,1]` → `[4,5,3,2,1]` → `[4,5,1,2,3]`. STL shortcut: `std::rotate(a.begin(), a.end() - k, a.end())`; mention it, but write the manual one. Left shift is the mirror.

```cpp
void rightShiftByK(vector<int>& a, int k) {
    int n = a.size(); if (n == 0) return;
    k %= n;
    reverse(a.begin(), a.end());
    reverse(a.begin(), a.begin() + k);
    reverse(a.begin() + k, a.end());
}
```

---

## 3. Move zeroes to end

`[1,2,0,4,3,0,5,0] → [1,2,4,3,5,0,0,0]`, non-zero order preserved.
Brute force: copy non-zeros to a temp array, pad zeros, O(n) space.
**Two pointers:** `w` = slot for the next non-zero; scan with `r`; on non-zero swap into `w`, advance `w`. One pass, stable, **O(n) / O(1)**.

```cpp
void moveZeroes(vector<int>& a) {
    int w = 0;
    for (int r = 0; r < (int)a.size(); ++r)
        if (a[r] != 0) swap(a[w++], a[r]);
}
```

---

## 4. Majority element (> n/2, else −1)

Brute O(n²) · hash map O(n)/O(n) · sort + middle O(n log n).
**Boyer–Moore voting, O(n) / O(1):** same as candidate +1, different −1, at 0 pick a new candidate. A real majority outnumbers everything else combined, so it survives the cancelling.
**Phase 2 is mandatory** on GfG because a majority may not exist: count the candidate again (`[1,1,2,2]` → −1).

```cpp
int majorityElement(const vector<int>& a) {
    int cand = 0, cnt = 0;
    for (int x : a) { if (cnt == 0) cand = x; cnt += (x == cand) ? 1 : -1; }
    return count(a.begin(), a.end(), cand) > (long long)a.size() / 2 ? cand : -1;
}
```
Follow-up: elements appearing > n/3 times → extended Boyer–Moore with 2 candidates.

---

## 5. Element occurring an odd number of times

**XOR all, O(n) / O(1).** `a^a = 0`, `a^0 = a`, order doesn't matter, so pairs cancel and the odd one remains. Alternative: `unordered_map` counts, O(n) space.

```cpp
int oddOccurrence(const vector<int>& a) { int r = 0; for (int x : a) r ^= x; return r; }
```
Follow-up, *two* odd numbers: `x = xor of all = p ^ q`; `bit = x & -x` (lowest set bit); XOR elements with that bit set into one bucket, the rest into another; the buckets give p and q.

---

## 6. Reverse a string

Two pointers, swap, move inward. **O(n) time, O(1) extra** because C++ strings are mutable. `std::reverse(s.begin(), s.end())` is the STL version. (If asked about Python: strings are immutable, so reversal always creates a new string, `s[::-1]`.)

```cpp
void reverseString(string& s) { int i = 0, j = s.size() - 1; while (i < j) swap(s[i++], s[j--]); }
```
Follow-ups: reverse words in a sentence (reverse whole string, then each word), palindrome check (same pointers, compare instead of swap).

---

## 7. Likely next questions (also in solutions.cpp, tested)

| Problem | Approach | Complexity |
|---|---|---|
| Two Sum | `unordered_map<value, index>`; check `target - x` before inserting | O(n) / O(n) |
| Max subarray sum (Kadane) | `cur = max(a[i], cur + a[i])`, track best; handles all-negative | O(n) / O(1) |
| Remove duplicates (sorted) | write pointer, copy when `a[r] != a[w-1]` | O(n) / O(1) |
| Second largest | track `first`, `second` in one pass, skip equals | O(n) / O(1) |
| Valid parentheses | stack of openers, match on close, empty at end | O(n) / O(n) |
| Anagram | `array<int,26>` ++ for s, −− for t, all zero | O(n) / O(1) |

## C++ things to say confidently
- `vector` amortised O(1) `push_back`; `unordered_map` average O(1), worst O(n); `map` O(log n) and ordered.
- Pass big containers by `const&`; `int` overflow → use `long long`; `(long long)a * b` before multiplying.
- `auto [a, b] = ...` structured bindings (C++17), range-for, `std::sort` is O(n log n) introsort.
