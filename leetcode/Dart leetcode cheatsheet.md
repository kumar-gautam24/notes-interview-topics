# 🎯 Dart Ultimate Cheat Sheet for LeetCode
## Competitive Programming & Technical Interviews (Flutter Developer Edition)

---

## ⚡ Basic Setup

```dart
import 'dart:io';
import 'dart:math';
import 'dart:collection';
import 'dart:convert';

void main() {
  // Fast I/O is automatic in Dart
  
  // Constants
  const int MOD = 1000000007;
  const int INF = 1 << 30;
  const double EPS = 1e-9;
  
  // Your code here
}
```

---

## 📊 LIST (Dynamic Array)

### Declaration & Initialization
```dart
List<int> list = [];                              // Empty list
List<int> list = [1, 2, 3, 4, 5];                // With values
List<int> list = List.filled(n, 0);              // Fixed length, all 0
List<int> list = List.filled(n, 0, growable: true);  // Growable
List<int> list = List.generate(n, (i) => i);     // Generate with function

// 2D list
List<List<int>> mat = List.generate(n, (_) => List.filled(m, 0));

// From iterable
List<int> list = [1, 2, 3].toList();
List<int> list = range.toList();
```

### Core Operations
```dart
// Adding elements
list.add(x);                                     // O(1) amortized - add to end
list.addAll([1, 2, 3]);                         // Add multiple elements
list.insert(i, x);                              // O(n) - insert at index
list.insertAll(i, [1, 2, 3]);                   // Insert multiple

// Removing elements
list.remove(x);                                  // O(n) - remove first occurrence
list.removeAt(i);                               // O(n) - remove at index
list.removeLast();                              // O(1) - remove last
list.removeRange(start, end);                   // Remove range [start, end)
list.removeWhere((x) => x > 0);                 // Remove matching
list.clear();                                    // Remove all

// Access & Update
list[i];                                         // O(1) - get element
list[i] = x;                                     // O(1) - set element
list.first;                                      // First element
list.last;                                       // Last element

// Size & Check
list.length;                                     // Size (not size()!)
list.isEmpty;                                    // Check if empty
list.isNotEmpty;                                 // Check if not empty

// Search
list.contains(x);                                // O(n) - check contains
list.indexOf(x);                                 // O(n) - first occurrence (-1 if not found)
list.lastIndexOf(x);                             // O(n) - last occurrence
```

### Iteration
```dart
// For-in loop
for(var x in list) {
  print(x);
}

// Index-based
for(int i = 0; i < list.length; i++) {
  print(list[i]);
}

// forEach
list.forEach((x) => print(x));
list.forEach(print);  // Shorter

// For with index
for(var i = 0; i < list.length; i++) {
  var x = list[i];
}

// Reversed iteration
for(var x in list.reversed) {
  print(x);
}
```

### Sorting & Searching
```dart
// Sorting
list.sort();                                     // Ascending (natural order)
list.sort((a, b) => b.compareTo(a));            // Descending

// Custom sort
list.sort((a, b) {
  if(a.first != b.first) return a.first.compareTo(b.first);
  return a.second.compareTo(b.second);
});

// Reverse
list.reversed.toList();                          // Returns new list
// OR modify in place:
list = list.reversed.toList();

// Binary search (custom implementation needed)
int binarySearch(List<int> list, int target) {
  int left = 0, right = list.length - 1;
  while(left <= right) {
    int mid = left + (right - left) ~/ 2;  // ~/ is integer division
    if(list[mid] == target) return mid;
    if(list[mid] < target) left = mid + 1;
    else right = mid - 1;
  }
  return -1;
}
```

### Functional Operations (Very Powerful!)
```dart
// Map - Transform each element
List<int> doubled = list.map((x) => x * 2).toList();

// Where - Filter elements
List<int> positive = list.where((x) => x > 0).toList();

// Any - Check if any element matches
bool hasPositive = list.any((x) => x > 0);

// Every - Check if all elements match
bool allPositive = list.every((x) => x > 0);

// Reduce - Combine all elements
int sum = list.reduce((a, b) => a + b);
int max = list.reduce((a, b) => a > b ? a : b);

// Fold - Like reduce but with initial value
int sum = list.fold(0, (sum, x) => sum + x);

// Take - First n elements
List<int> firstThree = list.take(3).toList();

// Skip - Skip first n elements
List<int> afterFirst = list.skip(1).toList();

// Expand - Flatten nested lists
List<int> flattened = [[1, 2], [3, 4]].expand((x) => x).toList();

// Join - Convert to string
String result = list.join(', ');  // "1, 2, 3"
```

### Sublist & Slicing
```dart
// Sublist
List<int> sub = list.sublist(start);            // From start to end
List<int> sub = list.sublist(start, end);       // [start, end)

// Get range
Iterable<int> range = list.getRange(start, end);  // [start, end)
```

---

## 📝 STRING

### Declaration & Operations
```dart
String s = 'hello';                              // Single quotes
String s = "hello";                              // Double quotes
String s = '''multi
line''';                                         // Multi-line

// String interpolation (very powerful!)
String name = 'Alice';
String msg = 'Hello $name';                      // Simple
String msg = 'Hello ${name.toUpperCase()}';      // Expression

// Length & Access
s.length;                                        // Length
s[i];                                            // Get char at index
s.isEmpty;                                       // Check empty
s.isNotEmpty;                                    // Check not empty

// Substring
s.substring(start);                              // From start to end
s.substring(start, end);                         // [start, end)

// Search
s.indexOf('sub');                                // First occurrence (-1 if not found)
s.lastIndexOf('sub');                            // Last occurrence
s.contains('sub');                               // Check contains
s.startsWith('pre');                             // Check prefix
s.endsWith('suf');                               // Check suffix

// Case conversion
s.toLowerCase();                                 // To lowercase
s.toUpperCase();                                 // To uppercase

// Trim
s.trim();                                        // Remove whitespace
s.trimLeft();                                    // Trim left only
s.trimRight();                                   // Trim right only

// Replace
s.replaceAll('old', 'new');                      // Replace all
s.replaceFirst('old', 'new');                    // Replace first
s.replaceRange(start, end, 'new');              // Replace range

// Split
List<String> parts = s.split(' ');               // Split by space
List<String> parts = s.split('');                // Split into chars

// Comparison
s1 == s2;                                        // Content equality
s1.compareTo(s2);                                // Lexicographic (returns <0, 0, or >0)
```

### Conversion
```dart
// String to number
int num = int.parse(s);
int? num = int.tryParse(s);                      // Returns null if invalid
double d = double.parse(s);
double? d = double.tryParse(s);

// Number to string
String s = 123.toString();
String s = 3.14.toString();
String s = '$num';                               // Using interpolation

// String to char list
List<String> chars = s.split('');

// Char code
int code = s.codeUnitAt(i);                      // Get char code at index
String char = String.fromCharCode(97);           // 'a'

// Character checks (need to check char code)
bool isDigit = s.codeUnitAt(i) >= '0'.codeUnitAt(0) 
            && s.codeUnitAt(i) <= '9'.codeUnitAt(0);
bool isLower = s.codeUnitAt(i) >= 'a'.codeUnitAt(0) 
            && s.codeUnitAt(i) <= 'z'.codeUnitAt(0);
bool isUpper = s.codeUnitAt(i) >= 'A'.codeUnitAt(0) 
            && s.codeUnitAt(i) <= 'Z'.codeUnitAt(0);
```

### StringBuffer (Mutable String)
```dart
// For efficient string concatenation
StringBuffer sb = StringBuffer();

sb.write('hello');                               // Append
sb.writeln('world');                             // Append with newline
sb.writeAll(['a', 'b', 'c']);                   // Append multiple
sb.writeAll(['a', 'b', 'c'], ', ');             // With separator

String result = sb.toString();                   // Convert to String

// Clear
sb.clear();
```

---

## 🗺️ MAP (Hash Map)

### Declaration
```dart
Map<int, int> map = {};                          // Empty map
Map<String, int> map = {'a': 1, 'b': 2};
Map<int, List<int>> map = {};

// Initialize with values
var map = <int, String>{
  1: 'one',
  2: 'two',
};
```

### Operations - O(1) Average
```dart
// Insert/Update
map[key] = value;                                // Insert or update

// Access
map[key];                                        // Returns null if not exists
map[key] ?? defaultValue;                        // Get with default

// Remove
map.remove(key);                                 // Remove key-value pair

// Check
map.containsKey(key);                            // Check if key exists
map.containsValue(value);                        // Check if value exists (O(n))

// Size
map.length;
map.isEmpty;
map.isNotEmpty;

// Clear
map.clear();
```

### Advanced Operations
```dart
// Put if absent
map.putIfAbsent(key, () => value);
map.putIfAbsent(key, () => []);                  // Useful for map of lists

// Update
map.update(key, (v) => v + 1);                   // Must exist
map.update(key, (v) => v + 1, ifAbsent: () => 1);  // With default

// Remove where
map.removeWhere((key, value) => value < 0);

// Add all
map.addAll({'c': 3, 'd': 4});
```

### Iteration
```dart
// Iterate through entries
map.forEach((key, value) {
  print('$key: $value');
});

// Iterate through keys
for(var key in map.keys) {
  var value = map[key];
}

// Iterate through values
for(var value in map.values) {
  print(value);
}

// Iterate with entries
for(var entry in map.entries) {
  var key = entry.key;
  var value = entry.value;
}
```

---

## 📦 SET (Hash Set)

### Declaration & Operations - O(1) Average
```dart
Set<int> set = {};                               // Empty set
Set<int> set = {1, 2, 3};                       // With values
Set<int> set = Set.from([1, 2, 3]);

// Insert
set.add(x);                                      // Add element
set.addAll([1, 2, 3]);                          // Add multiple

// Remove
set.remove(x);                                   // Remove element
set.removeAll([1, 2, 3]);                       // Remove multiple
set.clear();                                     // Remove all

// Check
set.contains(x);                                 // Check if contains
set.length;
set.isEmpty;
set.isNotEmpty;

// Set operations
set1.union(set2);                                // Union
set1.intersection(set2);                         // Intersection
set1.difference(set2);                           // Difference (in set1 but not set2)

// Subset check
set1.containsAll(set2);                          // Is set2 subset of set1?

// Iteration (unordered)
for(var x in set) {
  print(x);
}
```

---

## 📋 QUEUE

### Declaration & Operations - O(1)
```dart
import 'dart:collection';

Queue<int> queue = Queue();

// Add
queue.add(x);                                    // Add to back
queue.addFirst(x);                               // Add to front (deque operation)
queue.addLast(x);                                // Add to back (same as add)

// Remove
queue.removeFirst();                             // Remove from front
queue.removeLast();                              // Remove from back (deque operation)

// Access
queue.first;                                     // Access front
queue.last;                                      // Access back

// Size
queue.length;
queue.isEmpty;
queue.isNotEmpty;

// Clear
queue.clear();

// Iteration
for(var x in queue) {
  print(x);
}
```

---

## 🏔️ PRIORITY QUEUE (Custom Implementation)

Dart doesn't have a built-in PriorityQueue, so we implement it:

### Min Heap Implementation
```dart
class MinHeap<T extends Comparable> {
  List<T> heap = [];
  
  void add(T value) {
    heap.add(value);
    _siftUp(heap.length - 1);
  }
  
  T removeMin() {
    if(heap.isEmpty) throw Exception('Heap is empty');
    
    T min = heap[0];
    heap[0] = heap.last;
    heap.removeLast();
    
    if(heap.isNotEmpty) _siftDown(0);
    return min;
  }
  
  T get min => heap[0];
  bool get isEmpty => heap.isEmpty;
  bool get isNotEmpty => heap.isNotEmpty;
  int get length => heap.length;
  
  void _siftUp(int i) {
    while(i > 0) {
      int parent = (i - 1) ~/ 2;
      if(heap[i].compareTo(heap[parent]) >= 0) break;
      _swap(i, parent);
      i = parent;
    }
  }
  
  void _siftDown(int i) {
    while(true) {
      int smallest = i;
      int left = 2 * i + 1;
      int right = 2 * i + 2;
      
      if(left < heap.length && heap[left].compareTo(heap[smallest]) < 0) {
        smallest = left;
      }
      if(right < heap.length && heap[right].compareTo(heap[smallest]) < 0) {
        smallest = right;
      }
      
      if(smallest == i) break;
      
      _swap(i, smallest);
      i = smallest;
    }
  }
  
  void _swap(int i, int j) {
    T temp = heap[i];
    heap[i] = heap[j];
    heap[j] = temp;
  }
}

// Usage
void main() {
  var minHeap = MinHeap<int>();
  minHeap.add(5);
  minHeap.add(3);
  minHeap.add(7);
  print(minHeap.removeMin());  // 3
}
```

### Max Heap Implementation
```dart
class MaxHeap<T extends Comparable> {
  List<T> heap = [];
  
  void add(T value) {
    heap.add(value);
    _siftUp(heap.length - 1);
  }
  
  T removeMax() {
    if(heap.isEmpty) throw Exception('Heap is empty');
    
    T max = heap[0];
    heap[0] = heap.last;
    heap.removeLast();
    
    if(heap.isNotEmpty) _siftDown(0);
    return max;
  }
  
  T get max => heap[0];
  bool get isEmpty => heap.isEmpty;
  int get length => heap.length;
  
  void _siftUp(int i) {
    while(i > 0) {
      int parent = (i - 1) ~/ 2;
      if(heap[i].compareTo(heap[parent]) <= 0) break;  // Changed comparison
      _swap(i, parent);
      i = parent;
    }
  }
  
  void _siftDown(int i) {
    while(true) {
      int largest = i;
      int left = 2 * i + 1;
      int right = 2 * i + 2;
      
      if(left < heap.length && heap[left].compareTo(heap[largest]) > 0) {
        largest = left;
      }
      if(right < heap.length && heap[right].compareTo(heap[largest]) > 0) {
        largest = right;
      }
      
      if(largest == i) break;
      
      _swap(i, largest);
      i = largest;
    }
  }
  
  void _swap(int i, int j) {
    T temp = heap[i];
    heap[i] = heap[j];
    heap[j] = temp;
  }
}
```

---

## 🎯 ALGORITHMS

### Sorting
```dart
// List sort
list.sort();                                     // Ascending
list.sort((a, b) => b.compareTo(a));            // Descending

// Sort by custom criteria
list.sort((a, b) {
  if(a[0] != b[0]) return a[0].compareTo(b[0]);
  return a[1].compareTo(b[1]);
});

// Sort objects by property
people.sort((a, b) => a.age.compareTo(b.age));
```

### Binary Search (Custom Implementation)
```dart
int binarySearch(List<int> arr, int target) {
  int left = 0, right = arr.length - 1;
  
  while(left <= right) {
    int mid = left + (right - left) ~/ 2;  // ~/ is integer division!
    
    if(arr[mid] == target) return mid;
    if(arr[mid] < target) left = mid + 1;
    else right = mid - 1;
  }
  return -1;
}

// Lower bound (first >= x)
int lowerBound(List<int> arr, int x) {
  int left = 0, right = arr.length;
  
  while(left < right) {
    int mid = left + (right - left) ~/ 2;
    if(arr[mid] < x) left = mid + 1;
    else right = mid;
  }
  return left;
}

// Upper bound (first > x)
int upperBound(List<int> arr, int x) {
  int left = 0, right = arr.length;
  
  while(left < right) {
    int mid = left + (right - left) ~/ 2;
    if(arr[mid] <= x) left = mid + 1;
    else right = mid;
  }
  return left;
}

// Binary search on answer
int binarySearchAnswer(int low, int high, bool Function(int) check) {
  int ans = -1;
  
  while(low <= high) {
    int mid = low + (high - low) ~/ 2;
    
    if(check(mid)) {
      ans = mid;
      high = mid - 1;
    } else {
      low = mid + 1;
    }
  }
  return ans;
}
```

### Two Pointers
```dart
// Find pair with sum
List<int> twoSum(List<int> arr, int target) {
  int left = 0, right = arr.length - 1;
  
  while(left < right) {
    int sum = arr[left] + arr[right];
    if(sum == target) return [left, right];
    if(sum < target) left++;
    else right--;
  }
  return [-1, -1];
}

// Remove duplicates
int removeDuplicates(List<int> arr) {
  if(arr.isEmpty) return 0;
  
  int j = 0;
  for(int i = 1; i < arr.length; i++) {
    if(arr[i] != arr[j]) {
      arr[++j] = arr[i];
    }
  }
  return j + 1;
}
```

### Sliding Window
```dart
// Fixed size - Maximum sum of k elements
int maxSumKElements(List<int> arr, int k) {
  int sum = 0;
  for(int i = 0; i < k; i++) sum += arr[i];
  int maxSum = sum;
  
  for(int i = k; i < arr.length; i++) {
    sum += arr[i] - arr[i - k];
    maxSum = max(maxSum, sum);
  }
  return maxSum;
}

// Variable size - Longest substring with k distinct
int longestSubstringKDistinct(String s, int k) {
  Map<String, int> freq = {};
  int left = 0, maxLen = 0;
  
  for(int right = 0; right < s.length; right++) {
    String c = s[right];
    freq[c] = (freq[c] ?? 0) + 1;
    
    while(freq.length > k) {
      String leftChar = s[left];
      freq[leftChar] = freq[leftChar]! - 1;
      if(freq[leftChar] == 0) freq.remove(leftChar);
      left++;
    }
    
    maxLen = max(maxLen, right - left + 1);
  }
  return maxLen;
}
```

### Prefix Sum
```dart
// 1D prefix sum
List<int> buildPrefixSum(List<int> arr) {
  int n = arr.length;
  List<int> prefix = List.filled(n + 1, 0);
  
  for(int i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + arr[i];
  }
  return prefix;
}

// Query sum [l, r]
int rangeSum(List<int> prefix, int l, int r) {
  return prefix[r + 1] - prefix[l];
}

// 2D prefix sum
List<List<int>> build2DPrefix(List<List<int>> matrix) {
  int n = matrix.length, m = matrix[0].length;
  List<List<int>> prefix = List.generate(
    n + 1, 
    (_) => List.filled(m + 1, 0)
  );
  
  for(int i = 1; i <= n; i++) {
    for(int j = 1; j <= m; j++) {
      prefix[i][j] = matrix[i-1][j-1] 
                   + prefix[i-1][j] 
                   + prefix[i][j-1] 
                   - prefix[i-1][j-1];
    }
  }
  return prefix;
}

// Query 2D sum
int query2D(List<List<int>> prefix, int r1, int c1, int r2, int c2) {
  return prefix[r2+1][c2+1] 
       - prefix[r1][c2+1] 
       - prefix[r2+1][c1] 
       + prefix[r1][c1];
}
```

---

## 📈 GRAPH ALGORITHMS

### Graph Representation
```dart
// Adjacency List
List<List<int>> adj = List.generate(n, (_) => []);

// Add edge
adj[u].add(v);                                   // Directed
adj[u].add(v);                                   // Undirected
adj[v].add(u);

// Weighted graph
List<List<List<int>>> adj = List.generate(n, (_) => []);
adj[u].add([v, weight]);
```

### BFS
```dart
List<int> bfs(int start, List<List<int>> adj) {
  int n = adj.length;
  List<int> dist = List.filled(n, -1);
  Queue<int> queue = Queue();
  
  queue.add(start);
  dist[start] = 0;
  
  while(queue.isNotEmpty) {
    int u = queue.removeFirst();
    
    for(int v in adj[u]) {
      if(dist[v] == -1) {
        dist[v] = dist[u] + 1;
        queue.add(v);
      }
    }
  }
  return dist;
}

// BFS on grid
List<List<int>> directions = [[-1, 0], [1, 0], [0, -1], [0, 1]];

void bfsGrid(int sr, int sc, List<List<int>> grid) {
  int n = grid.length, m = grid[0].length;
  List<List<bool>> visited = List.generate(n, (_) => List.filled(m, false));
  Queue<List<int>> queue = Queue();
  
  queue.add([sr, sc]);
  visited[sr][sc] = true;
  
  while(queue.isNotEmpty) {
    var curr = queue.removeFirst();
    int x = curr[0], y = curr[1];
    
    for(var dir in directions) {
      int nx = x + dir[0], ny = y + dir[1];
      
      if(nx >= 0 && nx < n && ny >= 0 && ny < m 
         && !visited[nx][ny] && grid[nx][ny] != -1) {
        visited[nx][ny] = true;
        queue.add([nx, ny]);
      }
    }
  }
}
```

### DFS
```dart
void dfs(int u, List<List<int>> adj, List<bool> visited) {
  visited[u] = true;
  
  // Process node u
  
  for(int v in adj[u]) {
    if(!visited[v]) {
      dfs(v, adj, visited);
    }
  }
}

// DFS with parent (for trees)
void dfs(int u, int parent, List<List<int>> adj) {
  for(int v in adj[u]) {
    if(v != parent) {
      dfs(v, u, adj);
    }
  }
}

// DFS cycle detection (directed)
bool hasCycle(int u, List<List<int>> adj, 
              List<bool> visited, List<bool> recStack) {
  visited[u] = true;
  recStack[u] = true;
  
  for(int v in adj[u]) {
    if(!visited[v]) {
      if(hasCycle(v, adj, visited, recStack)) return true;
    } else if(recStack[v]) {
      return true;
    }
  }
  
  recStack[u] = false;
  return false;
}
```

### Dijkstra's Algorithm
```dart
List<int> dijkstra(int start, List<List<List<int>>> adj) {
  int n = adj.length;
  List<int> dist = List.filled(n, 1 << 30);  // INF
  
  // Use custom MinHeap or implement with list + sorting
  var pq = MinHeap<List<int>>();  // [distance, node]
  
  dist[start] = 0;
  pq.add([0, start]);
  
  while(pq.isNotEmpty) {
    var curr = pq.removeMin();
    int d = curr[0], u = curr[1];
    
    if(d > dist[u]) continue;
    
    for(var edge in adj[u]) {
      int v = edge[0], w = edge[1];
      
      if(dist[u] + w < dist[v]) {
        dist[v] = dist[u] + w;
        pq.add([dist[v], v]);
      }
    }
  }
  return dist;
}
```

### Union-Find (Disjoint Set Union)
```dart
class UnionFind {
  List<int> parent, rank, size;
  int components;
  
  UnionFind(int n) {
    parent = List.generate(n, (i) => i);
    rank = List.filled(n, 0);
    size = List.filled(n, 1);
    components = n;
  }
  
  int find(int x) {
    if(parent[x] != x) {
      parent[x] = find(parent[x]);  // Path compression
    }
    return parent[x];
  }
  
  bool union(int x, int y) {
    int px = find(x), py = find(y);
    if(px == py) return false;
    
    // Union by rank
    if(rank[px] < rank[py]) {
      int temp = px; px = py; py = temp;
    }
    parent[py] = px;
    size[px] += size[py];
    if(rank[px] == rank[py]) rank[px]++;
    
    components--;
    return true;
  }
  
  bool connected(int x, int y) {
    return find(x) == find(y);
  }
  
  int getSize(int x) {
    return size[find(x)];
  }
  
  int getComponents() {
    return components;
  }
}
```

### Topological Sort (Kahn's Algorithm)
```dart
List<int> topologicalSort(List<List<int>> adj) {
  int n = adj.length;
  List<int> indegree = List.filled(n, 0);
  
  // Calculate indegree
  for(int u = 0; u < n; u++) {
    for(int v in adj[u]) {
      indegree[v]++;
    }
  }
  
  Queue<int> queue = Queue();
  for(int i = 0; i < n; i++) {
    if(indegree[i] == 0) {
      queue.add(i);
    }
  }
  
  List<int> result = [];
  while(queue.isNotEmpty) {
    int u = queue.removeFirst();
    result.add(u);
    
    for(int v in adj[u]) {
      if(--indegree[v] == 0) {
        queue.add(v);
      }
    }
  }
  
  return result.length == n ? result : [];  // Empty if cycle
}
```

---

## 🎯 BIT MANIPULATION

### Basic Operations
```dart
// Check if ith bit is set
bool isSet = (n & (1 << i)) != 0;

// Set ith bit
n |= (1 << i);

// Clear ith bit
n &= ~(1 << i);

// Toggle ith bit
n ^= (1 << i);

// Get rightmost set bit
int rightmost = n & (-n);

// Clear rightmost set bit
n &= (n - 1);

// Count set bits (custom implementation)
int countBits(int n) {
  int count = 0;
  while(n > 0) {
    count += n & 1;
    n >>= 1;
  }
  return count;
}

// Check if power of 2
bool isPow2 = (n > 0) && ((n & (n - 1)) == 0);
```

### Subset Generation
```dart
// Generate all subsets
void generateSubsets(List<int> nums) {
  int n = nums.length;
  
  for(int mask = 0; mask < (1 << n); mask++) {
    List<int> subset = [];
    for(int i = 0; i < n; i++) {
      if((mask & (1 << i)) != 0) {
        subset.add(nums[i]);
      }
    }
    // Process subset
  }
}
```

---

## 🧮 MATH & NUMBER THEORY

### GCD & LCM
```dart
import 'dart:math';

// GCD
int gcd(int a, int b) {
  return b == 0 ? a : gcd(b, a % b);
}

// LCM
int lcm(int a, int b) {
  return (a ~/ gcd(a, b)) * b;
}
```

### Prime Numbers
```dart
// Check if prime
bool isPrime(int n) {
  if(n <= 1) return false;
  if(n <= 3) return true;
  if(n % 2 == 0 || n % 3 == 0) return false;
  
  for(int i = 5; i * i <= n; i += 6) {
    if(n % i == 0 || n % (i + 2) == 0) return false;
  }
  return true;
}

// Sieve of Eratosthenes
List<bool> sieve(int n) {
  List<bool> isPrime = List.filled(n + 1, true);
  isPrime[0] = isPrime[1] = false;
  
  for(int i = 2; i * i <= n; i++) {
    if(isPrime[i]) {
      for(int j = i * i; j <= n; j += i) {
        isPrime[j] = false;
      }
    }
  }
  return isPrime;
}

// Prime factorization
Map<int, int> primeFactorize(int n) {
  Map<int, int> factors = {};
  
  for(int i = 2; i * i <= n; i++) {
    while(n % i == 0) {
      factors[i] = (factors[i] ?? 0) + 1;
      n ~/= i;
    }
  }
  
  if(n > 1) factors[n] = 1;
  return factors;
}
```

### Modular Arithmetic
```dart
// Modular addition
int addMod(int a, int b, int mod) {
  return ((a % mod) + (b % mod)) % mod;
}

// Modular multiplication
int mulMod(int a, int b, int mod) {
  return ((a % mod) * (b % mod)) % mod;
}

// Modular exponentiation
int powerMod(int base, int exp, int mod) {
  int result = 1;
  base %= mod;
  
  while(exp > 0) {
    if((exp & 1) == 1) {
      result = (result * base) % mod;
    }
    base = (base * base) % mod;
    exp >>= 1;
  }
  return result;
}

// Modular inverse (Fermat's Little Theorem)
int modInverse(int a, int mod) {
  return powerMod(a, mod - 2, mod);
}
```

### Other Math Functions
```dart
import 'dart:math';

// Power
int power = pow(base, exp).toInt();

// Square root
double sqrt = sqrt(x);

// Absolute value
int abs = x.abs();

// Max/Min
int maxVal = max(a, b);
int minVal = min(a, b);

// Ceiling/Floor
int ceilVal = (a / b).ceil();
int floorVal = (a / b).floor();
```

---

## 📦 DYNAMIC PROGRAMMING PATTERNS

### 1D DP
```dart
// Fibonacci
int fib(int n) {
  if(n <= 1) return n;
  
  int prev2 = 0, prev1 = 1;
  for(int i = 2; i <= n; i++) {
    int curr = prev1 + prev2;
    prev2 = prev1;
    prev1 = curr;
  }
  return prev1;
}

// Climbing stairs
int climbStairs(int n) {
  if(n <= 2) return n;
  
  int prev2 = 1, prev1 = 2;
  for(int i = 3; i <= n; i++) {
    int curr = prev1 + prev2;
    prev2 = prev1;
    prev1 = curr;
  }
  return prev1;
}

// House robber
int rob(List<int> nums) {
  int n = nums.length;
  if(n == 0) return 0;
  if(n == 1) return nums[0];
  
  int prev2 = nums[0];
  int prev1 = max(nums[0], nums[1]);
  
  for(int i = 2; i < n; i++) {
    int curr = max(prev1, prev2 + nums[i]);
    prev2 = prev1;
    prev1 = curr;
  }
  return prev1;
}
```

### 2D DP
```dart
// Unique paths
int uniquePaths(int m, int n) {
  List<List<int>> dp = List.generate(m, (_) => List.filled(n, 1));
  
  for(int i = 1; i < m; i++) {
    for(int j = 1; j < n; j++) {
      dp[i][j] = dp[i-1][j] + dp[i][j-1];
    }
  }
  return dp[m-1][n-1];
}

// Longest Common Subsequence
int longestCommonSubsequence(String s1, String s2) {
  int m = s1.length, n = s2.length;
  List<List<int>> dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  
  for(int i = 1; i <= m; i++) {
    for(int j = 1; j <= n; j++) {
      if(s1[i-1] == s2[j-1]) {
        dp[i][j] = dp[i-1][j-1] + 1;
      } else {
        dp[i][j] = max(dp[i-1][j], dp[i][j-1]);
      }
    }
  }
  return dp[m][n];
}

// 0/1 Knapsack
int knapsack01(List<int> weights, List<int> values, int W) {
  int n = weights.length;
  List<List<int>> dp = List.generate(n + 1, (_) => List.filled(W + 1, 0));
  
  for(int i = 1; i <= n; i++) {
    for(int w = 1; w <= W; w++) {
      if(weights[i-1] <= w) {
        dp[i][w] = max(dp[i-1][w], 
                      dp[i-1][w - weights[i-1]] + values[i-1]);
      } else {
        dp[i][w] = dp[i-1][w];
      }
    }
  }
  return dp[n][W];
}
```

---

## ⚠️ COMMON PITFALLS & BEST PRACTICES

### Integer Division
```dart
// ❌ WRONG - Returns double
var result = a / b;

// ✅ CORRECT - Integer division
int result = a ~/ b;  // THIS IS VERY IMPORTANT!
```

### Null Safety (Dart 3.0+)
```dart
// Nullable types
int? nullable = null;                            // Can be null
int nonNullable = 0;                             // Cannot be null

// Safe access
nullable?.toString();                            // Returns null if nullable is null
nullable ?? defaultValue;                        // Null coalescing
nullable ??= defaultValue;                       // Assign if null

// Force unwrap (use with caution!)
nullable!;                                       // Throws if null

// Late initialization
late int value;                                  // Initialize later
```

### Immutability
```dart
// final - Cannot reassign
final int x = 10;                                // Runtime constant

// const - Compile-time constant
const int y = 20;                                // Compile-time constant

// var - Mutable
var x = 10;                                      // Type inferred
```

### List Operations Return Iterables
```dart
// ❌ WRONG - Returns Iterable, not List
var result = list.map((x) => x * 2);
var result = list.where((x) => x > 0);

// ✅ CORRECT - Convert to List
var result = list.map((x) => x * 2).toList();
var result = list.where((x) => x > 0).toList();
```

### String Comparison
```dart
// ✅ CORRECT - Use == for content equality
if(s1 == s2) {}

// ❌ WRONG - identical() checks reference equality
if(identical(s1, s2)) {}  // Usually not what you want
```

---

## 🚀 TIME COMPLEXITY QUICK REFERENCE

```dart
// O(1)
list[i], map[key], set.contains(x)

// O(log n)
Binary search, custom heap operations

// O(n)
Single loop, list operations

// O(n log n)
Sorting: list.sort()

// O(n²)
Nested loops

// O(2ⁿ)
All subsets, exponential recursion

// O(n!)
All permutations
```

---

## 📏 DART-SPECIFIC NOTES

### Key Differences from Other Languages
```dart
// 1. Integer division
int result = a ~/ b;  // NOT a / b

// 2. Everything is an object (no primitives)
int x = 5;
x.isEven;  // true
x.isOdd;   // false

// 3. Cascade notation (..)
list..add(1)..add(2)..add(3);  // Chain operations

// 4. Fat arrow (=>) for single expressions
int square(int x) => x * x;

// 5. Named parameters
void greet({String? name, int? age}) {}
greet(name: 'Alice', age: 25);

// 6. Extension methods (like Kotlin)
extension IntExtensions on int {
  bool get isPrime => _isPrime(this);
}

// 7. Spread operator (...)
List<int> combined = [...list1, ...list2];

// 8. Collection if/for
List<int> numbers = [
  1,
  2,
  if(condition) 3,
  for(int i in range) i * 2,
];
```

### Useful Built-in Properties
```dart
// Numbers
42.isEven;                                       // true
42.isOdd;                                        // false
42.isNegative;                                   // false
(-42).abs();                                     // 42

// Strings  
'hello'.isEmpty;
'hello'.isNotEmpty;
'hello'.length;

// Lists
[1, 2, 3].isEmpty;
[1, 2, 3].isNotEmpty;
[1, 2, 3].first;
[1, 2, 3].last;
[1, 2, 3].length;
```

---

## 🎓 DART FOR FLUTTER DEVELOPERS

If you're coming from Flutter development, here's what you already know:

### You Already Use These!
```dart
// Lists - You use these everywhere in Flutter
List<Widget> children = [Text('Hello'), Text('World')];

// Maps - For configuration and state
Map<String, dynamic> config = {'theme': 'dark'};

// Sets - For unique collections
Set<String> selectedIds = {};

// Functional operations - ListView.builder, etc.
List<Widget> items = data.map((item) => Text(item)).toList();
```

### LeetCode-Specific Tips for Flutter Devs
```dart
// 1. No async/await needed for LeetCode!
// Flutter: await Future.delayed(...)
// LeetCode: Direct computation

// 2. Focus on algorithms, not UI
// Flutter: Widget tree, setState, BuildContext
// LeetCode: Arrays, graphs, dynamic programming

// 3. Integer division is crucial!
// int mid = left + (right - left) ~/ 2;  // Use ~/

// 4. Immutability matters less
// Flutter: Use immutable data for performance
// LeetCode: Mutate in place for efficiency

// 5. No null safety concerns with algorithms
// Most LeetCode problems assume non-null inputs
```

---

**Happy Coding! 🎯**
