# 🚀 C++ Ultimate Cheat Sheet for LeetCode
## Competitive Programming & Technical Interviews

---

## 🔤 BASIC DATA TYPES & PRIMITIVES

### Integer Types
```cpp
// Signed integers
char c = 'A';                             // 1 byte: -128 to 127
short s = 100;                            // 2 bytes: -32,768 to 32,767
int i = 1000;                             // 4 bytes: -2^31 to 2^31-1 (~2.1 billion)
long l = 10000L;                          // 4 bytes (same as int on most systems)
long long ll = 1000000000000LL;          // 8 bytes: -2^63 to 2^63-1

// Unsigned integers
unsigned char uc = 255;                   // 0 to 255
unsigned short us = 65535;                // 0 to 65,535
unsigned int ui = 4000000000U;           // 0 to ~4.2 billion
unsigned long ul = 10000UL;              // Same as unsigned int
unsigned long long ull = 18446744073709551615ULL; // 0 to 2^64-1

// Type aliases (prefer these for competitive programming)
typedef long long ll;
typedef unsigned long long ull;

// Constants
const int MAX = 100000;
const double PI = 3.14159265358979323846;

// Limits (from <climits> and <limits>)
INT_MIN;                                  // -2,147,483,648
INT_MAX;                                  // 2,147,483,647
LONG_LONG_MIN;                           // -9,223,372,036,854,775,808
LONG_LONG_MAX;                           // 9,223,372,036,854,775,807

// Using numeric_limits
#include <limits>
numeric_limits<int>::min();
numeric_limits<int>::max();
numeric_limits<double>::infinity();
```

### Floating Point Types
```cpp
float f = 3.14f;                         // 4 bytes, ~7 decimal digits precision
double d = 3.14159265358979;             // 8 bytes, ~15 decimal digits precision
long double ld = 3.14159265358979323846L; // 10-16 bytes, platform dependent

// Special values
#include <cmath>
INFINITY;                                 // Positive infinity
NAN;                                      // Not a Number
isnan(x);                                // Check if NaN
isinf(x);                                // Check if infinity
isfinite(x);                             // Check if finite
```

### Boolean & Character
```cpp
bool flag = true;                        // 1 byte: true or false
bool flag2 = false;

char c = 'A';                            // Single character
char digit = '5';                        // Character digit

// Character operations
c - 'A';                                 // Position in alphabet (0-25)
digit - '0';                             // Convert digit char to int
toupper(c);                              // To uppercase
tolower(c);                              // To lowercase
isalpha(c), isdigit(c), isalnum(c);    // Character checks
```

### Type Conversion & Casting
```cpp
// Implicit conversion
int i = 10;
double d = i;                            // int to double (safe)

// Explicit casting (C-style)
double d = 3.14;
int i = (int)d;                          // 3

// C++ style casting (preferred)
int i = static_cast<int>(d);
long long ll = static_cast<long long>(i);

// Between char and int
char c = 'A';
int code = static_cast<int>(c);          // ASCII code
char fromCode = static_cast<char>(65);   // 'A'
```

---

## 📦 ARRAYS (Fixed Size)

### Declaration & Initialization
```cpp
// Basic declaration
int arr[5];                              // Uninitialized (garbage values)
int arr[5] = {0};                        // All zeros
int arr[5] = {1, 2, 3};                 // Rest are zeros
int arr[] = {1, 2, 3, 4, 5};            // Size inferred

// 2D arrays
int mat[3][4];                           // 3 rows, 4 columns
int mat[3][4] = {{1,2,3,4}, {5,6,7,8}, {9,10,11,12}};
int mat[3][4] = {0};                    // All zeros

// Character arrays (C-strings)
char str[100];                           // Character array
char str[] = "hello";                    // Null-terminated: {'h','e','l','l','o','\0'}
```

### Operations
```cpp
// Size
int size = sizeof(arr) / sizeof(arr[0]); // Number of elements

// Access & Modify
arr[0] = 10;                             // Set element
int x = arr[0];                          // Get element

// Fill with value
fill(arr, arr + n, value);               // Using STL
memset(arr, 0, sizeof(arr));            // Set all bytes to 0 (only for 0 and -1!)

// Copy
int copy[5];
copy(arr, arr + 5, copy);                // Using STL
memcpy(copy, arr, sizeof(arr));         // Using memcpy

// Compare
bool equal = equal(arr1, arr1 + n, arr2); // Using STL
```

### Iteration
```cpp
int arr[] = {1, 2, 3, 4, 5};
int n = 5;

// Index-based
for(int i = 0; i < n; i++) {
    cout << arr[i] << " ";
}

// Range-based for loop (C++11)
for(int x : arr) {
    cout << x << " ";
}

// With reference (to modify)
for(int& x : arr) {
    x *= 2;
}

// Iterators (for array passed to function)
for(int* ptr = arr; ptr != arr + n; ptr++) {
    cout << *ptr << " ";
}

// Reverse iteration
for(int i = n-1; i >= 0; i--) {
    cout << arr[i] << " ";
}
```

### Arrays & Functions
```cpp
// Pass array to function (decays to pointer)
void process(int arr[], int n) {
    // Can modify original array
}

// Pass by reference (preserves size info)
void process(int (&arr)[5]) {
    // Size is known
}

// Return array (use vector or dynamic allocation)
vector<int> getArray() {
    return {1, 2, 3, 4, 5};
}
```

---

## 🔗 POINTERS & REFERENCES

### Pointers Basics
```cpp
int x = 10;
int* ptr = &x;                           // Pointer to x
*ptr = 20;                               // Dereference and modify
cout << *ptr;                            // Access value through pointer

// Null pointer
int* ptr = nullptr;                      // C++11 (preferred)
int* ptr = NULL;                         // Old style

// Check null
if(ptr != nullptr) {
    // Safe to use
}

// Pointer arithmetic
int arr[] = {1, 2, 3, 4, 5};
int* ptr = arr;
ptr++;                                   // Points to arr[1]
ptr += 2;                                // Points to arr[3]
int value = *(ptr + 1);                 // Access arr[4]
```

### References
```cpp
int x = 10;
int& ref = x;                            // Reference to x (alias)
ref = 20;                                // Modifies x

// References must be initialized
int& ref;                                // ERROR!

// Cannot reassign reference
int y = 30;
ref = y;                                 // This assigns y's value to x, not reassigns ref!

// Const references
const int& cref = x;                    // Cannot modify through cref
```

### Pointers vs References
```cpp
// Use references when:
// - You need an alias to existing variable
// - Passing to functions (avoid copies)
void swap(int& a, int& b) {
    int temp = a;
    a = b;
    b = temp;
}

// Use pointers when:
// - You need to reassign
// - You need null value
// - Dynamic memory allocation
int* ptr = new int(10);
delete ptr;
```

---

## 🔗 LINKED LIST (Custom Implementation)

### Node Definition
```cpp
// Singly Linked List Node
struct ListNode {
    int val;
    ListNode* next;
    
    ListNode() : val(0), next(nullptr) {}
    ListNode(int x) : val(x), next(nullptr) {}
    ListNode(int x, ListNode* next) : val(x), next(next) {}
};

// Doubly Linked List Node
struct DListNode {
    int val;
    DListNode* prev;
    DListNode* next;
    
    DListNode(int x) : val(x), prev(nullptr), next(nullptr) {}
};
```

### Basic Operations - Singly Linked List
```cpp
// Create nodes
ListNode* head = new ListNode(1);
head->next = new ListNode(2);
head->next->next = new ListNode(3);

// OR create from array
ListNode* createList(vector<int>& arr) {
    if(arr.empty()) return nullptr;
    
    ListNode* head = new ListNode(arr[0]);
    ListNode* curr = head;
    
    for(int i = 1; i < arr.size(); i++) {
        curr->next = new ListNode(arr[i]);
        curr = curr->next;
    }
    return head;
}

// Insert at beginning
ListNode* insertAtBegin(ListNode* head, int val) {
    ListNode* newNode = new ListNode(val);
    newNode->next = head;
    return newNode;  // New head
}

// Insert at end
ListNode* insertAtEnd(ListNode* head, int val) {
    ListNode* newNode = new ListNode(val);
    
    if(!head) return newNode;
    
    ListNode* curr = head;
    while(curr->next) {
        curr = curr->next;
    }
    curr->next = newNode;
    return head;
}

// Insert at position (0-indexed)
ListNode* insertAtPos(ListNode* head, int pos, int val) {
    if(pos == 0) return insertAtBegin(head, val);
    
    ListNode* curr = head;
    for(int i = 0; i < pos - 1 && curr; i++) {
        curr = curr->next;
    }
    
    if(!curr) return head;  // Invalid position
    
    ListNode* newNode = new ListNode(val);
    newNode->next = curr->next;
    curr->next = newNode;
    return head;
}

// Delete node with value
ListNode* deleteNode(ListNode* head, int val) {
    if(!head) return nullptr;
    
    // If head needs to be deleted
    if(head->val == val) {
        ListNode* temp = head->next;
        delete head;
        return temp;
    }
    
    ListNode* curr = head;
    while(curr->next && curr->next->val != val) {
        curr = curr->next;
    }
    
    if(curr->next) {
        ListNode* temp = curr->next;
        curr->next = temp->next;
        delete temp;
    }
    return head;
}

// Delete at position
ListNode* deleteAtPos(ListNode* head, int pos) {
    if(!head) return nullptr;
    
    if(pos == 0) {
        ListNode* temp = head->next;
        delete head;
        return temp;
    }
    
    ListNode* curr = head;
    for(int i = 0; i < pos - 1 && curr->next; i++) {
        curr = curr->next;
    }
    
    if(curr->next) {
        ListNode* temp = curr->next;
        curr->next = temp->next;
        delete temp;
    }
    return head;
}

// Search for value
bool search(ListNode* head, int val) {
    ListNode* curr = head;
    while(curr) {
        if(curr->val == val) return true;
        curr = curr->next;
    }
    return false;
}

// Get length
int getLength(ListNode* head) {
    int len = 0;
    ListNode* curr = head;
    while(curr) {
        len++;
        curr = curr->next;
    }
    return len;
}

// Get nth node (0-indexed)
ListNode* getNth(ListNode* head, int n) {
    ListNode* curr = head;
    for(int i = 0; i < n && curr; i++) {
        curr = curr->next;
    }
    return curr;
}
```

### Iteration Patterns
```cpp
// Basic traversal
void traverse(ListNode* head) {
    ListNode* curr = head;
    while(curr) {
        cout << curr->val << " ";
        curr = curr->next;
    }
}

// With index
void traverseWithIndex(ListNode* head) {
    ListNode* curr = head;
    int index = 0;
    while(curr) {
        cout << "Index " << index << ": " << curr->val << "\n";
        curr = curr->next;
        index++;
    }
}

// Two pointers (slow-fast)
ListNode* findMiddle(ListNode* head) {
    ListNode* slow = head;
    ListNode* fast = head;
    
    while(fast && fast->next) {
        slow = slow->next;
        fast = fast->next->next;
    }
    return slow;
}

// Previous + Current pattern
void traverseWithPrev(ListNode* head) {
    ListNode* prev = nullptr;
    ListNode* curr = head;
    
    while(curr) {
        // Process with both prev and curr
        
        prev = curr;
        curr = curr->next;
    }
}
```

### Copy & Clone
```cpp
// Deep copy (create new nodes)
ListNode* deepCopy(ListNode* head) {
    if(!head) return nullptr;
    
    ListNode* newHead = new ListNode(head->val);
    ListNode* curr = head->next;
    ListNode* newCurr = newHead;
    
    while(curr) {
        newCurr->next = new ListNode(curr->val);
        newCurr = newCurr->next;
        curr = curr->next;
    }
    
    return newHead;
}

// Shallow copy (just pointer)
ListNode* shallowCopy(ListNode* head) {
    return head;  // Both point to same nodes!
}

// Convert to vector
vector<int> toVector(ListNode* head) {
    vector<int> result;
    ListNode* curr = head;
    while(curr) {
        result.push_back(curr->val);
        curr = curr->next;
    }
    return result;
}

// Create from vector
ListNode* fromVector(vector<int>& arr) {
    if(arr.empty()) return nullptr;
    
    ListNode* head = new ListNode(arr[0]);
    ListNode* curr = head;
    
    for(int i = 1; i < arr.size(); i++) {
        curr->next = new ListNode(arr[i]);
        curr = curr->next;
    }
    return head;
}
```

### Common Patterns
```cpp
// Reverse linked list
ListNode* reverse(ListNode* head) {
    ListNode* prev = nullptr;
    ListNode* curr = head;
    
    while(curr) {
        ListNode* next = curr->next;
        curr->next = prev;
        prev = curr;
        curr = next;
    }
    return prev;
}

// Detect cycle
bool hasCycle(ListNode* head) {
    ListNode* slow = head;
    ListNode* fast = head;
    
    while(fast && fast->next) {
        slow = slow->next;
        fast = fast->next->next;
        if(slow == fast) return true;
    }
    return false;
}

// Merge two sorted lists
ListNode* mergeTwoLists(ListNode* l1, ListNode* l2) {
    ListNode dummy(0);
    ListNode* curr = &dummy;
    
    while(l1 && l2) {
        if(l1->val < l2->val) {
            curr->next = l1;
            l1 = l1->next;
        } else {
            curr->next = l2;
            l2 = l2->next;
        }
        curr = curr->next;
    }
    
    curr->next = l1 ? l1 : l2;
    return dummy.next;
}

// Remove nth from end
ListNode* removeNthFromEnd(ListNode* head, int n) {
    ListNode dummy(0);
    dummy.next = head;
    
    ListNode* first = &dummy;
    ListNode* second = &dummy;
    
    // Move first n+1 steps ahead
    for(int i = 0; i <= n; i++) {
        first = first->next;
    }
    
    // Move both until first reaches end
    while(first) {
        first = first->next;
        second = second->next;
    }
    
    // Remove node
    ListNode* temp = second->next;
    second->next = temp->next;
    delete temp;
    
    return dummy.next;
}
```

### Memory Management
```cpp
// Delete entire list
void deleteList(ListNode* head) {
    while(head) {
        ListNode* temp = head;
        head = head->next;
        delete temp;
    }
}

// IMPORTANT: Always delete dynamically allocated nodes!
```

---

## ⚡ Fast I/O Boilerplate

```cpp
#include <bits/stdc++.h>
using namespace std;

// Fast I/O - Add at beginning of main()
ios_base::sync_with_stdio(false);
cin.tie(NULL);
cout.tie(NULL);

// Type aliases
typedef long long ll;
typedef unsigned long long ull;
typedef long double ld;
typedef pair<int, int> pii;
typedef pair<ll, ll> pll;
typedef vector<int> vi;
typedef vector<ll> vll;
typedef vector<pii> vpii;
typedef vector<string> vs;

// Constants
const int MOD = 1e9 + 7;
const int MOD2 = 998244353;
const int INF = 1e9;
const ll LINF = 1e18;
const double EPS = 1e-9;
const double PI = acos(-1.0);

// Macros
#define pb push_back
#define mp make_pair
#define fi first
#define se second
#define all(x) (x).begin(), (x).end()
#define rall(x) (x).rbegin(), (x).rend()
#define sz(x) (int)(x).size()
#define rep(i, a, b) for(int i = a; i < b; i++)
#define per(i, a, b) for(int i = a; i >= b; i--)
#define trav(a, x) for(auto& a : x)
#define uid(a, b) uniform_int_distribution<int>(a, b)(rng)

// Debug
#ifdef LOCAL
#define debug(x) cerr << #x << " = " << (x) << endl;
#else
#define debug(x)
#endif

// Utility
template<typename T>
void read(T& x) { cin >> x; }
template<typename T, typename... Args>
void read(T& first, Args&... args) { read(first); read(args...); }

mt19937 rng(chrono::steady_clock::now().time_since_epoch().count());
```

---

## 📊 VECTOR (Dynamic Array)

### Declaration & Initialization
```cpp
vector<int> v;                              // Empty vector
vector<int> v(n);                           // Size n, default 0
vector<int> v(n, val);                      // Size n, all initialized to val
vector<int> v = {1, 2, 3, 4, 5};           // Initialize with values
vector<int> v(arr, arr + n);                // From array
vector<int> v2(v.begin(), v.end());         // Copy from another vector
vector<vector<int>> mat(n, vector<int>(m, 0)); // 2D vector n×m

// Using iterators
vector<int> v(v1.begin() + 2, v1.end() - 1); // Subvector
```

### Core Operations
```cpp
// Adding elements
v.push_back(x);                             // O(1) amortized - add to end
v.emplace_back(x);                          // O(1) - construct in place (faster)
v.insert(v.begin() + i, x);                 // O(n) - insert at position
v.insert(v.end(), {1, 2, 3});              // Insert multiple elements

// Removing elements
v.pop_back();                               // O(1) - remove last
v.erase(v.begin() + i);                     // O(n) - remove at position
v.erase(v.begin() + i, v.begin() + j);     // O(n) - remove range [i, j)
v.clear();                                  // Remove all elements

// Access
v[i];                                       // O(1) - no bounds check
v.at(i);                                    // O(1) - with bounds check
v.front();                                  // First element
v.back();                                   // Last element
v.data();                                   // Pointer to underlying array

// Size & Capacity
v.size();                                   // Number of elements
v.empty();                                  // Check if empty
v.capacity();                               // Allocated capacity
v.resize(n);                                // Resize to n elements
v.resize(n, val);                           // Resize with default value
v.reserve(n);                               // Reserve capacity (no initialization)
v.shrink_to_fit();                          // Reduce capacity to size
```

### Iteration (Comprehensive Examples)
```cpp
vector<int> v = {10, 20, 30, 40, 50};

// 1. Range-based for loop (Simplest - C++11)
for(int x : v) {
    cout << x << " ";                       // By value (copy)
}

for(int& x : v) {
    x *= 2;                                 // By reference (modify original)
}

for(const int& x : v) {
    cout << x << " ";                       // Const reference (no copy, can't modify)
}

// 2. Index-based (When you need index)
for(int i = 0; i < v.size(); i++) {
    cout << i << ": " << v[i] << "\n";
}

for(size_t i = 0; i < v.size(); i++) {     // Using size_t (proper type)
    v[i] *= 2;
}

// 3. Forward Iterators
for(auto it = v.begin(); it != v.end(); it++) {
    cout << *it << " ";                     // Dereference to get value
    *it = 100;                              // Modify through iterator
}

// Using vector<int>::iterator (explicit type)
for(vector<int>::iterator it = v.begin(); it != v.end(); it++) {
    cout << *it << " ";
}

// 4. Const Iterators (read-only)
for(auto it = v.cbegin(); it != v.cend(); it++) {
    cout << *it << " ";                     // Can read
    // *it = 100;                           // ERROR! Cannot modify
}

for(vector<int>::const_iterator it = v.cbegin(); it != v.cend(); ++it) {
    cout << *it << " ";
}

// 5. Reverse Iterators
for(auto it = v.rbegin(); it != v.rend(); it++) {
    cout << *it << " ";                     // Iterates backward: 50 40 30 20 10
}

// Modify in reverse
for(auto it = v.rbegin(); it != v.rend(); it++) {
    *it += 1;
}

// 6. Iterator Arithmetic
auto it = v.begin();
it++;                                       // Move to next
it += 2;                                    // Move 2 positions forward
it--;                                       // Move back
cout << *it;                                // Access current element

// Random access
auto it2 = v.begin() + 2;                  // Points to v[2]
cout << *(v.begin() + 3);                  // Access v[3]

// Distance between iterators
auto start = v.begin();
auto end = v.begin() + 3;
int dist = distance(start, end);           // 3

// 7. Iterate with prev/next
for(auto it = v.begin(); it != v.end(); it++) {
    if(it != v.begin()) {
        auto prev = it - 1;
        cout << "Prev: " << *prev << ", Curr: " << *it << "\n";
    }
    
    if(it + 1 != v.end()) {
        auto next = it + 1;
        cout << "Curr: " << *it << ", Next: " << *next << "\n";
    }
}

// 8. Using next() and prev() functions
auto it = v.begin();
auto second = next(it);                     // Second element
auto third = next(it, 2);                   // Third element
auto last = prev(v.end());                  // Last element

// 9. Iterate with advance()
auto it = v.begin();
advance(it, 2);                             // Move 2 positions
cout << *it;                                // v[2]

// 10. Two-pointer iteration
auto left = v.begin();
auto right = v.end() - 1;
while(left < right) {
    cout << *left << " " << *right << "\n";
    left++;
    right--;
}

// 11. Iterate and erase (correct pattern)
for(auto it = v.begin(); it != v.end(); ) {
    if(*it < 0) {
        it = v.erase(it);                   // erase() returns next iterator
    } else {
        it++;
    }
}

// 12. Iterate with std::for_each (C++11)
for_each(v.begin(), v.end(), [](int x) {
    cout << x << " ";
});

// With modification
for_each(v.begin(), v.end(), [](int& x) {
    x *= 2;
});

// 13. Enumerate pattern (index + value)
int index = 0;
for(auto it = v.begin(); it != v.end(); it++, index++) {
    cout << "Index " << index << ": " << *it << "\n";
}

// Or simply
for(int i = 0; i < v.size(); i++) {
    cout << "Index " << i << ": " << v[i] << "\n";
}

// 14. Iterate subset [start, end)
for(auto it = v.begin() + 1; it != v.begin() + 4; it++) {
    cout << *it << " ";                     // Elements at index 1, 2, 3
}

// 15. Parallel iteration of two vectors
vector<int> v1 = {1, 2, 3};
vector<int> v2 = {4, 5, 6};

auto it1 = v1.begin();
auto it2 = v2.begin();
while(it1 != v1.end() && it2 != v2.end()) {
    cout << *it1 << " + " << *it2 << " = " << (*it1 + *it2) << "\n";
    it1++;
    it2++;
}
```

### Iterator Types Summary
```cpp
// Forward Iterator
vector<int>::iterator it = v.begin();
auto it = v.begin();                        // C++11 auto

// Const Iterator (read-only)
vector<int>::const_iterator it = v.cbegin();
auto it = v.cbegin();

// Reverse Iterator
vector<int>::reverse_iterator it = v.rbegin();
auto it = v.rbegin();

// Const Reverse Iterator
vector<int>::const_reverse_iterator it = v.crbegin();
auto it = v.crbegin();
```

### Sorting & Searching
```cpp
// Sorting
sort(v.begin(), v.end());                   // Ascending O(n log n)
sort(all(v));                               // Using macro
sort(v.begin(), v.end(), greater<int>());   // Descending
reverse(v.begin(), v.end());                // Reverse O(n)
reverse(all(v));                            // Using macro

// Custom comparator
sort(all(v), [](int a, int b) {
    return a > b;                           // Descending
});

// Partial sort (first k elements sorted)
partial_sort(v.begin(), v.begin() + k, v.end());

// nth_element (kth smallest element in correct position)
nth_element(v.begin(), v.begin() + k, v.end());

// Binary search (requires sorted vector)
bool found = binary_search(all(v), x);      // O(log n) - returns bool

// Lower bound (first element >= x)
auto it = lower_bound(all(v), x);           // Returns iterator
int idx = lower_bound(all(v), x) - v.begin(); // Get index
int pos = distance(v.begin(), lower_bound(all(v), x));

// Upper bound (first element > x)
auto it = upper_bound(all(v), x);
int idx = upper_bound(all(v), x) - v.begin();

// Count occurrences in sorted array
int cnt = upper_bound(all(v), x) - lower_bound(all(v), x);

// Equal range (both bounds at once)
auto [first, last] = equal_range(all(v), x);
```

### Algorithms
```cpp
// Min/Max element
int maxVal = *max_element(all(v));          // Maximum value
int minVal = *min_element(all(v));          // Minimum value
auto [minIt, maxIt] = minmax_element(all(v)); // Both at once

// Sum
int sum = accumulate(all(v), 0);            // Sum with initial 0
ll sum = accumulate(all(v), 0LL);           // Use 0LL for long long

// Count
int cnt = count(all(v), x);                 // Count occurrences of x
int cnt = count_if(all(v), [](int x) { return x > 0; }); // Count with condition

// Find
auto it = find(all(v), x);                  // Find first occurrence
if(it != v.end()) {
    int idx = it - v.begin();
}

// Remove duplicates (must be sorted first)
sort(all(v));
v.erase(unique(all(v)), v.end());

// Permutations
sort(all(v));
do {
    // Process permutation
} while(next_permutation(all(v)));

// Previous permutation
prev_permutation(all(v));

// Transform
transform(all(v), v.begin(), [](int x) { return x * 2; }); // Double each

// Rotate
rotate(v.begin(), v.begin() + k, v.end()); // Rotate k positions left

// Partition
partition(all(v), [](int x) { return x > 0; }); // Move elements matching condition to front

// Is sorted check
bool sorted = is_sorted(all(v));

// Fill
fill(all(v), val);                          // Fill with value
```

### Advanced Tips
```cpp
// Reserve to avoid reallocations
v.reserve(1000000);                         // Pre-allocate for better performance

// Emplace vs Push
v.push_back(make_pair(1, 2));              // Creates temp pair
v.emplace_back(1, 2);                      // Constructs in place (faster)

// Swap trick to clear memory
vector<int>().swap(v);                      // Actually frees memory
v.clear();                                  // Doesn't free memory

// 2D vector access
mat[i][j] = value;

// Flatten 2D to 1D
vector<int> flat;
for(auto& row : mat) {
    flat.insert(flat.end(), all(row));
}
```

---

## 📝 STRING

### Declaration & Initialization
```cpp
string s;                                   // Empty string
string s = "hello";                         // From literal
string s("hello");                          // Constructor
string s(n, 'a');                          // n times character 'a'
string s(str.begin(), str.end());          // From iterators
```

### Operations
```cpp
// Size & Access
s.length();                                 // Length (same as size())
s.size();                                   // Number of characters
s.empty();                                  // Check empty
s[i];                                       // Access character O(1)
s.at(i);                                    // Access with bounds check
s.front();                                  // First character
s.back();                                   // Last character

// Modification
s.push_back('c');                           // Append character
s.pop_back();                               // Remove last character
s += "text";                                // Concatenate
s.append("text");                           // Append string
s.insert(pos, "text");                      // Insert at position
s.erase(pos, len);                          // Erase len characters from pos
s.erase(pos);                               // Erase from pos to end
s.clear();                                  // Clear string
s.resize(n);                                // Resize
s.resize(n, 'x');                          // Resize with fill character

// Substring
s.substr(pos);                              // From pos to end
s.substr(pos, len);                         // len characters from pos

// Search
s.find("sub");                              // Find substring (returns size_t)
s.find('c');                                // Find character
s.find("sub", pos);                         // Find starting from pos
s.rfind("sub");                             // Find from end
s.find_first_of("aeiou");                  // First occurrence of any char
s.find_last_of("aeiou");                   // Last occurrence of any char
s.find_first_not_of("abc");                // First char not in set

if(s.find("sub") != string::npos) {        // Check if found
    // Found
}

// Replace
s.replace(pos, len, "new");                // Replace substring
```

### String Algorithms
```cpp
// Sorting & Reversing
sort(all(s));                               // Sort characters
reverse(all(s));                            // Reverse string

// Case conversion
transform(all(s), s.begin(), ::tolower);   // To lowercase
transform(all(s), s.begin(), ::toupper);   // To uppercase

// Check functions (cctype)
isalpha(c);                                 // Is alphabetic
isdigit(c);                                 // Is digit
isalnum(c);                                 // Is alphanumeric
islower(c);                                 // Is lowercase
isupper(c);                                 // Is uppercase
isspace(c);                                 // Is whitespace
tolower(c);                                 // To lowercase
toupper(c);                                 // To uppercase
```

### Conversion
```cpp
// String to Number
int num = stoi(s);                          // String to int
long lnum = stol(s);                        // String to long
long long llnum = stoll(s);                 // String to long long
float fnum = stof(s);                       // String to float
double dnum = stod(s);                      // String to double
long double ldnum = stold(s);               // String to long double

// Number to String
string s = to_string(123);                  // Int to string
string s = to_string(3.14);                 // Double to string

// Character to int
int digit = c - '0';                        // For digit characters
int pos = c - 'a';                          // Position in alphabet (lowercase)
int pos = c - 'A';                          // Position in alphabet (uppercase)
```

### String Comparison
```cpp
s1 == s2;                                   // Equality
s1 != s2;                                   // Inequality
s1 < s2;                                    // Lexicographic comparison
s1.compare(s2);                             // Returns 0 if equal, <0 if s1<s2, >0 if s1>s2

// Compare substring
s1.compare(pos, len, s2);
```

### String Stream
```cpp
#include <sstream>

// Split string by delimiter
string s = "1 2 3 4 5";
stringstream ss(s);
int num;
while(ss >> num) {
    // Process num
}

// Build string efficiently
ostringstream oss;
oss << "Value: " << 42 << ", PI: " << 3.14;
string result = oss.str();

// Parse with multiple delimiters
stringstream ss(s);
string token;
while(getline(ss, token, ',')) {
    // Process token
}
```

### Advanced String Tips
```cpp
// C-style string conversion
const char* cstr = s.c_str();              // Get C-string
char* data = s.data();                     // Get modifiable data (C++17)

// Character codes
int code = s[i];                           // ASCII/Unicode value
char c = 'a' + 5;                          // Character arithmetic

// String hashing (for pattern matching)
const ll BASE = 31;
const ll MOD = 1e9 + 9;
ll computeHash(const string& s) {
    ll hash = 0;
    ll pow = 1;
    for(char c : s) {
        hash = (hash + (c - 'a' + 1) * pow) % MOD;
        pow = (pow * BASE) % MOD;
    }
    return hash;
}
```

---

## 🗺️ MAP (Ordered Map - Red-Black Tree)

### Declaration
```cpp
map<int, int> m;                            // Empty map
map<string, int> m = {{"a", 1}, {"b", 2}};
map<int, vector<int>> m;                   // Map to vector
map<pair<int,int>, int> m;                 // Pair as key
```

### Operations - O(log n)
```cpp
// Insert/Update
m[key] = value;                            // Insert or update
m.insert({key, value});                    // Insert (doesn't overwrite)
m.insert(make_pair(key, value));
m.emplace(key, value);                     // Construct in place

// Access
m[key];                                    // Access (creates if doesn't exist!)
m.at(key);                                 // Access with exception if not found

// Remove
m.erase(key);                              // Remove by key
m.erase(it);                               // Remove by iterator
m.clear();                                 // Remove all

// Search
m.find(key);                               // Returns iterator (m.end() if not found)
m.count(key);                              // Returns 0 or 1
m.contains(key);                           // C++20 - returns bool

// Check existence
if(m.find(key) != m.end()) {}
if(m.count(key)) {}

// Size
m.size();
m.empty();
```

### Iteration (Sorted by Key) - Comprehensive
```cpp
map<int, string> m = {{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}};

// 1. Range-based for with structured binding (C++17) - BEST
for(auto& [key, value] : m) {
    cout << key << " -> " << value << "\n";
    value += " modified";                   // Can modify value
}

// With const (read-only)
for(const auto& [key, value] : m) {
    cout << key << " -> " << value << "\n";
    // value = "new";                       // ERROR!
}

// 2. Range-based for with pair
for(auto& pair : m) {
    int key = pair.first;
    string value = pair.second;
    cout << key << " -> " << value << "\n";
}

for(auto& p : m) {                          // Shorter variable name
    p.second += " updated";                 // Modify value through pair
}

// 3. Forward Iterator (most flexible)
for(auto it = m.begin(); it != m.end(); it++) {
    cout << it->first << " -> " << it->second << "\n";
    it->second = "new value";               // Modify value
    // it->first = 10;                      // ERROR! Keys are const
}

// Using map<int,string>::iterator
for(map<int,string>::iterator it = m.begin(); it != m.end(); ++it) {
    cout << it->first << " -> " << it->second << "\n";
}

// 4. Const Iterator (read-only)
for(auto it = m.cbegin(); it != m.cend(); it++) {
    cout << it->first << " -> " << it->second << "\n";
    // it->second = "new";                  // ERROR! Cannot modify
}

// 5. Reverse Iterator (descending order)
for(auto it = m.rbegin(); it != m.rend(); it++) {
    cout << it->first << " -> " << it->second << "\n";
}

// Modify in reverse
for(auto it = m.rbegin(); it != m.rend(); it++) {
    it->second += " reversed";
}

// 6. Iterate only keys
for(auto& [key, _] : m) {
    cout << "Key: " << key << "\n";
    // Underscore convention for unused variable
}

// Alternative
for(auto it = m.begin(); it != m.end(); it++) {
    int key = it->first;
    cout << "Key: " << key << "\n";
}

// 7. Iterate only values
for(auto& [_, value] : m) {
    cout << "Value: " << value << "\n";
}

// 8. Iterate with condition
for(auto& [key, value] : m) {
    if(key % 2 == 0) {
        cout << key << " is even: " << value << "\n";
    }
}

// 9. Iterate and erase (correct pattern)
for(auto it = m.begin(); it != m.end(); ) {
    if(it->second == "remove") {
        it = m.erase(it);                   // erase returns next iterator
    } else {
        it++;
    }
}

// 10. Iterate range [low, high]
auto start = m.lower_bound(2);              // First key >= 2
auto end = m.upper_bound(4);                // First key > 4

for(auto it = start; it != end; it++) {
    cout << it->first << " -> " << it->second << "\n";
}

// 11. Iterate with std::for_each
for_each(m.begin(), m.end(), [](auto& pair) {
    cout << pair.first << " -> " << pair.second << "\n";
});

// 12. Parallel iteration with index
int index = 0;
for(auto& [key, value] : m) {
    cout << "Entry " << index << ": " << key << " -> " << value << "\n";
    index++;
}

// 13. Find and iterate from specific key
auto it = m.find(2);
if(it != m.end()) {
    cout << "Starting from key 2:\n";
    while(it != m.end()) {
        cout << it->first << " -> " << it->second << "\n";
        it++;
    }
}

// 14. Iterate first N entries
int count = 0;
for(auto& [key, value] : m) {
    if(count++ >= 3) break;
    cout << key << " -> " << value << "\n";
}

// 15. Iterate and collect keys/values
vector<int> keys;
vector<string> values;

for(auto& [key, value] : m) {
    keys.push_back(key);
    values.push_back(value);
}

// 16. Iterate with prev/next
for(auto it = m.begin(); it != m.end(); it++) {
    if(it != m.begin()) {
        auto prev = std::prev(it);
        cout << "Prev key: " << prev->first << ", Curr key: " << it->first << "\n";
    }
    
    auto next = std::next(it);
    if(next != m.end()) {
        cout << "Curr key: " << it->first << ", Next key: " << next->first << "\n";
    }
}

// 17. Check if last element during iteration
for(auto it = m.begin(); it != m.end(); it++) {
    cout << it->first;
    if(next(it) != m.end()) {
        cout << ", ";                       // Add comma if not last
    }
}

// 18. Iterate using equal_range
auto range = m.equal_range(3);              // [lower_bound(3), upper_bound(3))
for(auto it = range.first; it != range.second; it++) {
    cout << it->first << " -> " << it->second << "\n";
}
```

### Iterator Types for Map
```cpp
// Forward Iterator
map<int, string>::iterator it = m.begin();
auto it = m.begin();

// Const Iterator (read-only)
map<int, string>::const_iterator it = m.cbegin();
auto it = m.cbegin();

// Reverse Iterator (descending order by key)
map<int, string>::reverse_iterator it = m.rbegin();
auto it = m.rbegin();

// Const Reverse Iterator
map<int, string>::const_reverse_iterator it = m.crbegin();
auto it = m.crbegin();
```

### Safe Iterator Operations
```cpp
// Check if iterator is valid
auto it = m.find(5);
if(it != m.end()) {
    // Safe to use it->first and it->second
}

// Advance iterator safely
auto it = m.begin();
if(distance(it, m.end()) >= 3) {
    advance(it, 3);                         // Move 3 positions
}

// Get nth element safely
auto getNth(map<int, string>& m, int n) {
    auto it = m.begin();
    advance(it, min(n, (int)m.size()));
    return it;
}
```

### Ordered Operations
```cpp
// First and Last
m.begin()->first;                          // Smallest key
m.rbegin()->first;                         // Largest key

// Lower/Upper bound
auto it = m.lower_bound(key);              // First key >= key
auto it = m.upper_bound(key);              // First key > key

// Range queries
auto left = m.lower_bound(L);
auto right = m.upper_bound(R);
for(auto it = left; it != right; it++) {
    // Process [L, R]
}

// Equal range
auto [first, last] = m.equal_range(key);
```

---

## 🗂️ UNORDERED_MAP (Hash Map)

### Declaration - O(1) Average Operations
```cpp
unordered_map<int, int> um;
unordered_map<string, int> um;
```

### Operations - O(1) Average
```cpp
// Same as map but unordered
um[key] = value;
um.insert({key, value});
um.erase(key);
um.find(key);
um.count(key);
um.size();
um.empty();

// NOTE: No lower_bound/upper_bound!
// NOTE: No ordered iteration!
```

### Custom Hash Function
```cpp
// For custom types (e.g., pair)
struct PairHash {
    size_t operator()(const pair<int, int>& p) const {
        auto h1 = hash<int>{}(p.first);
        auto h2 = hash<int>{}(p.second);
        return h1 ^ (h2 << 1);
    }
};

unordered_map<pair<int, int>, int, PairHash> um;

// Alternative: Use map for pairs (slower but works)
map<pair<int, int>, int> m;
```

### When to Use Map vs Unordered_Map
```cpp
// Use MAP when:
// - Need ordered keys
// - Need lower_bound/upper_bound
// - Custom comparator
// - Stable performance (O(log n) guaranteed)

// Use UNORDERED_MAP when:
// - Don't need ordering
// - Want faster average performance O(1)
// - Keys are standard types (int, string, etc.)
```

---

## 📦 SET (Ordered Set - Red-Black Tree)

### Declaration
```cpp
set<int> s;                                // Empty set
set<int> s = {1, 2, 3, 4, 5};
set<int, greater<int>> s;                  // Descending order
```

### Operations - O(log n)
```cpp
// Insert
s.insert(x);                               // Insert element
s.emplace(x);                              // Construct in place
s.insert({1, 2, 3, 4});                   // Insert multiple

// Remove
s.erase(x);                                // Erase by value
s.erase(it);                               // Erase by iterator
s.clear();                                 // Remove all

// Search
s.find(x);                                 // Returns iterator
s.count(x);                                // Returns 0 or 1
s.contains(x);                             // C++20 - returns bool

// Size
s.size();
s.empty();
```

### Ordered Operations
```cpp
// First and Last
*s.begin();                                // Smallest element
*s.rbegin();                               // Largest element

// Lower/Upper bound
auto it = s.lower_bound(x);                // First element >= x
auto it = s.upper_bound(x);                // First element > x

// Range iteration
for(auto it = s.lower_bound(L); it != s.upper_bound(R); it++) {
    // Elements in [L, R]
}
```

### Iteration (Sorted Order)
```cpp
for(int x : s) {}                          // Ascending
for(auto it = s.rbegin(); it != s.rend(); it++) {} // Descending
```

---

## 📦 MULTISET (Ordered Multiset - Allows Duplicates)

### Declaration
```cpp
multiset<int> ms;
```

### Operations - O(log n)
```cpp
// Insert (allows duplicates)
ms.insert(x);                              // Can insert same value multiple times

// Count
ms.count(x);                               // Number of occurrences

// Remove
ms.erase(x);                               // Erases ALL occurrences
ms.erase(ms.find(x));                      // Erase single occurrence

// Access
*ms.begin();                               // Smallest
*ms.rbegin();                              // Largest

// Lower/Upper bound work same as set
auto it = ms.lower_bound(x);
auto it = ms.upper_bound(x);
```

### Common Use Cases
```cpp
// Sliding window maximum/minimum
multiset<int> window;
for(int i = 0; i < n; i++) {
    window.insert(arr[i]);
    if(i >= k) window.erase(window.find(arr[i-k]));
    if(i >= k-1) {
        int minVal = *window.begin();
        int maxVal = *window.rbegin();
    }
}
```

---

## 🔢 UNORDERED_SET (Hash Set)

### Declaration - O(1) Average Operations
```cpp
unordered_set<int> us;
unordered_set<string> us;
```

### Operations - O(1) Average
```cpp
// Same as set but unordered
us.insert(x);
us.erase(x);
us.find(x);
us.count(x);
us.size();
us.empty();

// NOTE: No lower_bound/upper_bound!
// NOTE: No ordered iteration!
```

---

## 📚 STACK (LIFO)

### Declaration
```cpp
stack<int> st;
```

### Operations - All O(1)
```cpp
st.push(x);                                // Add to top
st.pop();                                  // Remove top (returns void!)
st.top();                                  // Access top
st.size();
st.empty();
```

### Common Patterns
```cpp
// Process all elements
while(!st.empty()) {
    int x = st.top();
    st.pop();
    // Process x
}

// Monotonic stack (next greater element)
vector<int> nextGreater(vector<int>& arr) {
    int n = arr.size();
    vector<int> result(n, -1);
    stack<int> st; // Stores indices
    
    for(int i = n-1; i >= 0; i--) {
        while(!st.empty() && arr[st.top()] <= arr[i]) {
            st.pop();
        }
        if(!st.empty()) result[i] = arr[st.top()];
        st.push(i);
    }
    return result;
}
```

---

## 📋 QUEUE (FIFO)

### Declaration
```cpp
queue<int> q;
```

### Operations - All O(1)
```cpp
q.push(x);                                 // Add to back
q.pop();                                   // Remove from front (returns void!)
q.front();                                 // Access front
q.back();                                  // Access back
q.size();
q.empty();
```

### Common Usage
```cpp
// BFS traversal
queue<int> q;
q.push(start);
visited[start] = true;

while(!q.empty()) {
    int u = q.front();
    q.pop();
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            visited[v] = true;
            q.push(v);
        }
    }
}
```

---

## 🔄 DEQUE (Double-Ended Queue)

### Declaration
```cpp
deque<int> dq;
```

### Operations - All O(1)
```cpp
dq.push_back(x);                           // Add to back
dq.push_front(x);                          // Add to front
dq.pop_back();                             // Remove from back
dq.pop_front();                            // Remove from front
dq.front();                                // Access front
dq.back();                                 // Access back
dq[i];                                     // Random access O(1)
dq.size();
dq.empty();
```

### When to Use
```cpp
// Use deque when you need:
// - Both stack and queue operations
// - Random access
// - Fast insertion/deletion at both ends

// Sliding window problems
deque<int> dq; // Store indices
for(int i = 0; i < n; i++) {
    // Remove elements outside window
    while(!dq.empty() && dq.front() <= i - k) {
        dq.pop_front();
    }
    
    // Maintain monotonic deque
    while(!dq.empty() && arr[dq.back()] < arr[i]) {
        dq.pop_back();
    }
    
    dq.push_back(i);
    
    if(i >= k-1) {
        int maxInWindow = arr[dq.front()];
    }
}
```

---

## 🏔️ PRIORITY_QUEUE (Heap)

### Declaration
```cpp
priority_queue<int> pq;                     // Max heap (largest on top)
priority_queue<int, vector<int>, greater<int>> minPq; // Min heap

// Custom comparator
auto cmp = [](int a, int b) { return a > b; };
priority_queue<int, vector<int>, decltype(cmp)> pq(cmp);

// For pairs (sorts by first, then second)
priority_queue<pii> pq;                     // Max heap
priority_queue<pii, vector<pii>, greater<pii>> minPq; // Min heap
```

### Operations
```cpp
pq.push(x);                                // O(log n)
pq.pop();                                  // O(log n) - removes top
pq.top();                                  // O(1) - access top
pq.size();                                 // O(1)
pq.empty();                                // O(1)
```

### Custom Comparator Examples
```cpp
// Min heap for pairs (sort by second element)
auto cmp = [](pii a, pii b) { return a.second > b.second; };
priority_queue<pii, vector<pii>, decltype(cmp)> pq(cmp);

// For custom struct
struct Node {
    int val, cost;
    bool operator<(const Node& other) const {
        return cost > other.cost; // Min heap by cost
    }
};
priority_queue<Node> pq;
```

### Common Use Cases
```cpp
// Kth largest element
priority_queue<int, vector<int>, greater<int>> minPq;
for(int x : arr) {
    minPq.push(x);
    if(minPq.size() > k) minPq.pop();
}
int kthLargest = minPq.top();

// Dijkstra's algorithm
priority_queue<pii, vector<pii>, greater<pii>> pq; // {dist, node}
```

---

## 👫 PAIR & TUPLE

### Pair
```cpp
// Declaration
pair<int, int> p;
pair<int, string> p = {1, "text"};
pair<int, int> p = make_pair(1, 2);
auto p = make_pair(1, 2);                  // Type inference

// Access
p.first;                                   // First element
p.second;                                  // Second element

// Comparison (lexicographic: first, then second)
pair<int, int> p1 = {1, 2};
pair<int, int> p2 = {1, 3};
p1 < p2;                                   // true
p1 == p2;                                  // false

// Swap
p1.swap(p2);

// Sorting pairs
vector<pii> vp = {{3, 1}, {1, 2}, {1, 1}};
sort(all(vp));                             // Sorts by first, then second
```

### Tuple (C++11)
```cpp
// Declaration
tuple<int, string, double> t;
tuple<int, string, double> t = make_tuple(1, "text", 3.14);
auto t = make_tuple(1, "text", 3.14);

// Access
get<0>(t);                                 // First element
get<1>(t);                                 // Second element
get<2>(t);                                 // Third element

// Structured binding (C++17)
auto [x, y, z] = t;

// Comparison (lexicographic)
tuple<int, int, int> t1 = {1, 2, 3};
tuple<int, int, int> t2 = {1, 2, 4};
t1 < t2;                                   // true

// Tie (for easy unpacking)
int a, b, c;
tie(a, b, c) = make_tuple(1, 2, 3);

// Ignore elements
tie(a, ignore, c) = make_tuple(1, 2, 3);   // b is ignored
```

---

## 🧮 BITSET

### Declaration
```cpp
bitset<32> bs;                             // 32 bits, all 0
bitset<32> bs(10);                         // From integer
bitset<32> bs("1010");                     // From binary string
```

### Operations
```cpp
bs.set();                                  // Set all to 1
bs.set(i);                                 // Set bit i to 1
bs.reset();                                // Set all to 0
bs.reset(i);                               // Set bit i to 0
bs.flip();                                 // Flip all bits
bs.flip(i);                                // Flip bit i
bs[i];                                     // Access bit i
bs.test(i);                                // Test if bit i is 1
bs.count();                                // Count number of 1s
bs.size();                                 // Number of bits
bs.any();                                  // Any bit is 1?
bs.none();                                 // All bits are 0?
bs.all();                                  // All bits are 1?

// Conversions
bs.to_string();                            // To binary string
bs.to_ulong();                             // To unsigned long
bs.to_ullong();                            // To unsigned long long

// Bitwise operations
bs1 & bs2;                                 // AND
bs1 | bs2;                                 // OR
bs1 ^ bs2;                                 // XOR
~bs1;                                      // NOT
bs1 << n;                                  // Left shift
bs1 >> n;                                  // Right shift
```

---

## 🎯 ALGORITHMS

### Sorting
```cpp
// Basic sorting
sort(arr, arr + n);                        // Array
sort(v.begin(), v.end());                  // Vector
sort(all(v));                              // Using macro

// Descending
sort(all(v), greater<int>());

// Custom comparator (lambda)
sort(all(v), [](int a, int b) {
    return a > b;                          // Descending
});

// Sort by absolute value
sort(all(v), [](int a, int b) {
    return abs(a) < abs(b);
});

// Sort pairs by second element
sort(all(vp), [](pii a, pii b) {
    return a.second < b.second;
});

// Sort 2D array/vector
vector<vector<int>> intervals;
sort(all(intervals), [](vector<int>& a, vector<int>& b) {
    if(a[0] != b[0]) return a[0] < b[0];
    return a[1] < b[1];
});

// Stable sort (maintains relative order)
stable_sort(all(v));

// Partial sort (first k elements)
partial_sort(v.begin(), v.begin() + k, v.end());

// nth_element (kth element in correct position)
nth_element(v.begin(), v.begin() + k, v.end());

// Is sorted check
bool sorted = is_sorted(all(v));
```

### Binary Search
```cpp
// Basic binary search
int binarySearch(vector<int>& arr, int target) {
    int left = 0, right = arr.size() - 1;
    while(left <= right) {
        int mid = left + (right - left) / 2;  // Avoid overflow
        if(arr[mid] == target) return mid;
        if(arr[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

// STL binary search
bool found = binary_search(all(v), x);     // Returns bool

// Lower bound (first >= x)
auto it = lower_bound(all(v), x);
if(it != v.end()) {
    int idx = it - v.begin();
    int value = *it;
}

// Upper bound (first > x)
auto it = upper_bound(all(v), x);

// Count occurrences in sorted array
int count = upper_bound(all(v), x) - lower_bound(all(v), x);

// Binary search on answer (finding minimum)
int binarySearchAnswer(int low, int high) {
    int ans = -1;
    while(low <= high) {
        int mid = low + (high - low) / 2;
        if(check(mid)) {
            ans = mid;
            high = mid - 1;            // Search left for minimum
        } else {
            low = mid + 1;
        }
    }
    return ans;
}

// Binary search on answer (finding maximum)
int binarySearchMaximum(int low, int high) {
    int ans = -1;
    while(low <= high) {
        int mid = low + (high - low) / 2;
        if(check(mid)) {
            ans = mid;
            low = mid + 1;             // Search right for maximum
        } else {
            high = mid - 1;
        }
    }
    return ans;
}

// Binary search on real numbers
double binarySearchReal(double low, double high) {
    for(int iter = 0; iter < 100; iter++) {  // Or while(high - low > EPS)
        double mid = (low + high) / 2.0;
        if(check(mid)) {
            high = mid;
        } else {
            low = mid;
        }
    }
    return low;
}
```

### Two Pointers
```cpp
// Find pair with sum in sorted array
pair<int, int> findPairWithSum(vector<int>& arr, int target) {
    int left = 0, right = arr.size() - 1;
    while(left < right) {
        int sum = arr[left] + arr[right];
        if(sum == target) return {left, right};
        if(sum < target) left++;
        else right--;
    }
    return {-1, -1};
}

// Remove duplicates in sorted array
int removeDuplicates(vector<int>& arr) {
    if(arr.empty()) return 0;
    int j = 0;
    for(int i = 1; i < arr.size(); i++) {
        if(arr[i] != arr[j]) {
            arr[++j] = arr[i];
        }
    }
    return j + 1;  // New length
}

// Container with most water
int maxArea(vector<int>& height) {
    int left = 0, right = height.size() - 1;
    int maxArea = 0;
    while(left < right) {
        int area = min(height[left], height[right]) * (right - left);
        maxArea = max(maxArea, area);
        if(height[left] < height[right]) left++;
        else right--;
    }
    return maxArea;
}
```

### Sliding Window
```cpp
// Fixed size window - Maximum sum of k elements
int maxSumKElements(vector<int>& arr, int k) {
    int sum = 0;
    for(int i = 0; i < k; i++) sum += arr[i];
    int maxSum = sum;
    
    for(int i = k; i < arr.size(); i++) {
        sum += arr[i] - arr[i-k];
        maxSum = max(maxSum, sum);
    }
    return maxSum;
}

// Variable size window - Longest substring with at most k distinct
int longestSubstringKDistinct(string s, int k) {
    unordered_map<char, int> freq;
    int left = 0, maxLen = 0;
    
    for(int right = 0; right < s.length(); right++) {
        freq[s[right]]++;
        
        while(freq.size() > k) {
            freq[s[left]]--;
            if(freq[s[left]] == 0) freq.erase(s[left]);
            left++;
        }
        
        maxLen = max(maxLen, right - left + 1);
    }
    return maxLen;
}

// Minimum window substring
string minWindow(string s, string t) {
    unordered_map<char, int> need, window;
    for(char c : t) need[c]++;
    
    int left = 0, right = 0;
    int valid = 0;  // Count of matched characters
    int start = 0, len = INT_MAX;
    
    while(right < s.length()) {
        char c = s[right++];
        if(need.count(c)) {
            window[c]++;
            if(window[c] == need[c]) valid++;
        }
        
        while(valid == need.size()) {
            if(right - left < len) {
                start = left;
                len = right - left;
            }
            
            char d = s[left++];
            if(need.count(d)) {
                if(window[d] == need[d]) valid--;
                window[d]--;
            }
        }
    }
    
    return len == INT_MAX ? "" : s.substr(start, len);
}
```

### Prefix Sum
```cpp
// 1D prefix sum
vector<int> buildPrefixSum(vector<int>& arr) {
    int n = arr.size();
    vector<int> prefix(n + 1, 0);
    for(int i = 0; i < n; i++) {
        prefix[i + 1] = prefix[i] + arr[i];
    }
    return prefix;
}

// Query sum [l, r]
int rangeSum(vector<int>& prefix, int l, int r) {
    return prefix[r + 1] - prefix[l];
}

// 2D prefix sum
vector<vector<int>> build2DPrefix(vector<vector<int>>& matrix) {
    int n = matrix.size(), m = matrix[0].size();
    vector<vector<int>> prefix(n + 1, vector<int>(m + 1, 0));
    
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
int query2DSum(vector<vector<int>>& prefix, int r1, int c1, int r2, int c2) {
    return prefix[r2+1][c2+1] 
         - prefix[r1][c2+1] 
         - prefix[r2+1][c1] 
         + prefix[r1][c1];
}
```

### Difference Array
```cpp
// Range update in O(1), query in O(1) after build
class DifferenceArray {
    vector<int> diff;
public:
    DifferenceArray(vector<int>& arr) {
        int n = arr.size();
        diff.resize(n + 1, 0);
        diff[0] = arr[0];
        for(int i = 1; i < n; i++) {
            diff[i] = arr[i] - arr[i-1];
        }
    }
    
    void rangeUpdate(int l, int r, int val) {
        diff[l] += val;
        diff[r+1] -= val;
    }
    
    vector<int> getArray() {
        vector<int> result(diff.size() - 1);
        result[0] = diff[0];
        for(int i = 1; i < result.size(); i++) {
            result[i] = result[i-1] + diff[i];
        }
        return result;
    }
};
```

---

## 📈 GRAPH ALGORITHMS

### Graph Representation
```cpp
// Adjacency List (unweighted)
int n, m;  // n = nodes, m = edges
vector<vector<int>> adj(n);

// Add edge
adj[u].push_back(v);                       // Directed
adj[u].push_back(v);                       // Undirected
adj[v].push_back(u);

// Weighted graph
vector<vector<pii>> adj(n);                // {neighbor, weight}
adj[u].push_back({v, weight});

// Edge List
vector<tuple<int, int, int>> edges;        // {u, v, weight}
edges.push_back({u, v, weight});
```

### BFS (Breadth-First Search)
```cpp
// Single source shortest path (unweighted)
vector<int> bfs(int start, vector<vector<int>>& adj) {
    int n = adj.size();
    vector<int> dist(n, -1);
    queue<int> q;
    
    q.push(start);
    dist[start] = 0;
    
    while(!q.empty()) {
        int u = q.front();
        q.pop();
        
        for(int v : adj[u]) {
            if(dist[v] == -1) {
                dist[v] = dist[u] + 1;
                q.push(v);
            }
        }
    }
    return dist;
}

// BFS with parent tracking (for path reconstruction)
vector<int> bfsWithParent(int start, int end, vector<vector<int>>& adj) {
    int n = adj.size();
    vector<int> parent(n, -1);
    vector<bool> visited(n, false);
    queue<int> q;
    
    q.push(start);
    visited[start] = true;
    
    while(!q.empty()) {
        int u = q.front();
        q.pop();
        
        if(u == end) break;
        
        for(int v : adj[u]) {
            if(!visited[v]) {
                visited[v] = true;
                parent[v] = u;
                q.push(v);
            }
        }
    }
    
    // Reconstruct path
    vector<int> path;
    for(int v = end; v != -1; v = parent[v]) {
        path.push_back(v);
    }
    reverse(all(path));
    return path;
}

// 0-1 BFS (edges with weight 0 or 1)
vector<int> bfs01(int start, vector<vector<pii>>& adj) {
    int n = adj.size();
    vector<int> dist(n, INF);
    deque<int> dq;
    
    dist[start] = 0;
    dq.push_front(start);
    
    while(!dq.empty()) {
        int u = dq.front();
        dq.pop_front();
        
        for(auto [v, w] : adj[u]) {
            if(dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                if(w == 0) dq.push_front(v);
                else dq.push_back(v);
            }
        }
    }
    return dist;
}
```

### BFS on Grid
```cpp
// 4-directional movement
int dx[] = {-1, 1, 0, 0};
int dy[] = {0, 0, -1, 1};

void bfsGrid(int sr, int sc, vector<vector<int>>& grid) {
    int n = grid.size(), m = grid[0].size();
    vector<vector<bool>> visited(n, vector<bool>(m, false));
    queue<pii> q;
    
    q.push({sr, sc});
    visited[sr][sc] = true;
    
    while(!q.empty()) {
        auto [x, y] = q.front();
        q.pop();
        
        for(int i = 0; i < 4; i++) {
            int nx = x + dx[i];
            int ny = y + dy[i];
            
            if(nx >= 0 && nx < n && ny >= 0 && ny < m 
               && !visited[nx][ny] && grid[nx][ny] != -1) {
                visited[nx][ny] = true;
                q.push({nx, ny});
            }
        }
    }
}

// 8-directional movement
int dx[] = {-1, -1, -1, 0, 0, 1, 1, 1};
int dy[] = {-1, 0, 1, -1, 1, -1, 0, 1};
```

### DFS (Depth-First Search)
```cpp
// Basic DFS
void dfs(int u, vector<vector<int>>& adj, vector<bool>& visited) {
    visited[u] = true;
    
    // Process node u
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            dfs(v, adj, visited);
        }
    }
}

// DFS with entry/exit time
int timer = 0;
void dfs(int u, vector<vector<int>>& adj, vector<bool>& visited,
         vector<int>& entry, vector<int>& exit) {
    visited[u] = true;
    entry[u] = timer++;
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            dfs(v, adj, visited, entry, exit);
        }
    }
    
    exit[u] = timer++;
}

// DFS with parent (for tree)
void dfs(int u, int parent, vector<vector<int>>& adj) {
    for(int v : adj[u]) {
        if(v != parent) {
            dfs(v, u, adj);
        }
    }
}

// DFS for cycle detection (undirected graph)
bool hasCycleDFS(int u, int parent, vector<vector<int>>& adj, vector<bool>& visited) {
    visited[u] = true;
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            if(hasCycleDFS(v, u, adj, visited)) return true;
        } else if(v != parent) {
            return true;  // Back edge found
        }
    }
    return false;
}

// DFS for cycle detection (directed graph)
bool hasCycleDFS(int u, vector<vector<int>>& adj, 
                 vector<bool>& visited, vector<bool>& recStack) {
    visited[u] = true;
    recStack[u] = true;
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            if(hasCycleDFS(v, adj, visited, recStack)) return true;
        } else if(recStack[v]) {
            return true;  // Back edge to node in recursion stack
        }
    }
    
    recStack[u] = false;
    return false;
}
```

### Dijkstra's Algorithm (Shortest Path)
```cpp
vector<int> dijkstra(int start, vector<vector<pii>>& adj) {
    int n = adj.size();
    vector<int> dist(n, INF);
    priority_queue<pii, vector<pii>, greater<pii>> pq;  // {dist, node}
    
    dist[start] = 0;
    pq.push({0, start});
    
    while(!pq.empty()) {
        auto [d, u] = pq.top();
        pq.pop();
        
        if(d > dist[u]) continue;  // Already processed
        
        for(auto [v, w] : adj[u]) {
            if(dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                pq.push({dist[v], v});
            }
        }
    }
    return dist;
}

// Dijkstra with path reconstruction
pair<vector<int>, vector<int>> dijkstraWithPath(int start, int end, 
                                                  vector<vector<pii>>& adj) {
    int n = adj.size();
    vector<int> dist(n, INF);
    vector<int> parent(n, -1);
    priority_queue<pii, vector<pii>, greater<pii>> pq;
    
    dist[start] = 0;
    pq.push({0, start});
    
    while(!pq.empty()) {
        auto [d, u] = pq.top();
        pq.pop();
        
        if(d > dist[u]) continue;
        
        for(auto [v, w] : adj[u]) {
            if(dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                parent[v] = u;
                pq.push({dist[v], v});
            }
        }
    }
    
    // Reconstruct path
    vector<int> path;
    for(int v = end; v != -1; v = parent[v]) {
        path.push_back(v);
    }
    reverse(all(path));
    
    return {dist, path};
}
```

### Bellman-Ford (Shortest Path with Negative Weights)
```cpp
vector<int> bellmanFord(int start, int n, vector<tuple<int,int,int>>& edges) {
    vector<int> dist(n, INF);
    dist[start] = 0;
    
    // Relax all edges n-1 times
    for(int i = 0; i < n - 1; i++) {
        for(auto [u, v, w] : edges) {
            if(dist[u] != INF && dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
            }
        }
    }
    
    // Check for negative cycle
    for(auto [u, v, w] : edges) {
        if(dist[u] != INF && dist[u] + w < dist[v]) {
            // Negative cycle exists
            return {};
        }
    }
    
    return dist;
}
```

### Floyd-Warshall (All Pairs Shortest Path)
```cpp
vector<vector<int>> floydWarshall(int n, vector<vector<int>>& graph) {
    vector<vector<int>> dist = graph;
    
    // Initialize diagonal to 0
    for(int i = 0; i < n; i++) {
        dist[i][i] = 0;
    }
    
    for(int k = 0; k < n; k++) {
        for(int i = 0; i < n; i++) {
            for(int j = 0; j < n; j++) {
                if(dist[i][k] != INF && dist[k][j] != INF) {
                    dist[i][j] = min(dist[i][j], dist[i][k] + dist[k][j]);
                }
            }
        }
    }
    
    return dist;
}
```

### Union-Find (Disjoint Set Union)
```cpp
class UnionFind {
public:
    vector<int> parent, rank, size;
    int components;
    
    UnionFind(int n) {
        parent.resize(n);
        rank.resize(n, 0);
        size.resize(n, 1);
        components = n;
        for(int i = 0; i < n; i++) {
            parent[i] = i;
        }
    }
    
    int find(int x) {
        if(parent[x] != x) {
            parent[x] = find(parent[x]);  // Path compression
        }
        return parent[x];
    }
    
    bool unite(int x, int y) {
        int px = find(x), py = find(y);
        if(px == py) return false;
        
        // Union by rank
        if(rank[px] < rank[py]) swap(px, py);
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
};
```

### Topological Sort (DFS-based)
```cpp
void topologicalSortUtil(int u, vector<vector<int>>& adj, 
                         vector<bool>& visited, stack<int>& st) {
    visited[u] = true;
    
    for(int v : adj[u]) {
        if(!visited[v]) {
            topologicalSortUtil(v, adj, visited, st);
        }
    }
    
    st.push(u);
}

vector<int> topologicalSort(vector<vector<int>>& adj) {
    int n = adj.size();
    vector<bool> visited(n, false);
    stack<int> st;
    
    for(int i = 0; i < n; i++) {
        if(!visited[i]) {
            topologicalSortUtil(i, adj, visited, st);
        }
    }
    
    vector<int> result;
    while(!st.empty()) {
        result.push_back(st.top());
        st.pop();
    }
    return result;
}
```

### Topological Sort (Kahn's Algorithm - BFS)
```cpp
vector<int> topologicalSortKahn(vector<vector<int>>& adj) {
    int n = adj.size();
    vector<int> indegree(n, 0);
    
    // Calculate indegree
    for(int u = 0; u < n; u++) {
        for(int v : adj[u]) {
            indegree[v]++;
        }
    }
    
    // Queue all nodes with indegree 0
    queue<int> q;
    for(int i = 0; i < n; i++) {
        if(indegree[i] == 0) {
            q.push(i);
        }
    }
    
    vector<int> result;
    while(!q.empty()) {
        int u = q.front();
        q.pop();
        result.push_back(u);
        
        for(int v : adj[u]) {
            if(--indegree[v] == 0) {
                q.push(v);
            }
        }
    }
    
    // Check for cycle
    return result.size() == n ? result : vector<int>();
}
```

### Kruskal's Algorithm (MST)
```cpp
int kruskal(int n, vector<tuple<int, int, int>>& edges) {
    // Sort edges by weight
    sort(all(edges), [](auto& a, auto& b) {
        return get<2>(a) < get<2>(b);
    });
    
    UnionFind uf(n);
    int mstCost = 0;
    int edgesUsed = 0;
    
    for(auto [u, v, w] : edges) {
        if(uf.unite(u, v)) {
            mstCost += w;
            edgesUsed++;
            if(edgesUsed == n - 1) break;
        }
    }
    
    return edgesUsed == n - 1 ? mstCost : -1;  // -1 if no MST
}
```

### Prim's Algorithm (MST)
```cpp
int prim(int n, vector<vector<pii>>& adj) {
    vector<bool> inMST(n, false);
    priority_queue<pii, vector<pii>, greater<pii>> pq;  // {weight, node}
    
    int mstCost = 0;
    pq.push({0, 0});
    
    while(!pq.empty()) {
        auto [w, u] = pq.top();
        pq.pop();
        
        if(inMST[u]) continue;
        
        inMST[u] = true;
        mstCost += w;
        
        for(auto [v, weight] : adj[u]) {
            if(!inMST[v]) {
                pq.push({weight, v});
            }
        }
    }
    
    return mstCost;
}
```

---

## 🎯 BIT MANIPULATION

### Basic Operations
```cpp
// Check if ith bit is set (0-indexed from right)
bool isSet = (n & (1 << i)) != 0;
bool isSet = (n >> i) & 1;

// Set ith bit
n |= (1 << i);

// Clear ith bit
n &= ~(1 << i);

// Toggle ith bit
n ^= (1 << i);

// Get rightmost set bit
int rightmost = n & (-n);
int rightmost = n & (~n + 1);

// Clear rightmost set bit
n &= (n - 1);

// Clear all bits from MSB to ith bit (inclusive)
int mask = (1 << i) - 1;
n &= mask;

// Clear all bits from ith bit to LSB (inclusive)
int mask = ~((1 << (i + 1)) - 1);
n &= mask;

// Update ith bit to value
n = (n & ~(1 << i)) | (value << i);
```

### Built-in Functions
```cpp
// Count set bits (popcount)
int count = __builtin_popcount(n);         // For int
int count = __builtin_popcountll(n);       // For long long

// Count trailing zeros (ctz)
int zeros = __builtin_ctz(n);              // Undefined for n=0!
int zeros = __builtin_ctzll(n);            // For long long

// Count leading zeros (clz)
int zeros = __builtin_clz(n);              // Undefined for n=0!
int zeros = __builtin_clzll(n);            // For long long

// Find first set bit (ffs) - returns position + 1
int pos = __builtin_ffs(n);                // Returns 0 if n=0
int pos = __builtin_ffsll(n);              // For long long

// Parity (1 if odd number of set bits)
int parity = __builtin_parity(n);
int parity = __builtin_parityll(n);
```

### Common Tricks
```cpp
// Check if power of 2
bool isPow2 = (n > 0) && ((n & (n - 1)) == 0);

// Get next power of 2
int nextPow2(int n) {
    n--;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    return n + 1;
}

// Get position of rightmost set bit (0-indexed)
int pos = __builtin_ctz(n);

// Get position of leftmost set bit (0-indexed)
int pos = 31 - __builtin_clz(n);           // For 32-bit int
int pos = 63 - __builtin_clzll(n);         // For 64-bit long long

// Isolate rightmost set bit
int isolated = n & (-n);

// Turn off rightmost set bit
n = n & (n - 1);

// Check if n has opposite signs
bool oppositeSigns = ((a ^ b) < 0);

// Swap two numbers without temp
a ^= b;
b ^= a;
a ^= b;

// Absolute value
int abs = (n ^ (n >> 31)) - (n >> 31);

// Min/Max without branching
int min = b ^ ((a ^ b) & -(a < b));
int max = a ^ ((a ^ b) & -(a < b));

// Modulo by power of 2 (n % (2^k))
int mod = n & ((1 << k) - 1);

// XOR of range [0, n]
int xorRange(int n) {
    int mod = n % 4;
    if(mod == 0) return n;
    if(mod == 1) return 1;
    if(mod == 2) return n + 1;
    return 0;
}

// XOR of range [l, r]
int xorRange(int l, int r) {
    return xorRange(r) ^ xorRange(l - 1);
}
```

### Subset Generation
```cpp
// Generate all subsets
void generateSubsets(vector<int>& nums) {
    int n = nums.size();
    for(int mask = 0; mask < (1 << n); mask++) {
        vector<int> subset;
        for(int i = 0; i < n; i++) {
            if(mask & (1 << i)) {
                subset.push_back(nums[i]);
            }
        }
        // Process subset
    }
}

// Iterate through all subsets of a set
for(int subset = mask; subset; subset = (subset - 1) & mask) {
    // Process subset
}
```

### Gray Code
```cpp
// Binary to Gray code
int binaryToGray(int n) {
    return n ^ (n >> 1);
}

// Gray to Binary code
int grayToBinary(int gray) {
    int binary = 0;
    while(gray) {
        binary ^= gray;
        gray >>= 1;
    }
    return binary;
}
```

---

## 🧮 MATH & NUMBER THEORY

### GCD & LCM
```cpp
// GCD (built-in C++17)
int g = __gcd(a, b);

// Manual GCD (Euclidean algorithm)
int gcd(int a, int b) {
    return b == 0 ? a : gcd(b, a % b);
}

// GCD for multiple numbers
int gcdMultiple(vector<int>& nums) {
    int result = nums[0];
    for(int i = 1; i < nums.size(); i++) {
        result = __gcd(result, nums[i]);
        if(result == 1) break;
    }
    return result;
}

// LCM
int lcm(int a, int b) {
    return (a / __gcd(a, b)) * b;  // Avoid overflow
}

// LCM for multiple numbers
ll lcmMultiple(vector<int>& nums) {
    ll result = nums[0];
    for(int i = 1; i < nums.size(); i++) {
        result = (result / __gcd(result, (ll)nums[i])) * nums[i];
    }
    return result;
}
```

### Prime Numbers
```cpp
// Check if prime
bool isPrime(int n) {
    if(n <= 1) return false;
    if(n <= 3) return true;
    if(n % 2 == 0 || n % 3 == 0) return false;
    
    for(int i = 5; i * i <= n; i += 6) {
        if(n % i == 0 || n % (i + 2) == 0) {
            return false;
        }
    }
    return true;
}

// Sieve of Eratosthenes
vector<bool> sieve(int n) {
    vector<bool> is_prime(n + 1, true);
    is_prime[0] = is_prime[1] = false;
    
    for(int i = 2; i * i <= n; i++) {
        if(is_prime[i]) {
            for(int j = i * i; j <= n; j += i) {
                is_prime[j] = false;
            }
        }
    }
    return is_prime;
}

// Get all primes up to n
vector<int> getAllPrimes(int n) {
    vector<bool> is_prime = sieve(n);
    vector<int> primes;
    for(int i = 2; i <= n; i++) {
        if(is_prime[i]) primes.push_back(i);
    }
    return primes;
}

// Prime factorization
vector<pii> primeFactorize(int n) {
    vector<pii> factors;  // {prime, count}
    
    for(int i = 2; i * i <= n; i++) {
        int count = 0;
        while(n % i == 0) {
            count++;
            n /= i;
        }
        if(count > 0) factors.push_back({i, count});
    }
    
    if(n > 1) factors.push_back({n, 1});
    return factors;
}

// Count divisors
int countDivisors(int n) {
    int count = 0;
    for(int i = 1; i * i <= n; i++) {
        if(n % i == 0) {
            count += (i * i == n) ? 1 : 2;
        }
    }
    return count;
}

// Sum of divisors
int sumDivisors(int n) {
    int sum = 0;
    for(int i = 1; i * i <= n; i++) {
        if(n % i == 0) {
            sum += i;
            if(i * i != n) sum += n / i;
        }
    }
    return sum;
}
```

### Modular Arithmetic
```cpp
// Modular addition
int addMod(int a, int b, int mod) {
    return ((a % mod) + (b % mod)) % mod;
}

// Modular subtraction
int subMod(int a, int b, int mod) {
    return ((a % mod) - (b % mod) + mod) % mod;
}

// Modular multiplication
ll mulMod(ll a, ll b, ll mod) {
    return ((a % mod) * (b % mod)) % mod;
}

// Modular exponentiation (a^b mod m)
ll powerMod(ll base, ll exp, ll mod) {
    ll result = 1;
    base %= mod;
    
    while(exp > 0) {
        if(exp & 1) {
            result = (result * base) % mod;
        }
        base = (base * base) % mod;
        exp >>= 1;
    }
    return result;
}

// Modular inverse (when mod is prime) - Fermat's Little Theorem
ll modInverse(ll a, ll mod) {
    return powerMod(a, mod - 2, mod);
}

// Modular inverse (extended Euclidean algorithm)
ll modInverseExtended(ll a, ll mod) {
    ll m0 = mod, x0 = 0, x1 = 1;
    
    while(a > 1) {
        ll q = a / mod;
        ll t = mod;
        mod = a % mod;
        a = t;
        t = x0;
        x0 = x1 - q * x0;
        x1 = t;
    }
    
    if(x1 < 0) x1 += m0;
    return x1;
}

// Modular division (a / b mod m)
ll divMod(ll a, ll b, ll mod) {
    return mulMod(a, modInverse(b, mod), mod);
}
```

### Combinatorics
```cpp
// Factorial
ll factorial(int n) {
    ll result = 1;
    for(int i = 2; i <= n; i++) {
        result *= i;
    }
    return result;
}

// Factorial with modulo
ll factorialMod(int n, ll mod) {
    ll result = 1;
    for(int i = 2; i <= n; i++) {
        result = (result * i) % mod;
    }
    return result;
}

// nCr (Combinations)
ll nCr(int n, int r) {
    if(r > n) return 0;
    if(r == 0 || r == n) return 1;
    
    r = min(r, n - r);  // Optimization
    
    ll result = 1;
    for(int i = 0; i < r; i++) {
        result *= (n - i);
        result /= (i + 1);
    }
    return result;
}

// nCr with Pascal's triangle (DP)
vector<vector<ll>> pascalTriangle(int n) {
    vector<vector<ll>> C(n + 1, vector<ll>(n + 1, 0));
    
    for(int i = 0; i <= n; i++) {
        C[i][0] = C[i][i] = 1;
        for(int j = 1; j < i; j++) {
            C[i][j] = C[i-1][j-1] + C[i-1][j];
        }
    }
    return C;
}

// nCr with modulo
ll nCrMod(int n, int r, ll mod) {
    if(r > n) return 0;
    if(r == 0 || r == n) return 1;
    
    // Precompute factorials
    vector<ll> fact(n + 1);
    fact[0] = 1;
    for(int i = 1; i <= n; i++) {
        fact[i] = (fact[i-1] * i) % mod;
    }
    
    ll numerator = fact[n];
    ll denominator = (fact[r] * fact[n - r]) % mod;
    
    return (numerator * modInverse(denominator, mod)) % mod;
}
```

### Other Math Functions
```cpp
// Power
ll power(ll base, ll exp) {
    ll result = 1;
    while(exp > 0) {
        if(exp & 1) result *= base;
        base *= base;
        exp >>= 1;
    }
    return result;
}

// Square root (integer)
int isqrt(int n) {
    if(n == 0) return 0;
    int x = n;
    int y = (x + 1) / 2;
    while(y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// Check if perfect square
bool isPerfectSquare(int n) {
    int sr = isqrt(n);
    return sr * sr == n;
}

// Nth Fibonacci number (matrix exponentiation)
ll fib(int n) {
    if(n <= 1) return n;
    
    vector<vector<ll>> base = {{1, 1}, {1, 0}};
    vector<vector<ll>> result = {{1, 0}, {0, 1}};  // Identity matrix
    
    auto multiply = [](vector<vector<ll>>& a, vector<vector<ll>>& b) {
        vector<vector<ll>> c(2, vector<ll>(2));
        for(int i = 0; i < 2; i++) {
            for(int j = 0; j < 2; j++) {
                for(int k = 0; k < 2; k++) {
                    c[i][j] += a[i][k] * b[k][j];
                }
            }
        }
        return c;
    };
    
    while(n > 0) {
        if(n & 1) result = multiply(result, base);
        base = multiply(base, base);
        n >>= 1;
    }
    
    return result[0][1];
}
```

---

## 📦 DYNAMIC PROGRAMMING PATTERNS

### 1D DP
```cpp
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
int rob(vector<int>& nums) {
    int n = nums.size();
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
```cpp
// Unique paths in grid
int uniquePaths(int m, int n) {
    vector<vector<int>> dp(m, vector<int>(n, 1));
    
    for(int i = 1; i < m; i++) {
        for(int j = 1; j < n; j++) {
            dp[i][j] = dp[i-1][j] + dp[i][j-1];
        }
    }
    return dp[m-1][n-1];
}

// Longest Common Subsequence (LCS)
int longestCommonSubsequence(string s1, string s2) {
    int m = s1.length(), n = s2.length();
    vector<vector<int>> dp(m + 1, vector<int>(n + 1, 0));
    
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

// Edit Distance
int minDistance(string word1, string word2) {
    int m = word1.length(), n = word2.length();
    vector<vector<int>> dp(m + 1, vector<int>(n + 1, 0));
    
    for(int i = 0; i <= m; i++) dp[i][0] = i;
    for(int j = 0; j <= n; j++) dp[0][j] = j;
    
    for(int i = 1; i <= m; i++) {
        for(int j = 1; j <= n; j++) {
            if(word1[i-1] == word2[j-1]) {
                dp[i][j] = dp[i-1][j-1];
            } else {
                dp[i][j] = 1 + min({dp[i-1][j], dp[i][j-1], dp[i-1][j-1]});
            }
        }
    }
    return dp[m][n];
}
```

### Knapsack Patterns
```cpp
// 0/1 Knapsack
int knapsack01(vector<int>& weights, vector<int>& values, int W) {
    int n = weights.size();
    vector<vector<int>> dp(n + 1, vector<int>(W + 1, 0));
    
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

// 0/1 Knapsack (Space Optimized)
int knapsack01Optimized(vector<int>& weights, vector<int>& values, int W) {
    int n = weights.size();
    vector<int> dp(W + 1, 0);
    
    for(int i = 0; i < n; i++) {
        for(int w = W; w >= weights[i]; w--) {
            dp[w] = max(dp[w], dp[w - weights[i]] + values[i]);
        }
    }
    return dp[W];
}

// Unbounded Knapsack
int knapsackUnbounded(vector<int>& weights, vector<int>& values, int W) {
    vector<int> dp(W + 1, 0);
    
    for(int i = 0; i < weights.size(); i++) {
        for(int w = weights[i]; w <= W; w++) {
            dp[w] = max(dp[w], dp[w - weights[i]] + values[i]);
        }
    }
    return dp[W];
}

// Subset Sum
bool subsetSum(vector<int>& nums, int target) {
    vector<bool> dp(target + 1, false);
    dp[0] = true;
    
    for(int num : nums) {
        for(int sum = target; sum >= num; sum--) {
            dp[sum] = dp[sum] || dp[sum - num];
        }
    }
    return dp[target];
}
```

### DP on Trees
```cpp
// Tree diameter
int treeDiameter(int u, int parent, vector<vector<int>>& adj, int& diameter) {
    int max1 = 0, max2 = 0;  // Two largest depths
    
    for(int v : adj[u]) {
        if(v == parent) continue;
        
        int depth = treeDiameter(v, u, adj, diameter);
        
        if(depth > max1) {
            max2 = max1;
            max1 = depth;
        } else if(depth > max2) {
            max2 = depth;
        }
    }
    
    diameter = max(diameter, max1 + max2);
    return max1 + 1;
}
```

---

## ⚠️ COMMON PITFALLS & BEST PRACTICES

### Integer Overflow
```cpp
// ❌ WRONG - Can overflow
int mid = (left + right) / 2;
int result = a * b;
long long sum = a + b;  // If a, b are int

// ✅ CORRECT
int mid = left + (right - left) / 2;
long long result = (ll)a * b;
long long sum = (ll)a + b;

// Always use ll for intermediate calculations
ll result = ((ll)a * b) % MOD;
```

### Array Bounds & Unsigned Integers
```cpp
// ❌ WRONG - size() returns size_t (unsigned)
for(int i = v.size() - 1; i >= 0; i--) {}  // Infinite loop if v.size() == 0

// ✅ CORRECT
for(int i = (int)v.size() - 1; i >= 0; i--) {}
for(int i = sz(v) - 1; i >= 0; i--) {}  // Using macro
```

### Pass by Reference
```cpp
// ❌ WRONG - Unnecessary copies (slow for large containers)
void process(vector<int> v) {}
void modify(string s) {}

// ✅ CORRECT
void process(const vector<int>& v) {}  // Read-only
void modify(vector<int>& v) {}          // Modify
void iterate(const string& s) {}        // Avoid copy
```

### Map/Set Iterator Invalidation
```cpp
// ❌ WRONG
for(auto it = m.begin(); it != m.end(); it++) {
    m.erase(it);  // Invalidates iterator
}

// ✅ CORRECT
for(auto it = m.begin(); it != m.end();) {
    if(condition) {
        it = m.erase(it);  // Returns next valid iterator
    } else {
        it++;
    }
}
```

### Vector Reserve vs Resize
```cpp
// Reserve - allocates memory, no initialization
v.reserve(1000000);  // Fast, use when you know size

// Resize - allocates and initializes
v.resize(1000000);   // Slower, use when you need default values
```

### Comparing Doubles
```cpp
// ❌ WRONG
if(a == b) {}
if(a > b) {}

// ✅ CORRECT
const double EPS = 1e-9;
if(abs(a - b) < EPS) {}  // Equal
if(a > b + EPS) {}        // Greater than
```

### Modulo with Negative Numbers
```cpp
// ❌ WRONG - Can be negative
int mod = a % MOD;

// ✅ CORRECT
int mod = ((a % MOD) + MOD) % MOD;
```

### Using unordered_map with Custom Types
```cpp
// Need custom hash function
struct PairHash {
    size_t operator()(const pair<int, int>& p) const {
        return hash<int>()(p.first) ^ (hash<int>()(p.second) << 1);
    }
};

unordered_map<pair<int, int>, int, PairHash> mp;

// Alternative: Use map (slower but works)
map<pair<int, int>, int> mp;
```

### endl vs '\n'
```cpp
// ❌ SLOW - Flushes buffer every time
cout << x << endl;

// ✅ FAST
cout << x << '\n';
```

### Global vs Local Variables
```cpp
// Global arrays are zero-initialized
int arr[100000];  // All zeros

// Local arrays have garbage values
int main() {
    int arr[100000];  // Garbage values!
    
    // Need to initialize
    memset(arr, 0, sizeof(arr));
    fill(arr, arr + 100000, 0);
}
```

---

## 🚀 TIME COMPLEXITY QUICK REFERENCE

```cpp
// O(1) - Constant
arr[i], map[key], set.find()

// O(log n) - Logarithmic
binary_search, lower_bound, upper_bound
map operations, set operations
binary search on answer

// O(n) - Linear
Single loop, linear search
vector operations (most)

// O(n log n) - Linearithmic  
Sorting: sort(), stable_sort()
Building heap
Merge sort

// O(n²) - Quadratic
Nested loops
Bubble sort, Selection sort

// O(n³) - Cubic
Triple nested loops
Floyd-Warshall

// O(2ⁿ) - Exponential
All subsets
Recursive without memoization

// O(n!) - Factorial
All permutations
```

---

## 📏 COMMON LIMITS

```cpp
// Integer types
int:              -2×10⁹ to 2×10⁹         (~2.1 billion)
unsigned int:     0 to 4×10⁹              (~4.2 billion)
long long:        -9×10¹⁸ to 9×10¹⁸       
unsigned ll:      0 to 1.8×10¹⁹

// Safe operations
10⁶ operations:   Usually safe
10⁷ operations:   Might be tight
10⁸ operations:   Risky, depends on constant
10⁹ operations:   Usually TLE

// Array sizes
int arr[10⁶]:     Safe
int arr[10⁷]:     Might exceed stack (use global or dynamic)

// Modulo
const int MOD = 1e9 + 7;
const int MOD = 998244353;
```

---

**Happy Coding! 🚀**
