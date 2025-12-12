# 🎓 Complete Technical Interview Guide
## Algorithms, Patterns, Problem-Solving & Interview Strategies

---

## 📊 TIME & SPACE COMPLEXITY ANALYSIS

### Big-O Notation Hierarchy
```
O(1) < O(log n) < O(√n) < O(n) < O(n log n) < O(n²) < O(n³) < O(2ⁿ) < O(n!)

Constant < Logarithmic < Square Root < Linear < Linearithmic < Quadratic < Cubic < Exponential < Factorial
```

### Detailed Complexity Guide

#### O(1) - Constant Time
```
Operations:
- Array/vector access by index: arr[i]
- HashMap/unordered_map get/put: map[key]
- HashSet/unordered_set contains: set.contains(x)
- Stack/Queue push/pop
- Arithmetic operations: +, -, *, /, %
- Comparison operations: <, >, ==

Examples:
✓ Accessing element in array
✓ Inserting at end of vector (amortized)
✓ Hash table operations (average case)
```

#### O(log n) - Logarithmic Time
```
Operations:
- Binary search in sorted array
- Insert/delete/search in balanced BST (TreeMap, TreeSet)
- Heap push/pop operations
- Finding GCD using Euclidean algorithm
- Exponentiation by squaring

Why log n?
Each operation cuts the problem size in half (or constant factor)

Examples:
✓ Binary search: [1,2,3,4,5,6,7,8] → Check middle → [5,6,7,8] → Check middle → [7,8]
✓ Tree height in balanced tree
```

#### O(√n) - Square Root Time
```
Operations:
- Prime checking (trial division up to √n)
- Finding divisors of n
- Square root algorithms

Examples:
✓ isPrime(n): Only check divisors up to √n
✓ Count divisors of n
```

#### O(n) - Linear Time
```
Operations:
- Single loop through array
- Linear search
- Finding min/max in unsorted array
- Counting occurrences
- Two pointers on array
- Sliding window (each element visited at most twice)

Examples:
✓ Sum of array elements
✓ Find maximum element
✓ Check if array contains element
```

#### O(n log n) - Linearithmic Time
```
Operations:
- Efficient sorting: Merge Sort, Heap Sort, Quick Sort (average)
- Building balanced BST from sorted array
- Divide and conquer algorithms

Why n log n?
- Divide problem into log n levels
- Each level processes n elements

Examples:
✓ Sorting an array
✓ Finding median (requires sorting)
✓ Merge K sorted lists
```

#### O(n²) - Quadratic Time
```
Operations:
- Nested loops over same array
- Bubble sort, Selection sort, Insertion sort
- Comparing all pairs
- Simple string matching

Examples:
✓ Check all pairs in array
✓ Matrix operations (n×n matrix)
✓ Simple path finding in graph
```

#### O(n³) - Cubic Time
```
Operations:
- Triple nested loops
- Matrix multiplication (naive)
- Floyd-Warshall algorithm (all pairs shortest path)

Examples:
✓ Check all triplets in array
✓ Some DP problems with 3D states
```

#### O(2ⁿ) - Exponential Time
```
Operations:
- Generate all subsets
- Recursive Fibonacci (without memoization)
- Backtracking problems (worst case)
- Brute force on all combinations

Examples:
✓ All subsets of array: [1,2,3] → [], [1], [2], [3], [1,2], [1,3], [2,3], [1,2,3]
✓ N-Queens problem
✓ Sudoku solver
```

#### O(n!) - Factorial Time
```
Operations:
- Generate all permutations
- Traveling salesman problem (brute force)

Examples:
✓ All permutations of array: [1,2,3] → 3! = 6 permutations
✓ Trying all orderings
```

### Space Complexity

```
O(1) - Constant Space:
- Few variables
- In-place algorithms
Example: Swap two numbers

O(log n) - Logarithmic Space:
- Recursion depth in binary search
- Balanced tree height
Example: Binary search (recursive)

O(n) - Linear Space:
- Array/list storing n elements
- Hash map with n entries
- Recursion depth in linear recursion
Example: Merge sort (temporary array)

O(n²) - Quadratic Space:
- 2D matrix
- Graph adjacency matrix
Example: Dynamic programming 2D table
```

### How to Calculate Complexity

#### Method 1: Count Operations
```cpp
// Example 1: Single loop = O(n)
for(int i = 0; i < n; i++) {
    // O(1) operation
}
// Total: n × O(1) = O(n)

// Example 2: Nested loops = O(n²)
for(int i = 0; i < n; i++) {
    for(int j = 0; j < n; j++) {
        // O(1) operation
    }
}
// Total: n × n × O(1) = O(n²)

// Example 3: Loop with halving = O(log n)
while(n > 1) {
    n = n / 2;
}
// n, n/2, n/4, ..., 1 = log₂(n) iterations
```

#### Method 2: Recurrence Relations
```
T(n) = T(n/2) + O(1)      → O(log n)  [Binary Search]
T(n) = 2T(n/2) + O(n)     → O(n log n) [Merge Sort]
T(n) = T(n-1) + O(1)      → O(n)      [Linear Recursion]
T(n) = 2T(n-1) + O(1)     → O(2ⁿ)     [Fibonacci (naive)]
```

### Best, Average, Worst Case

```
Algorithm           Best Case    Average Case    Worst Case
-----------------------------------------------------------------
Binary Search       O(1)         O(log n)        O(log n)
Quick Sort          O(n log n)   O(n log n)      O(n²)
Merge Sort          O(n log n)   O(n log n)      O(n log n)
Hash Table Get      O(1)         O(1)            O(n)
Binary Search Tree  O(log n)     O(log n)        O(n)
```

### Amortized Analysis

```
Operation that is expensive occasionally but cheap most of the time.

Example: Vector push_back
- Usually O(1) when capacity available
- Occasionally O(n) when resize needed
- Amortized O(1) because resize happens rarely
```

---

## 🎯 ALGORITHM PARADIGMS

### 1. BRUTE FORCE
```
Approach: Try all possible solutions
Time: Usually O(2ⁿ) or O(n!)
Use when: Small input size (n ≤ 20)

Example Problems:
- Generate all subsets
- Find all permutations
- N-Queens problem

When to use:
✓ Problem size is very small
✓ No better algorithm exists
✓ Need to verify correctness of optimized solution
```

### 2. GREEDY ALGORITHMS
```
Approach: Make locally optimal choice at each step
Key: Greedy choice property + optimal substructure
Time: Usually O(n) to O(n log n)

Example Problems:
✓ Coin change (specific denominations)
✓ Activity selection / Meeting rooms
✓ Huffman coding
✓ Fractional knapsack
✓ Minimum spanning tree (Kruskal, Prim)

Pattern Recognition:
- "Maximize/minimize" problems
- Can make choice without looking ahead
- Choice doesn't need to be reconsidered

How to verify greedy works:
1. Exchange argument
2. Stays ahead argument
3. Prove optimal substructure

Common Greedy Strategies:
- Sort first, then iterate
- Use heap for optimal selection
- Process in specific order
```

### 3. DIVIDE & CONQUER
```
Approach: 
1. Divide problem into subproblems
2. Conquer subproblems recursively
3. Combine solutions

Time: Often O(n log n)

Example Problems:
✓ Merge Sort: Divide → Sort halves → Merge
✓ Quick Sort: Partition → Sort halves
✓ Binary Search: Check middle → Search half
✓ Closest pair of points
✓ Karatsuba multiplication

Pattern Recognition:
- Problem can be divided into similar subproblems
- Solutions can be combined efficiently
- Subproblems are independent

Template:
solve(problem):
    if base case: return solution
    
    left = solve(left_half)
    right = solve(right_half)
    
    return combine(left, right)
```

### 4. DYNAMIC PROGRAMMING
```
Approach: Break down into overlapping subproblems + memoization
Key: Optimal substructure + overlapping subproblems
Time: Usually O(n), O(n²), or O(n³)

When to use DP:
✓ Problem has optimal substructure
✓ Subproblems overlap (solve same thing multiple times)
✓ Greedy doesn't work (need to try multiple options)

Two Approaches:

1. Top-Down (Memoization):
   - Start with original problem
   - Recursively break down
   - Store results in memo table
   
   def solve(n, memo):
       if n in memo: return memo[n]
       if base_case: return value
       memo[n] = solve(subproblem, memo)
       return memo[n]

2. Bottom-Up (Tabulation):
   - Start with base cases
   - Build up to answer
   - Use DP table
   
   dp[0] = base_case
   for i in range(1, n+1):
       dp[i] = f(dp[i-1], dp[i-2], ...)
   return dp[n]

Common DP Patterns:
```

#### 1D DP Patterns
```
✓ Fibonacci-style: dp[i] = dp[i-1] + dp[i-2]
  Problems: Climbing stairs, House robber
  
✓ Max/Min to reach: dp[i] = min/max(dp[i-1], dp[i-2]) + cost[i]
  Problems: Min cost climbing stairs, Jump game
  
✓ Count ways: dp[i] = sum of ways to reach i
  Problems: Decode ways, Coin change II
```

#### 2D DP Patterns
```
✓ Grid paths: dp[i][j] = dp[i-1][j] + dp[i][j-1]
  Problems: Unique paths, Minimum path sum
  
✓ String matching: dp[i][j] based on s1[i] and s2[j]
  Problems: Edit distance, LCS, LIS
  
✓ Knapsack: dp[i][w] = max(dp[i-1][w], dp[i-1][w-weight[i]] + value[i])
  Problems: 0/1 knapsack, Subset sum, Partition equal subset
```

#### DP on Trees
```
✓ Tree DP: Process subtrees first
  Problems: Tree diameter, House robber III, Binary tree cameras
```

#### State Machine DP
```
✓ Multiple states: dp[i][state]
  Problems: Stock buy/sell, Paint house
```

### 5. BACKTRACKING
```
Approach: Try all possibilities, backtrack when constraint violated
Pattern: Build solution incrementally, undo when dead end

Template:
void backtrack(state, choices):
    if is_solution(state):
        add to results
        return
    
    for choice in choices:
        if is_valid(choice):
            make_choice(state, choice)
            backtrack(new_state, remaining_choices)
            undo_choice(state, choice)  // Backtrack

Example Problems:
✓ Generate all subsets/permutations/combinations
✓ N-Queens
✓ Sudoku solver
✓ Word search
✓ Palindrome partitioning

Time Complexity: Usually O(2ⁿ) or O(n!)
Space: O(n) for recursion stack

Optimization Techniques:
- Pruning: Skip branches that can't lead to solution
- Memoization: Cache results (DP + Backtracking)
- Constraint propagation: Eliminate invalid choices early
```

### 6. SLIDING WINDOW
```
Approach: Maintain window of elements, slide through array
Pattern: Two pointers (left, right) defining window

Types:

1. Fixed Size Window:
   for right in range(n):
       add arr[right] to window
       if right >= k-1:
           process window
           remove arr[right-k+1] from window

2. Variable Size Window:
   left = 0
   for right in range(n):
       add arr[right] to window
       while window_invalid():
           remove arr[left] from window
           left++
       update answer

Example Problems:
✓ Maximum sum subarray of size k (fixed)
✓ Longest substring without repeating characters (variable)
✓ Minimum window substring (variable)
✓ Sliding window maximum (deque)

Time: O(n) - Each element added and removed once
```

### 7. TWO POINTERS
```
Approach: Use two pointers to traverse array

Patterns:

1. Same Direction:
   slow = 0, fast = 0
   while fast < n:
       // Process
       fast++
       if condition: slow++

2. Opposite Direction:
   left = 0, right = n-1
   while left < right:
       if condition: left++
       else: right--

3. Fast & Slow (Floyd's):
   slow = start, fast = start
   while fast and fast.next:
       slow = slow.next
       fast = fast.next.next

Example Problems:
✓ Two sum (sorted array)
✓ Remove duplicates
✓ Container with most water
✓ Linked list cycle detection
✓ Palindrome check

Time: O(n)
```

### 8. BINARY SEARCH PATTERNS
```
1. Standard Binary Search (exact match):
   left, right = 0, n-1
   while left <= right:
       mid = left + (right-left)//2
       if arr[mid] == target: return mid
       if arr[mid] < target: left = mid+1
       else: right = mid-1

2. Lower Bound (first >= target):
   left, right = 0, n
   while left < right:
       mid = left + (right-left)//2
       if arr[mid] < target: left = mid+1
       else: right = mid

3. Upper Bound (first > target):
   left, right = 0, n
   while left < right:
       mid = left + (right-left)//2
       if arr[mid] <= target: left = mid+1
       else: right = mid

4. Binary Search on Answer:
   left, right = min_answer, max_answer
   while left <= right:
       mid = left + (right-left)//2
       if is_feasible(mid):
           answer = mid
           // Adjust based on minimization/maximization
       else:
           // Adjust search space
```

---

## 🔍 PROBLEM RECOGNITION PATTERNS

### Array/String Problems

#### 1. Subarray Problems
```
Keywords: "contiguous", "subarray", "substring"

Patterns:
✓ Prefix sum: When asking for sum of subarrays
✓ Kadane's algorithm: Maximum subarray sum
✓ Sliding window: Fixed/variable size constraints
✓ Two pointers: Finding pairs/triplets

Examples:
- Maximum subarray sum → Kadane's
- Subarray sum equals k → Prefix sum + hashmap
- Longest substring without repeating → Sliding window
```

#### 2. Subsequence Problems
```
Keywords: "subsequence" (not necessarily contiguous)

Patterns:
✓ Dynamic Programming (usually)
✓ Two pointers (for sorted arrays)
✓ Greedy (sometimes)

Examples:
- Longest increasing subsequence → DP or Binary Search
- Is subsequence → Two pointers
- Number of subsequences → DP
```

#### 3. Palindrome Problems
```
Patterns:
✓ Expand around center
✓ Two pointers
✓ DP (for counting/partitioning)

Examples:
- Longest palindromic substring → Expand around center or DP
- Valid palindrome → Two pointers
- Palindrome partitioning → Backtracking + DP
```

#### 4. Interval Problems
```
Keywords: "merge", "overlap", "intersection"

Pattern:
1. Sort intervals by start time
2. Iterate and merge/process

Examples:
- Merge intervals → Sort + merge
- Insert interval → Sort + merge
- Meeting rooms → Sort + check overlap
```

### Tree Problems

#### 1. Tree Traversal
```
Patterns:
✓ DFS: Inorder, Preorder, Postorder
✓ BFS: Level-order

When to use:
- Need to process nodes level by level → BFS
- Need to go deep first → DFS
- Tree structure problems → Usually DFS
```

#### 2. Tree Path Problems
```
Keywords: "path", "root-to-leaf", "node-to-node"

Patterns:
✓ Backtracking (for all paths)
✓ DFS with state (for specific paths)
✓ Tree DP (for node-to-node paths)

Examples:
- Path sum → DFS with running sum
- Binary tree maximum path sum → Tree DP
- All paths from root to leaf → Backtracking
```

#### 3. Tree Property Problems
```
✓ Height/Depth → DFS returning height
✓ Diameter → Tree DP
✓ Balanced → Check height difference
✓ Symmetric → Mirror comparison
```

### Graph Problems

#### 1. Connectivity
```
✓ Connected components → DFS/BFS or Union-Find
✓ Cycle detection → DFS with colors or Union-Find
✓ Bipartite → BFS/DFS with 2-coloring
```

#### 2. Shortest Path
```
✓ Unweighted graph → BFS
✓ Weighted positive → Dijkstra
✓ Weighted (can be negative) → Bellman-Ford
✓ All pairs → Floyd-Warshall
```

#### 3. Minimum Spanning Tree
```
✓ Kruskal's algorithm (Union-Find)
✓ Prim's algorithm (Priority Queue)
```

#### 4. Topological Sort
```
✓ DFS-based (post-order)
✓ Kahn's algorithm (BFS-based)
Use when: Directed acyclic graph (DAG)
```

---

## 💡 PROBLEM-SOLVING FRAMEWORK

### Step 1: Understand the Problem (5 minutes)
```
Questions to ask:
1. What is the input? What is the output?
2. What are the constraints? (Size limits, value ranges)
3. Edge cases? (Empty input, negative numbers, duplicates)
4. Can I modify input? Do I need to preserve it?
5. Is there a sorted order?
6. Time/space constraints?

Example:
Problem: "Find two numbers that sum to target"
- Input: Array of integers, target integer
- Output: Indices or the numbers themselves?
- Constraints: One solution or all solutions? Can use same element twice?
- Edge cases: Empty array? No solution?
```

### Step 2: Example Analysis (5 minutes)
```
1. Work through given examples manually
2. Create your own test cases:
   - Simple case
   - Edge case (empty, single element)
   - Large case
3. Identify patterns

Example:
Input: [2, 7, 11, 15], target = 9
Output: [0, 1] (2 + 7 = 9)

Pattern observed: Need to find complement (target - current)
```

### Step 3: Pattern Recognition (5 minutes)
```
Ask yourself:
- Have I solved similar problem?
- What category? (Array, Tree, Graph, DP)
- What pattern? (Two pointers, Sliding window, etc.)
- Brute force first: What would naive solution look like?

Example:
Two sum → Hash map pattern (seen this before)
```

### Step 4: Design Solution (10 minutes)
```
1. Start with brute force
   - What's the time/space complexity?
   - Is it acceptable?

2. Optimize
   - Can I use a better data structure?
   - Can I preprocess data?
   - Can I use a known algorithm?

3. Consider trade-offs
   - Time vs Space
   - Code complexity vs Efficiency

Example:
Brute force: O(n²) - Check all pairs
Optimized: O(n) - Use hash map to store complements
```

### Step 5: Code (15-20 minutes)
```
Best practices:
1. Write clean, readable code
2. Use meaningful variable names
3. Add comments for complex logic
4. Handle edge cases first
5. Don't optimize prematurely

Structure:
// Handle edge cases
if (arr.empty()) return result;

// Main logic with clear sections
// 1. Initialize
// 2. Process
// 3. Return result
```

### Step 6: Test (5-10 minutes)
```
Test cases:
1. Given examples
2. Edge cases:
   - Empty input
   - Single element
   - All same elements
   - Minimum/maximum values
3. Your own cases
4. Walk through code line by line

Common bugs to check:
- Off-by-one errors
- Integer overflow
- Null pointer
- Empty data structure
```

### Step 7: Analyze Complexity (2 minutes)
```
Time Complexity:
- Count operations in loops
- Consider recursive calls
- Best/Average/Worst case

Space Complexity:
- Auxiliary data structures
- Recursion stack
- Can it be optimized?

Be ready to explain!
```

---

## 🎯 COMMON INTERVIEW PATTERNS

### Pattern 1: Hash Map for O(1) Lookup
```
Use when: Need to check existence or find complement
Problems: Two sum, Group anagrams, Subarray sum

Template:
map<type, type> seen;
for each element:
    if seen.contains(complement):
        return found
    seen[element] = ...
```

### Pattern 2: Sliding Window
```
Use when: Subarray/substring with constraint
Problems: Longest substring, Max sum subarray

Template (Variable):
left = 0
for right in range(n):
    add right
    while invalid:
        remove left
        left++
    update result
```

### Pattern 3: Two Pointers
```
Use when: Sorted array, finding pairs
Problems: Two sum II, Remove duplicates

Template:
left, right = 0, n-1
while left < right:
    if condition met: return
    adjust pointers
```

### Pattern 4: Fast & Slow Pointers
```
Use when: Cycle detection, find middle
Problems: Linked list cycle, Happy number

Template:
slow = fast = head
while fast and fast.next:
    slow = slow.next
    fast = fast.next.next
    if slow == fast: cycle found
```

### Pattern 5: Binary Search
```
Use when: Sorted array, search space can be divided
Problems: Search insert, Find peak element

Template:
left, right = 0, n-1
while left <= right:
    mid = left + (right-left)//2
    if found: return
    adjust boundaries
```

### Pattern 6: DFS/BFS on Graph
```
Use when: Tree/graph traversal, connectivity
Problems: Number of islands, Word ladder

DFS Template:
def dfs(node):
    if visited[node]: return
    visited[node] = true
    for neighbor in adj[node]:
        dfs(neighbor)

BFS Template:
queue = [start]
visited = {start}
while queue:
    node = queue.pop(0)
    for neighbor in adj[node]:
        if neighbor not in visited:
            visited.add(neighbor)
            queue.append(neighbor)
```

### Pattern 7: Backtracking
```
Use when: Generate all possibilities
Problems: Permutations, N-Queens

Template:
def backtrack(current, remaining):
    if is_solution(current):
        result.append(current.copy())
        return
    
    for choice in remaining:
        if is_valid(choice):
            make_choice(current, choice)
            backtrack(current, new_remaining)
            undo_choice(current, choice)
```

### Pattern 8: Dynamic Programming
```
Use when: Optimal substructure + overlapping subproblems
Problems: Fibonacci, Coin change, LCS

Bottom-Up Template:
dp = [base_case]
for i in range(1, n):
    dp[i] = f(dp[i-1], dp[i-2], ...)
return dp[n]

Top-Down Template:
memo = {}
def solve(n):
    if n in memo: return memo[n]
    if base_case: return value
    memo[n] = f(solve(n-1), solve(n-2), ...)
    return memo[n]
```

---

## ⚠️ COMMON MISTAKES & HOW TO AVOID

### 1. Not Clarifying Requirements
```
❌ Mistake: Jump straight to coding
✅ Fix: Ask clarifying questions first
- Input/output format?
- Edge cases?
- Constraints?
```

### 2. Not Considering Edge Cases
```
❌ Mistake: Only test happy path
✅ Fix: Always consider:
- Empty input
- Single element
- All same elements
- Minimum/maximum values
- Null/undefined
```

### 3. Off-by-One Errors
```
❌ Mistake: for(i = 0; i <= n; i++)  // Goes out of bounds
✅ Fix: 
- Use i < n for 0-indexed arrays
- Draw examples on paper
- Test with small inputs
```

### 4. Integer Overflow
```
❌ Mistake: int mid = (left + right) / 2;  // Can overflow
✅ Fix: int mid = left + (right - left) / 2;

❌ Mistake: int result = a * b;
✅ Fix: long long result = (long long)a * b;
```

### 5. Modifying Input When Shouldn't
```
❌ Mistake: Sort array without checking if allowed
✅ Fix: Ask if input modification is allowed
       If not, create a copy
```

### 6. Not Handling Duplicates
```
❌ Mistake: Assume all elements are unique
✅ Fix: Check problem statement
       Handle duplicates if needed
```

### 7. Using Wrong Data Structure
```
❌ Mistake: Using vector when set is better
✅ Fix: Choose data structure based on operations:
- Need fast lookup? → Hash map/set
- Need sorted order? → Tree map/set
- Need fast insert/delete? → Linked list
```

### 8. Not Optimizing Space
```
❌ Mistake: Using O(n²) space when O(n) possible
✅ Fix: After solving with extra space,
       Ask: Can I reduce space complexity?
```

### 9. Recursive Stack Overflow
```
❌ Mistake: Deep recursion without base case check
✅ Fix: 
- Always have clear base case
- Consider iterative approach for deep recursion
- Use memoization to reduce calls
```

### 10. Not Testing Code
```
❌ Mistake: Say "I think this works"
✅ Fix: Walk through code with test case
       Trace variables step by step
```

---

## 🗣️ COMMUNICATION DURING INTERVIEW

### DO's
```
✅ Think aloud - Share your thought process
✅ Ask clarifying questions
✅ Start with brute force, then optimize
✅ Explain your approach before coding
✅ Use meaningful variable names
✅ Test your code with examples
✅ Discuss time/space complexity
✅ Be receptive to hints
✅ Admit when stuck and ask for help
```

### DON'Ts
```
❌ Don't stay silent
❌ Don't memorize solutions word-for-word
❌ Don't give up immediately when stuck
❌ Don't argue with interviewer
❌ Don't write sloppy code
❌ Don't skip testing
❌ Don't lie about knowing something
```

### How to Handle Being Stuck
```
1. Reread problem - Did you miss something?
2. Work through another example
3. Think about similar problems you've solved
4. Explain where you're stuck to interviewer
5. Ask for a hint (if really stuck)
6. Try brute force first
```

### Example Communication Flow
```
Interviewer: "Find the longest substring without repeating characters"

You: "Let me clarify - so we want the length of the longest substring 
     where all characters are unique, correct?"

Interviewer: "Yes"

You: "And can the string contain any characters, or just lowercase letters?"

Interviewer: "Any ASCII characters"

You: "Great. Let me work through an example...
     For 'abcabcbb', the answer would be 3 ('abc')
     For 'bbbbb', it would be 1 ('b')
     
     I'm thinking of using a sliding window approach with a hash set
     to track characters in current window. 
     
     Time would be O(n) since we visit each character at most twice.
     Space would be O(min(n, m)) where m is charset size.
     
     Does this approach sound reasonable?"

Interviewer: "Yes, proceed"

You: [Start coding while explaining each section]
```

---

## 📚 INTERVIEW QUESTION DIFFICULTY LEVELS

### Easy (10-15 minutes)
```
Characteristics:
- Direct application of basic data structure
- Single technique needed
- Small number of edge cases

Common topics:
- Array manipulation
- String operations
- Simple recursion
- Basic math

Examples:
- Two Sum
- Valid Parentheses
- Reverse Linked List
- Maximum Subarray
```

### Medium (20-30 minutes)
```
Characteristics:
- Combination of techniques
- Requires optimization thinking
- Multiple edge cases
- May need custom data structure

Common topics:
- Two pointers
- Sliding window
- DFS/BFS
- DP (simple)
- Binary search variants

Examples:
- Longest Substring Without Repeating Characters
- 3Sum
- Container With Most Water
- Course Schedule
- Coin Change
```

### Hard (35-45 minutes)
```
Characteristics:
- Complex algorithm required
- Multiple techniques combined
- Tricky edge cases
- Advanced data structures

Common topics:
- Advanced DP
- Complex graph algorithms
- Hard greedy proofs
- Segment trees / Trie

Examples:
- Median of Two Sorted Arrays
- Regular Expression Matching
- Merge K Sorted Lists
- Word Ladder II
- Alien Dictionary
```

---

## 🎯 FINAL TIPS FOR SUCCESS

### Before Interview
```
1. Practice consistently (not just before interview)
2. Do mock interviews
3. Review fundamental data structures
4. Sleep well night before
5. Prepare questions to ask interviewer
```

### During Interview
```
1. Stay calm and think clearly
2. Manage your time (don't spend 30 min on easy question)
3. Write clean, bug-free code
4. Test thoroughly
5. Be humble and collaborative
```

### After Each Problem
```
1. Review solution even if you solved it
2. Learn the optimal approach
3. Understand why it works
4. Practice similar problems
5. Note down patterns
```

### Growth Mindset
```
✓ Every failed interview is a learning opportunity
✓ Focus on progress, not perfection
✓ Consistent practice beats cramming
✓ Understand concepts, don't memorize
✓ Ask for feedback after interviews
```

---

## 📖 RECOMMENDED PRACTICE STRATEGY

### Week 1-2: Foundations
```
Focus on:
- Arrays and Strings (20 problems)
- Hash Maps and Sets (10 problems)
- Two Pointers (10 problems)

Goal: Master O(n) and O(1) operations
```

### Week 3-4: Core Algorithms
```
Focus on:
- Sorting and Searching (15 problems)
- Recursion and Backtracking (15 problems)
- Stacks and Queues (10 problems)

Goal: Understand recursion deeply
```

### Week 5-6: Trees and Graphs
```
Focus on:
- Binary Trees (20 problems)
- Binary Search Trees (10 problems)
- Graphs DFS/BFS (15 problems)

Goal: Master tree/graph traversal
```

### Week 7-8: Dynamic Programming
```
Focus on:
- 1D DP (15 problems)
- 2D DP (15 problems)
- DP on Trees (10 problems)

Goal: Recognize DP patterns
```

### Week 9-10: Advanced Topics
```
Focus on:
- Heaps and Priority Queues (10 problems)
- Union-Find (10 problems)
- Sliding Window Advanced (10 problems)
- Trie (5 problems)

Goal: Handle complex data structures
```

### Daily Practice Schedule
```
Weekday (1-1.5 hours):
- 1 Easy problem (15 min)
- 1 Medium problem (30-45 min)

Weekend (2-3 hours):
- 1 Easy (15 min)
- 2 Medium (1 hour)
- 1 Hard (1 hour)
- Review past problems

Key: Consistency > Quantity
```

---

**Remember: The goal is not just to solve problems, but to develop problem-solving intuition!** 🚀

Good luck with your interviews! 💪
