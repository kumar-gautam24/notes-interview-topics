# Amazon SDE 1 Interview Last-Minute Preparation Guide

## Table of Contents
1. [Core Data Structures & Algorithms](#core-data-structures--algorithms)
2. [Pattern-Based Problem Solving](#pattern-based-problem-solving)
3. [Dynamic Programming Mastery](#dynamic-programming-mastery)
4. [Graph Algorithms & Techniques](#graph-algorithms--techniques)
5. [Tree Traversal & Manipulation](#tree-traversal--manipulation)
6. [Greedy Algorithms](#greedy-algorithms)
7. [Heap/Priority Queue Techniques](#heappriority-queue-techniques)
8. [Top Amazon SDE 1 Questions by Category](#top-amazon-sde-1-questions-by-category)
9. [C++ Best Practices for Interviews](#c-best-practices-for-interviews)
10. [Last-Minute Strategy & Tips](#last-minute-strategy--tips)

---

## Core Data Structures & Algorithms

### Vector/Array Operations
```cpp
// Time Complexity: O(n) for traversal, O(1) for access by index
// Space Complexity: O(1) for in-place operations
vector<int> nums = {1, 2, 3, 4, 5};

// Two-pointer technique (common for array problems)
int left = 0, right = nums.size() - 1;
while (left < right) {
    // Process elements from both ends
    swap(nums[left], nums[right]);
    left++;
    right--;
}

// Sliding window technique (fixed size k)
int k = 3; // Window size
int windowSum = 0;
for (int i = 0; i < k; i++) {
    windowSum += nums[i];
}
int maxSum = windowSum;
for (int i = k; i < nums.size(); i++) {
    windowSum = windowSum + nums[i] - nums[i - k]; // Add new, remove old
    maxSum = max(maxSum, windowSum);
}
```

### HashMap/Set Usage
```cpp
// Time Complexity: O(1) average for insert/find/erase
// Space Complexity: O(n) for storing n elements
unordered_map<int, int> countMap; // For frequency counting
for (int num : nums) {
    countMap[num]++; // Count frequency
}

// Check if key exists
if (countMap.find(key) != countMap.end()) {
    // Key exists
}

// Using set for quick lookup
unordered_set<int> seen;
for (int num : nums) {
    if (seen.count(num)) {
        // Duplicate found
    }
    seen.insert(num);
}
```

### Linked List Operations
```cpp
struct ListNode {
    int val;
    ListNode* next;
    ListNode(int x) : val(x), next(nullptr) {}
};

// Two-pointer technique for linked lists
// Find middle of linked list - O(n) time, O(1) space
ListNode* findMiddle(ListNode* head) {
    if (!head) return nullptr;
    
    ListNode* slow = head;
    ListNode* fast = head;
    
    while (fast && fast->next) {
        slow = slow->next;      // Move one step
        fast = fast->next->next; // Move two steps
    }
    
    return slow; // Slow is at middle when fast reaches end
}

// Reverse a linked list - O(n) time, O(1) space
ListNode* reverseList(ListNode* head) {
    ListNode* prev = nullptr;
    ListNode* curr = head;
    
    while (curr) {
        ListNode* next = curr->next;
        curr->next = prev; // Reverse link
        prev = curr;
        curr = next;
    }
    
    return prev; // New head
}
```

### Stack and Queue Applications
```cpp
// Stack for problems requiring LIFO order - O(1) operations
stack<int> stack;
stack.push(1);
stack.push(2);
int top = stack.top(); // Gets top without removing
stack.pop();           // Removes top element

// Queue for problems requiring FIFO order - O(1) operations
queue<int> queue;
queue.push(1);
queue.push(2);
int front = queue.front(); // Gets front without removing
queue.pop();              // Removes front element

// Common pattern: using stack to check balanced parentheses
bool isValid(string s) {
    stack<char> stack;
    for (char c : s) {
        if (c == '(' || c == '[' || c == '{') {
            stack.push(c);
        } else {
            if (stack.empty()) return false;
            
            if ((c == ')' && stack.top() == '(') ||
                (c == ']' && stack.top() == '[') ||
                (c == '}' && stack.top() == '{')) {
                stack.pop();
            } else {
                return false;
            }
        }
    }
    return stack.empty();
}
```

---

## Pattern-Based Problem Solving

### Two Pointers Pattern
```cpp
// Two Sum II (sorted array) - O(n) time, O(1) space
vector<int> twoSum(vector<int>& numbers, int target) {
    int left = 0, right = numbers.size() - 1;
    
    while (left < right) {
        int sum = numbers[left] + numbers[right];
        
        if (sum == target) {
            return {left + 1, right + 1}; // 1-indexed result
        } else if (sum < target) {
            left++; // Need a larger sum, move left pointer
        } else {
            right--; // Need a smaller sum, move right pointer
        }
    }
    
    return {}; // No solution found
}

// Remove duplicates from sorted array - O(n) time, O(1) space
int removeDuplicates(vector<int>& nums) {
    if (nums.empty()) return 0;
    
    int writeIdx = 1; // Start from second position
    
    for (int readIdx = 1; readIdx < nums.size(); readIdx++) {
        // If current element is different from previous one
        if (nums[readIdx] != nums[readIdx - 1]) {
            nums[writeIdx++] = nums[readIdx]; // Write it to next position
        }
    }
    
    return writeIdx; // New length
}
```

### Sliding Window Pattern
```cpp
// Maximum sum subarray of size k - O(n) time, O(1) space
int maxSubarraySum(vector<int>& nums, int k) {
    if (nums.size() < k) return -1;
    
    int maxSum = 0;
    int windowSum = 0;
    
    // First window sum
    for (int i = 0; i < k; i++) {
        windowSum += nums[i];
    }
    maxSum = windowSum;
    
    // Slide window and update maximum
    for (int i = k; i < nums.size(); i++) {
        windowSum = windowSum - nums[i - k] + nums[i]; // Remove old, add new
        maxSum = max(maxSum, windowSum);
    }
    
    return maxSum;
}

// Longest substring without repeating characters - O(n) time, O(min(m,n)) space where m is alphabet size
int lengthOfLongestSubstring(string s) {
    int n = s.length();
    unordered_map<char, int> charIndex; // Character -> last seen index
    int maxLength = 0;
    int windowStart = 0;
    
    for (int windowEnd = 0; windowEnd < n; windowEnd++) {
        char rightChar = s[windowEnd];
        
        // If character is in current window, shrink window from left
        if (charIndex.find(rightChar) != charIndex.end() && 
            charIndex[rightChar] >= windowStart) {
            // Move window start to position after the last occurrence
            windowStart = charIndex[rightChar] + 1;
        }
        
        // Update position of current character
        charIndex[rightChar] = windowEnd;
        
        // Update maximum length
        maxLength = max(maxLength, windowEnd - windowStart + 1);
    }
    
    return maxLength;
}
```

### Binary Search Pattern
```cpp
// Classic binary search - O(log n) time, O(1) space
int binarySearch(vector<int>& nums, int target) {
    int left = 0, right = nums.size() - 1;
    
    while (left <= right) {
        int mid = left + (right - left) / 2; // Avoid overflow
        
        if (nums[mid] == target) {
            return mid;
        } else if (nums[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return -1; // Target not found
}

// Find first and last position of target - O(log n) time, O(1) space
vector<int> searchRange(vector<int>& nums, int target) {
    vector<int> result = {-1, -1};
    if (nums.empty()) return result;
    
    // Find first position
    int left = 0, right = nums.size() - 1;
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] >= target) {
            right = mid - 1;
        } else {
            left = mid + 1;
        }
    }
    
    // Check if target exists
    if (left >= nums.size() || nums[left] != target) {
        return result;
    }
    
    result[0] = left;
    
    // Find last position
    right = nums.size() - 1; // Reset right
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (nums[mid] <= target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    result[1] = right;
    
    return result;
}
```

### Fast and Slow Pointers Pattern (for cycles)
```cpp
// Detect cycle in linked list - O(n) time, O(1) space
bool hasCycle(ListNode* head) {
    if (!head || !head->next) return false;
    
    ListNode* slow = head;
    ListNode* fast = head;
    
    while (fast && fast->next) {
        slow = slow->next;       // Move one step
        fast = fast->next->next; // Move two steps
        
        if (slow == fast) return true; // Cycle detected
    }
    
    return false; // No cycle
}

// Find start of cycle - O(n) time, O(1) space
ListNode* detectCycle(ListNode* head) {
    if (!head || !head->next) return nullptr;
    
    // Detect cycle
    ListNode* slow = head;
    ListNode* fast = head;
    bool hasCycle = false;
    
    while (fast && fast->next) {
        slow = slow->next;
        fast = fast->next->next;
        
        if (slow == fast) {
            hasCycle = true;
            break;
        }
    }
    
    if (!hasCycle) return nullptr;
    
    // Find start of cycle
    slow = head;
    while (slow != fast) {
        slow = slow->next;
        fast = fast->next;
    }
    
    return slow; // Start of cycle
}
```

---

## Dynamic Programming Mastery

### Key DP Concepts
1. **Identify Subproblems** - Break down the problem into smaller, overlapping subproblems
2. **Define State** - Determine what information is needed to solve each subproblem
3. **Recursion with Memoization** - Top-down approach by solving subproblems as needed and caching results
4. **Tabulation** - Bottom-up approach by solving all subproblems in a specific order
5. **State Transition** - Define how to move from one state to another

### Converting Recursive to DP Solutions

**Step 1:** Identify the recursive solution first:
```cpp
// Recursive solution for Fibonacci
int fib(int n) {
    if (n <= 1) return n;
    return fib(n-1) + fib(n-2);
}
```

**Step 2:** Add memoization (top-down DP):
```cpp
// Top-down DP for Fibonacci - O(n) time, O(n) space
int fibMemo(int n, vector<int>& memo) {
    if (n <= 1) return n;
    
    // Return cached result if available
    if (memo[n] != -1) return memo[n];
    
    // Compute and cache result
    memo[n] = fibMemo(n-1, memo) + fibMemo(n-2, memo);
    return memo[n];
}

int fib(int n) {
    vector<int> memo(n+1, -1);
    return fibMemo(n, memo);
}
```

**Step 3:** Convert to tabulation (bottom-up DP):
```cpp
// Bottom-up DP for Fibonacci - O(n) time, O(n) space
int fib(int n) {
    if (n <= 1) return n;
    
    vector<int> dp(n+1);
    dp[0] = 0;
    dp[1] = 1;
    
    for (int i = 2; i <= n; i++) {
        dp[i] = dp[i-1] + dp[i-2];
    }
    
    return dp[n];
}
```

**Step 4:** Optimize space complexity if possible:
```cpp
// Space-optimized DP for Fibonacci - O(n) time, O(1) space
int fib(int n) {
    if (n <= 1) return n;
    
    int prev2 = 0; // f(0)
    int prev1 = 1; // f(1)
    int curr;
    
    for (int i = 2; i <= n; i++) {
        curr = prev1 + prev2;
        prev2 = prev1;
        prev1 = curr;
    }
    
    return prev1;
}
```

### Common DP Patterns

#### 1D DP - Longest Increasing Subsequence
```cpp
// Time Complexity: O(n²), Space Complexity: O(n)
int lengthOfLIS(vector<int>& nums) {
    int n = nums.size();
    if (n == 0) return 0;
    
    // dp[i] = length of LIS ending at index i
    vector<int> dp(n, 1); // Each element is a subsequence of length 1
    
    int maxLength = 1;
    
    for (int i = 1; i < n; i++) {
        for (int j = 0; j < i; j++) {
            if (nums[i] > nums[j]) {
                // Can extend subsequence ending at j
                dp[i] = max(dp[i], dp[j] + 1);
            }
        }
        maxLength = max(maxLength, dp[i]);
    }
    
    return maxLength;
}

// Optimized solution with binary search - O(n log n) time, O(n) space
int lengthOfLIS(vector<int>& nums) {
    vector<int> tails; // tails[i] = smallest value that ends an increasing subsequence of length i+1
    
    for (int num : nums) {
        // Binary search to find position to insert/replace
        auto it = lower_bound(tails.begin(), tails.end(), num);
        
        if (it == tails.end()) {
            // Add to the end for a longer subsequence
            tails.push_back(num);
        } else {
            // Replace existing value for a potentially better subsequence
            *it = num;
        }
    }
    
    return tails.size();
}
```

#### 2D DP - Longest Common Subsequence
```cpp
// Time Complexity: O(m*n), Space Complexity: O(m*n)
int longestCommonSubsequence(string text1, string text2) {
    int m = text1.length();
    int n = text2.length();
    
    // dp[i][j] = length of LCS for text1[0..i-1] and text2[0..j-1]
    vector<vector<int>> dp(m+1, vector<int>(n+1, 0));
    
    for (int i = 1; i <= m; i++) {
        for (int j = 1; j <= n; j++) {
            if (text1[i-1] == text2[j-1]) {
                // Characters match, extend LCS
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                // Characters don't match, take max of excluding one character
                dp[i][j] = max(dp[i-1][j], dp[i][j-1]);
            }
        }
    }
    
    return dp[m][n];
}
```

#### Knapsack Pattern
```cpp
// 0/1 Knapsack Problem - O(n*W) time, O(n*W) space
int knapsack(vector<int>& weights, vector<int>& values, int n, int capacity) {
    // dp[i][w] = max value with first i items and capacity w
    vector<vector<int>> dp(n+1, vector<int>(capacity+1, 0));
    
    for (int i = 1; i <= n; i++) {
        for (int w = 1; w <= capacity; w++) {
            // Can't include current item
            if (weights[i-1] > w) {
                dp[i][w] = dp[i-1][w];
            } else {
                // Max of including or excluding current item
                dp[i][w] = max(
                    dp[i-1][w],                              // Exclude
                    dp[i-1][w - weights[i-1]] + values[i-1]  // Include
                );
            }
        }
    }
    
    return dp[n][capacity];
}

// Space-optimized 0/1 Knapsack - O(n*W) time, O(W) space
int knapsack(vector<int>& weights, vector<int>& values, int n, int capacity) {
    vector<int> dp(capacity+1, 0);
    
    for (int i = 0; i < n; i++) {
        // Process from right to left to avoid overwriting needed values
        for (int w = capacity; w >= weights[i]; w--) {
            dp[w] = max(dp[w], dp[w - weights[i]] + values[i]);
        }
    }
    
    return dp[capacity];
}
```

#### Word Break Problem (DP with String)
```cpp
// Time Complexity: O(n²*m) where n is string length, m is dictionary size
// Space Complexity: O(n)
bool wordBreak(string s, vector<string>& wordDict) {
    int n = s.length();
    unordered_set<string> dict(wordDict.begin(), wordDict.end());
    
    // dp[i] = can segment s[0...i-1]
    vector<bool> dp(n+1, false);
    dp[0] = true; // Empty string can be segmented
    
    for (int i = 1; i <= n; i++) {
        for (int j = 0; j < i; j++) {
            if (dp[j] && dict.find(s.substr(j, i-j)) != dict.end()) {
                // If s[0...j-1] can be segmented and s[j...i-1] is in dictionary
                dp[i] = true;
                break;
            }
        }
    }
    
    return dp[n];
}
```

---

## Graph Algorithms & Techniques

### Graph Representation
```cpp
// Adjacency List
vector<vector<int>> graph(n); // n nodes
// Add directed edge from u to v
graph[u].push_back(v);
// Add undirected edge between u and v
graph[u].push_back(v);
graph[v].push_back(u);

// Adjacency Matrix (for dense graphs)
vector<vector<bool>> adjMatrix(n, vector<bool>(n, false));
// Add directed edge from u to v
adjMatrix[u][v] = true;
// Add undirected edge between u and v
adjMatrix[u][v] = adjMatrix[v][u] = true;
```

### BFS (Breadth-First Search)
```cpp
// Time Complexity: O(V + E), Space Complexity: O(V)
void bfs(vector<vector<int>>& graph, int start) {
    int n = graph.size();
    vector<bool> visited(n, false);
    queue<int> q;
    
    visited[start] = true;
    q.push(start);
    
    while (!q.empty()) {
        int node = q.front();
        q.pop();
        cout << node << " "; // Process node
        
        for (int neighbor : graph[node]) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                q.push(neighbor);
            }
        }
    }
}

// BFS for shortest path (unweighted)
vector<int> shortestPath(vector<vector<int>>& graph, int start, int end) {
    int n = graph.size();
    vector<bool> visited(n, false);
    vector<int> parent(n, -1); // Store path
    queue<int> q;
    
    visited[start] = true;
    q.push(start);
    
    while (!q.empty()) {
        int node = q.front();
        q.pop();
        
        if (node == end) break; // Found destination
        
        for (int neighbor : graph[node]) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                parent[neighbor] = node; // Record path
                q.push(neighbor);
            }
        }
    }
    
    // Reconstruct path
    vector<int> path;
    if (parent[end] == -1) return path; // No path exists
    
    for (int curr = end; curr != -1; curr = parent[curr]) {
        path.push_back(curr);
    }
    reverse(path.begin(), path.end());
    
    return path;
}
```

### DFS (Depth-First Search)
```cpp
// Time Complexity: O(V + E), Space Complexity: O(V)
void dfs(vector<vector<int>>& graph, int node, vector<bool>& visited) {
    visited[node] = true;
    cout << node << " "; // Process node
    
    for (int neighbor : graph[node]) {
        if (!visited[neighbor]) {
            dfs(graph, neighbor, visited);
        }
    }
}

// Iterative DFS
void dfsIterative(vector<vector<int>>& graph, int start) {
    int n = graph.size();
    vector<bool> visited(n, false);
    stack<int> stack;
    
    stack.push(start);
    
    while (!stack.empty()) {
        int node = stack.top();
        stack.pop();
        
        if (visited[node]) continue;
        
        visited[node] = true;
        cout << node << " "; // Process node
        
        // Push neighbors in reverse order to match recursive DFS
        for (int i = graph[node].size() - 1; i >= 0; i--) {
            int neighbor = graph[node][i];
            if (!visited[neighbor]) {
                stack.push(neighbor);
            }
        }
    }
}
```

### Connected Components
```cpp
// Find number of connected components - O(V + E) time, O(V) space
int countComponents(int n, vector<vector<int>>& graph) {
    vector<bool> visited(n, false);
    int count = 0;
    
    for (int i = 0; i < n; i++) {
        if (!visited[i]) {
            dfs(graph, i, visited);
            count++;
        }
    }
    
    return count;
}
```

### Cycle Detection
```cpp
// Detect cycle in undirected graph - O(V + E) time, O(V) space
bool hasCycle(vector<vector<int>>& graph, int node, int parent, vector<bool>& visited) {
    visited[node] = true;
    
    for (int neighbor : graph[node]) {
        if (!visited[neighbor]) {
            if (hasCycle(graph, neighbor, node, visited)) {
                return true;
            }
        } else if (neighbor != parent) {
            // Found a back edge to an already visited node
            return true;
        }
    }
    
    return false;
}

bool detectCycle(vector<vector<int>>& graph) {
    int n = graph.size();
    vector<bool> visited(n, false);
    
    for (int i = 0; i < n; i++) {
        if (!visited[i]) {
            if (hasCycle(graph, i, -1, visited)) {
                return true;
            }
        }
    }
    
    return false;
}

// Detect cycle in directed graph - O(V + E) time, O(V) space
bool hasCycleDFS(vector<vector<int>>& graph, int node, vector<bool>& visited, vector<bool>& recStack) {
    visited[node] = true;
    recStack[node] = true; // Node is in current recursion stack
    
    for (int neighbor : graph[node]) {
        if (!visited[neighbor]) {
            if (hasCycleDFS(graph, neighbor, visited, recStack)) {
                return true;
            }
        } else if (recStack[neighbor]) {
            // Found a back edge to a node in recursion stack
            return true;
        }
    }
    
    recStack[node] = false; // Remove from recursion stack
    return false;
}

bool detectCycleDirected(vector<vector<int>>& graph) {
    int n = graph.size();
    vector<bool> visited(n, false);
    vector<bool> recStack(n, false);
    
    for (int i = 0; i < n; i++) {
        if (!visited[i]) {
            if (hasCycleDFS(graph, i, visited, recStack)) {
                return true;
            }
        }
    }
    
    return false;
}
```

### Topological Sort
```cpp
// Topological Sort (DAG) - O(V + E) time, O(V) space
void topoSortDFS(vector<vector<int>>& graph, int node, vector<bool>& visited, stack<int>& stack) {
    visited[node] = true;
    
    for (int neighbor : graph[node]) {
        if (!visited[neighbor]) {
            topoSortDFS(graph, neighbor, visited, stack);
        }
    }
    
    // Push after all descendants are processed
    stack.push(node);
}

vector<int> topologicalSort(vector<vector<int>>& graph) {
    int n = graph.size();
    vector<bool> visited(n, false);
    stack<int> stack;
    
    for (int i = 0; i < n; i++) {
        if (!visited[i]) {
            topoSortDFS(graph, i, visited, stack);
        }
    }
    
    vector<int> result;
    while (!stack.empty()) {
        result.push_back(stack.top());
        stack.pop();
    }
    
    return result;
}

// Kahn's Algorithm (BFS approach for topological sort)
vector<int> topologicalSortBFS(vector<vector<int>>& graph) {
    int n = graph.size();
    vector<int> inDegree(n, 0);
    
    // Calculate in-degree for each node
    for (int i = 0; i < n; i++) {
        for (int neighbor : graph[i]) {
            inDegree[neighbor]++;
        }
    }
    
    queue<int> q;
    // Add nodes with 0 in-degree to queue
    for (int i = 0; i < n; i++) {
        if (inDegree[i] == 0) {
            q.push(i);
        }
    }
    
    vector<int> result;
    while (!q.empty()) {
        int node = q.front();
        q.pop();
        result.push_back(node);
        
        for (int neighbor : graph[node]) {
            if (--inDegree[neighbor] == 0) {
                q.push(neighbor);
            }
        }
    }
    
    // If topological sort is not possible (graph has cycle)
    if (result.size() != n) {
        return {};
    }
    
    return result;
}
```

### Dijkstra's Algorithm (Shortest Path)
```cpp
// Time Complexity: O((V + E) log V), Space Complexity: O(V)
vector<int> dijkstra(vector<vector<pair<int, int>>>& graph, int start) {
    int n = graph.size();
    vector<int> dist(n, INT_MAX);
    dist[start] = 0;
    
    // Min-heap: (distance, node)
    priority_queue<pair<int, int>, vector<pair<int, int>>, greater<pair<int, int>>> pq;
    pq.push({0, start});
    
    while (!pq.empty()) {
        int d = pq.top().first;
        int node = pq.top().second;
        pq.pop();
        
        // Skip if we've found a better path
        if (d > dist[node]) continue;
        
        for (auto& [neighbor, weight] : graph[node]) {
            if (dist[node] + weight < dist[neighbor]) {
                dist[neighbor] = dist[node] + weight;
                pq.push({dist[neighbor], neighbor});
            }
        }
    }
    
    return dist;
}
```

### Number of Islands (Grid DFS/BFS)
```cpp
// Time Complexity: O(m*n), Space Complexity: O(m*n)
void dfs(vector<vector<char>>& grid, int i, int j) {
    int m = grid.size();
    int n = grid[0].size();
    
    // Check boundaries and if it's a land cell
    if (i < 0 || i >= m || j < 0 || j >= n || grid[i][j] != '1') {
        return;
    }
    
    // Mark as visited
    grid[i][j] = '2';
    
    // Visit all adjacent land cells
    dfs(grid, i+1, j);
    dfs(grid, i-1, j);
    dfs(grid, i, j+1);
    dfs(grid, i, j-1);
}

int numIslands(vector<vector<char>>& grid) {
    if (grid.empty()) return 0;
    
    int m = grid.size();
    int n = grid[0].size();
    int count = 0;
    
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            if (grid[i][j] == '1') {
                count++;
                dfs(grid, i, j);
            }
        }
    }
    
    return count;
}
```

---

## Tree Traversal & Manipulation

### Tree Structure
```cpp
struct TreeNode {
    int val;
    TreeNode* left;
    TreeNode* right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};
```

### Tree Traversals
```cpp
// In-order Traversal (Left -> Root -> Right) - O(n) time, O(h) space
void inorderTraversal(TreeNode* root, vector<int>& result) {
    if (!root) return;
    
    inorderTraversal(root->left, result);
    result.push_back(root->val);
    inorderTraversal(root->right, result);
}

// Pre-order Traversal (Root -> Left -> Right) - O(n) time, O(h) space
void preorderTraversal(TreeNode* root, vector<int>& result) {
    if (!root) return;
    
    result.push_back(root->val);
    preorderTraversal(root->left, result);
    preorderTraversal(root->right, result);
}

// Post-order Traversal (Left -> Right -> Root) - O(n) time, O(h) space
void postorderTraversal(TreeNode* root, vector<int>& result) {
    if (!root) return;
    
    postorderTraversal(root->left, result);
    postorderTraversal(root->right, result);
    result.push_back(root->val);
}

// Level-order Traversal (BFS) - O(n) time, O(w) space (w = width of tree)
vector<vector<int>> levelOrder(TreeNode* root) {
    vector<vector<int>> result;
    if (!root) return result;
    
    queue<TreeNode*> q;
    q.push(root);
    
    while (!q.empty()) {
        int levelSize = q.size();
        vector<int> currentLevel;
        
        for (int i = 0; i < levelSize; i++) {
            TreeNode* node = q.front();
            q.pop();
            
            currentLevel.push_back(node->val);
            
            if (node->left) q.push(node->left);
            if (node->right) q.push(node->right);
        }
        
        result.push_back(currentLevel);
    }
    
    return result;
}
```

### Iterative Tree Traversals
```cpp
// Iterative In-order Traversal - O(n) time, O(h) space
vector<int> inorderTraversalIterative(TreeNode* root) {
    vector<int> result;
    stack<TreeNode*> stack;
    TreeNode* curr = root;
    
    while (curr || !stack.empty()) {
        // Go all the way to the left
        while (curr) {
            stack.push(curr);
            curr = curr->left;
        }
        
        // Process current node
        curr = stack.top();
        stack.pop();
        result.push_back(curr->val);
        
        // Move to right subtree
        curr = curr->right;
    }
    
    return result;
}

// Iterative Pre-order Traversal - O(n) time, O(h) space
vector<int> preorderTraversalIterative(TreeNode* root) {
    vector<int> result;
    if (!root) return result;
    
    stack<TreeNode*> stack;
    stack.push(root);
    
    while (!stack.empty()) {
        TreeNode* node = stack.top();
        stack.pop();
        
        result.push_back(node->val);
        
        // Push right first so left is processed first (LIFO)
        if (node->right) stack.push(node->right);
        if (node->left) stack.push(node->left);
    }
    
    return result;
}

// Iterative Post-order Traversal - O(n) time, O(h) space
vector<int> postorderTraversalIterative(TreeNode* root) {
    vector<int> result;
    if (!root) return result;
    
    stack<TreeNode*> stack;
    stack.push(root);
    
    // Use another stack to reverse the order
    stack<int> values;
    
    while (!stack.empty()) {
        TreeNode* node = stack.top();
        stack.pop();
        
        values.push(node->val);
        
        // Push left first so right is processed first in reverse
        if (node->left) stack.push(node->left);
        if (node->right) stack.push(node->right);
    }
    
    // Reverse the order to get post-order
    while (!values.empty()) {
        result.push_back(values.top());
        values.pop();
    }
    
    return result;
}
```

### Tree Operations
```cpp
// Maximum Depth of Binary Tree - O(n) time, O(h) space
int maxDepth(TreeNode* root) {
    if (!root) return 0;
    
    int leftDepth = maxDepth(root->left);
    int rightDepth = maxDepth(root->right);
    
    return max(leftDepth, rightDepth) + 1;
}

// Check if tree is balanced - O(n) time, O(h) space
pair<bool, int> isBalancedHelper(TreeNode* root) {
    if (!root) return {true, 0};
    
    auto left = isBalancedHelper(root->left);
    auto right = isBalancedHelper(root->right);
    
    bool isBalanced = left.first && right.first && 
                     abs(left.second - right.second) <= 1;
    
    return {isBalanced, max(left.second, right.second) + 1};
}

bool isBalanced(TreeNode* root) {
    return isBalancedHelper(root).first;
}

// Validate Binary Search Tree - O(n) time, O(h) space
bool isValidBST(TreeNode* root, TreeNode* minNode = nullptr, TreeNode* maxNode = nullptr) {
    if (!root) return true;
    
    // Check if current node's value is within valid range
    if ((minNode && root->val <= minNode->val) || 
        (maxNode && root->val >= maxNode->val)) {
        return false;
    }
    
    // Recursively check left and right subtrees
    return isValidBST(root->left, minNode, root) && 
           isValidBST(root->right, root, maxNode);
}

// Lowest Common Ancestor - O(n) time, O(h) space
TreeNode* lowestCommonAncestor(TreeNode* root, TreeNode* p, TreeNode* q) {
    if (!root || root == p || root == q) return root;
    
    TreeNode* left = lowestCommonAncestor(root->left, p, q);
    TreeNode* right = lowestCommonAncestor(root->right, p, q);
    
    if (left && right) return root; // p and q are in different subtrees
    return left ? left : right;     // Either one of p or q is in a subtree, or none
}
```

### Serialize and Deserialize Binary Tree
```cpp
// Time Complexity: O(n), Space Complexity: O(n)
class Codec {
public:
    // Encodes a tree to a single string.
    string serialize(TreeNode* root) {
        if (!root) return "null";
        
        // Preorder traversal: root,left,right
        return to_string(root->val) + "," + 
               serialize(root->left) + "," + 
               serialize(root->right);
    }

    // Decodes your encoded data to tree.
    TreeNode* deserialize(string data) {
        stringstream ss(data);
        return deserializeHelper(ss);
    }
    
private:
    TreeNode* deserializeHelper(stringstream& ss) {
        string val;
        getline(ss, val, ',');
        
        if (val == "null") return nullptr;
        
        TreeNode* root = new TreeNode(stoi(val));
        root->left = deserializeHelper(ss);
        root->right = deserializeHelper(ss);
        
        return root;
    }
};
```

---

## Greedy Algorithms

### Interval Problems
```cpp
// Merge Intervals - O(n log n) time, O(n) space
vector<vector<int>> merge(vector<vector<int>>& intervals) {
    if (intervals.empty()) return {};
    
    // Sort intervals by start time
    sort(intervals.begin(), intervals.end(), 
         [](const vector<int>& a, const vector<int>& b) {
             return a[0] < b[0];
         });
    
    vector<vector<int>> result;
    result.push_back(intervals[0]);
    
    for (int i = 1; i < intervals.size(); i++) {
        // If current interval overlaps with last result interval
        if (intervals[i][0] <= result.back()[1]) {
            // Merge by updating end time to maximum of both
            result.back()[1] = max(result.back()[1], intervals[i][1]);
        } else {
            // No overlap, add current interval to result
            result.push_back(intervals[i]);
        }
    }
    
    return result;
}

// Meeting Rooms II - O(n log n) time, O(n) space
int minMeetingRooms(vector<vector<int>>& intervals) {
    if (intervals.empty()) return 0;
    
    // Separate start and end times
    vector<int> startTimes;
    vector<int> endTimes;
    
    for (auto& interval : intervals) {
        startTimes.push_back(interval[0]);
        endTimes.push_back(interval[1]);
    }
    
    // Sort start and end times
    sort(startTimes.begin(), startTimes.end());
    sort(endTimes.begin(), endTimes.end());
    
    int rooms = 0;
    int endIdx = 0;
    
    // Count required rooms
    for (int startIdx = 0; startIdx < intervals.size(); startIdx++) {
        // If this meeting starts before the earliest ending meeting
        if (startTimes[startIdx] < endTimes[endIdx]) {
            rooms++; // Need a new room
        } else {
            endIdx++; // Can reuse a room
        }
    }
    
    return rooms;
}
```

### Jump Game
```cpp
// Jump Game - O(n) time, O(1) space
bool canJump(vector<int>& nums) {
    int maxReach = 0;
    
    for (int i = 0; i < nums.size(); i++) {
        // Can't reach current position
        if (i > maxReach) return false;
        
        // Update maximum reachable position
        maxReach = max(maxReach, i + nums[i]);
        
        // If can reach the end, return true
        if (maxReach >= nums.size() - 1) return true;
    }
    
    return true;
}

// Jump Game II - O(n) time, O(1) space
int jump(vector<int>& nums) {
    int jumps = 0;
    int currEnd = 0;  // Maximum reach of current jump
    int currFarthest = 0;  // Farthest position that can be reached
    
    // Don't need to check the last element
    for (int i = 0; i < nums.size() - 1; i++) {
        currFarthest = max(currFarthest, i + nums[i]);
        
        // Reached the boundary of current jump
        if (i == currEnd) {
            jumps++;
            currEnd = currFarthest;
            
            // If already can reach the end
            if (currEnd >= nums.size() - 1) break;
        }
    }
    
    return jumps;
}
```

### Task Scheduler
```cpp
// Task Scheduler - O(n) time, O(1) space (since at most 26 characters)
int leastInterval(vector<char>& tasks, int n) {
    vector<int> freq(26, 0);
    for (char task : tasks) {
        freq[task - 'A']++;
    }
    
    // Sort frequencies in descending order
    sort(freq.begin(), freq.end(), greater<int>());
    
    // Maximum frequency
    int maxFreq = freq[0];
    
    // Count number of tasks with maximum frequency
    int maxCount = 0;
    for (int f : freq) {
        if (f == maxFreq) maxCount++;
        else break;
    }
    
    // Formula: (maxFreq - 1) * (n + 1) + maxCount
    // Explanation:
    // - We need (maxFreq - 1) groups of size (n + 1)
    // - Plus maxCount tasks at the end
    int result = (maxFreq - 1) * (n + 1) + maxCount;
    
    // Return maximum of calculated intervals and actual number of tasks
    return max(result, static_cast<int>(tasks.size()));
}
```

---

## Heap/Priority Queue Techniques

### Heap Operations
```cpp
// Min-heap (priority_queue with greater comparator)
priority_queue<int, vector<int>, greater<int>> minHeap;
minHeap.push(5);
minHeap.push(2);
minHeap.push(8);
int smallest = minHeap.top(); // 2
minHeap.pop();

// Max-heap (default priority_queue)
priority_queue<int> maxHeap;
maxHeap.push(5);
maxHeap.push(2);
maxHeap.push(8);
int largest = maxHeap.top(); // 8
maxHeap.pop();

// Custom comparator for priority_queue
struct Compare {
    bool operator()(const ListNode* a, const ListNode* b) {
        return a->val > b->val; // For min-heap based on ListNode->val
    }
};
priority_queue<ListNode*, vector<ListNode*>, Compare> pq;
```

### Top K Elements
```cpp
// Kth Largest Element - O(n + k log n) time, O(n) space
int findKthLargest(vector<int>& nums, int k) {
    // Using min-heap to maintain k largest elements
    priority_queue<int, vector<int>, greater<int>> minHeap;
    
    for (int num : nums) {
        minHeap.push(num);
        if (minHeap.size() > k) {
            minHeap.pop(); // Remove smallest element
        }
    }
    
    return minHeap.top(); // Kth largest
}

// Top K Frequent Elements - O(n log k) time, O(n) space
vector<int> topKFrequent(vector<int>& nums, int k) {
    // Count frequencies
    unordered_map<int, int> freq;
    for (int num : nums) {
        freq[num]++;
    }
    
    // Min-heap based on frequency
    // Each element is a pair: (frequency, number)
    struct Compare {
        bool operator()(const pair<int, int>& a, const pair<int, int>& b) {
            return a.first > b.first; // Min-heap by frequency
        }
    };
    priority_queue<pair<int, int>, vector<pair<int, int>>, Compare> minHeap;
    
    // Keep k most frequent elements
    for (auto& [num, count] : freq) {
        minHeap.push({count, num});
        if (minHeap.size() > k) {
            minHeap.pop();
        }
    }
    
    // Extract result
    vector<int> result;
    while (!minHeap.empty()) {
        result.push_back(minHeap.top().second);
        minHeap.pop();
    }
    
    return result;
}
```

### Merge K Sorted Lists
```cpp
// Time Complexity: O(n log k) where n is total nodes, k is number of lists
// Space Complexity: O(k)
ListNode* mergeKLists(vector<ListNode*>& lists) {
    // Custom comparator for min-heap
    struct Compare {
        bool operator()(const ListNode* a, const ListNode* b) {
            return a->val > b->val; // Min-heap
        }
    };
    
    // Min-heap to maintain smallest element from each list
    priority_queue<ListNode*, vector<ListNode*>, Compare> minHeap;
    
    // Add first node from each list to heap
    for (ListNode* list : lists) {
        if (list) minHeap.push(list);
    }
    
    // Dummy head for result list
    ListNode dummy(0);
    ListNode* tail = &dummy;
    
    // Process nodes from heap
    while (!minHeap.empty()) {
        // Get smallest node
        ListNode* curr = minHeap.top();
        minHeap.pop();
        
        // Add to result list
        tail->next = curr;
        tail = tail->next;
        
        // Add next node from same list to heap
        if (curr->next) {
            minHeap.push(curr->next);
        }
    }
    
    return dummy.next;
}
```

### Find Median from Data Stream
```cpp
// Time Complexity: O(log n) for add, O(1) for findMedian
// Space Complexity: O(n)
class MedianFinder {
private:
    // Max-heap for the smaller half of numbers
    priority_queue<int> maxHeap;
    // Min-heap for the larger half of numbers
    priority_queue<int, vector<int>, greater<int>> minHeap;
    
public:
    MedianFinder() {}
    
    void addNum(int num) {
        // Add to max-heap first
        maxHeap.push(num);
        
        // Balance heaps: ensure max-heap elements <= min-heap elements
        minHeap.push(maxHeap.top());
        maxHeap.pop();
        
        // Ensure size difference is not more than 1
        if (maxHeap.size() < minHeap.size()) {
            maxHeap.push(minHeap.top());
            minHeap.pop();
        }
    }
    
    double findMedian() {
        if (maxHeap.size() > minHeap.size()) {
            return maxHeap.top();
        } else {
            return (maxHeap.top() + minHeap.top()) / 2.0;
        }
    }
};
```

---

## Top Amazon SDE 1 Questions by Category

### Arrays
1. **Two Sum** - Use hashmap for O(n) solution
2. **Best Time to Buy and Sell Stock** - One pass, track minimum price
3. **Container With Most Water** - Two pointers from both ends
4. **Product of Array Except Self** - Left and right product arrays
5. **3Sum** - Sort and use two pointers

### Strings
1. **Valid Parentheses** - Use stack to match opening/closing
2. **Longest Palindromic Substring** - Expand around centers
3. **String to Integer (atoi)** - Handle edge cases carefully
4. **Valid Anagram** - Use frequency counter
5. **Group Anagrams** - Sort characters as key in hashmap

### Linked Lists
1. **Reverse Linked List** - Iterative three-pointer approach
2. **Merge Two Sorted Lists** - Use dummy head
3. **Linked List Cycle** - Fast and slow pointers
4. **Add Two Numbers** - Simulate digit-by-digit addition
5. **Remove Nth Node From End** - Two pointers with gap of n

### Trees
1. **Maximum Depth of Binary Tree** - Recursive DFS
2. **Validate Binary Search Tree** - Pass min/max constraints
3. **Symmetric Tree** - Recursive or iterative with queue
4. **Binary Tree Level Order Traversal** - BFS with queue
5. **Lowest Common Ancestor of BST** - Use BST property

### Graphs
1. **Number of Islands** - DFS/BFS to count connected components
2. **Course Schedule** - Topological sort / cycle detection
3. **Word Ladder** - BFS for shortest path
4. **Clone Graph** - DFS/BFS with hashmap for mapping
5. **Rotting Oranges** - BFS to simulate time

### Dynamic Programming
1. **Maximum Subarray** - Kadane's algorithm
2. **Climbing Stairs** - Simple 1D DP
3. **Coin Change** - 1D DP bottom-up approach
4. **Longest Increasing Subsequence** - 1D DP or binary search
5. **Word Break** - 1D DP with string matching

### Greedy
1. **Jump Game** - Track maximum reachable index
2. **Merge Intervals** - Sort and merge overlapping intervals
3. **Task Scheduler** - Focus on most frequent task
4. **Meeting Rooms II** - Separate and sort start/end times
5. **Gas Station** - One pass with cumulative sum

### Heap
1. **Kth Largest Element** - Min-heap of size k
2. **Merge K Sorted Lists** - Min-heap for k lists' heads
3. **Top K Frequent Elements** - Frequency counter and heap
4. **Find Median from Data Stream** - Two heaps (max and min)
5. **K Closest Points to Origin** - Min-heap based on distance

---

## C++ Best Practices for Interviews

### Efficient Vector Operations
```cpp
// Reserve capacity for better performance
vector<int> nums;
nums.reserve(1000); // Allocate space for 1000 elements

// Prefer emplace_back over push_back for custom objects
vector<pair<int, int>> pairs;
pairs.emplace_back(1, 2); // Constructs pair in-place
```

### Smart Use of STL
```cpp
// Use appropriate containers
unordered_map<int, int> map; // For O(1) lookup when order doesn't matter
map<int, int> orderedMap;    // For O(log n) lookup when order matters

// Use algorithms for cleaner code
vector<int> nums = {3, 1, 4, 1, 5, 9};
sort(nums.begin(), nums.end());
auto it = lower_bound(nums.begin(), nums.end(), 4); // Binary search

// Use accumulate for sum
int sum = accumulate(nums.begin(), nums.end(), 0);

// Use count_if for counting elements matching a predicate
int evenCount = count_if(nums.begin(), nums.end(), [](int x) { return x % 2 == 0; });
```

### Memory Management
```cpp
// Always free memory in interviews (even though smart pointers are better in production)
TreeNode* root = new TreeNode(10);
root->left = new TreeNode(5);
root->right = new TreeNode(15);

// Free memory when done
void freeTree(TreeNode* root) {
    if (!root) return;
    freeTree(root->left);
    freeTree(root->right);
    delete root;
}
```

### Avoid Common Pitfalls
```cpp
// Avoid overflow in integer arithmetic
int mid = left + (right - left) / 2; // Instead of (left + right) / 2

// Check boundaries
if (i >= 0 && i < n && j >= 0 && j < m) {
    // Safe to access grid[i][j]
}

// Initialize variables
int result = 0; // Or appropriate initial value
vector<vector<int>> grid(m, vector<int>(n, 0)); // 2D vector with zeros
```

### Custom Comparators
```cpp
// Using struct for better readability
struct Compare {
    bool operator()(const ListNode* a, const ListNode* b) {
        return a->val > b->val; // For min-heap
    }
};
priority_queue<ListNode*, vector<ListNode*>, Compare> pq;

// Using lambda for inline comparisons
sort(intervals.begin(), intervals.end(), 
    [](const vector<int>& a, const vector<int>& b) {
        return a[0] < b[0]; // Sort by start time
    });
```

---

## Last-Minute Strategy & Tips

### Time Management During Interview
1. **First 2-3 minutes**: Understand the problem completely
   - Ask clarifying questions
   - Confirm input/output formats and constraints
   - Discuss edge cases

2. **Next 5 minutes**: Develop approach and discuss with interviewer
   - Think out loud
   - Start with brute force, then optimize
   - Discuss time and space complexity

3. **Next 15-20 minutes**: Write clean, efficient code
   - Use meaningful variable names
   - Add comments for clarity
   - Handle edge cases properly

4. **Last 5 minutes**: Test your code
   - Use a specific example and trace through
   - Check edge cases
   - Suggest optimizations if time permits

### Problem-Solving Framework
1. **Understand** - Clarify the problem and constraints
2. **Match** - Connect to known patterns or problems
3. **Plan** - Outline your approach before coding
4. **Implement** - Write clean, efficient code
5. **Review** - Test your solution with examples and edge cases

### 5 Most Common Patterns in Amazon Interviews
1. **BFS/DFS** - For tree and graph traversal
2. **Two Pointers** - For array and string problems
3. **Sliding Window** - For substring and subarray problems
4. **Dynamic Programming** - For optimization problems
5. **Heap** - For top K or streaming data problems

### Critical Last-Minute Reminders
1. **Communicate clearly** throughout the interview
2. **Think aloud** to demonstrate problem-solving
3. **Start with a working solution** before optimizing
4. **Test your code** with examples and edge cases
5. **Always analyze time and space complexity**
6. **Connect solutions to Amazon's Leadership Principles** when appropriate

### Mental Preparation
1. **Stay calm** - Nervousness can block clear thinking
2. **Focus on one step at a time** - Don't get overwhelmed
3. **Use interviewer hints** - They want you to succeed
4. **Be confident** in your abilities
5. **Remember** - It's about problem-solving process, not just the final solution

Good luck with your Amazon SDE 1 interview today! You've prepared well, and these notes should help you tackle any coding challenges they present. Remember to communicate clearly, demonstrate your problem-solving approach, and connect your solutions to Amazon's culture when possible.
