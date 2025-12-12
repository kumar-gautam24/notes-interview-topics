# ☕ Java Ultimate Cheat Sheet for LeetCode
## Competitive Programming & Technical Interviews

---

## 🔤 BASIC DATA TYPES & PRIMITIVES

### Primitive Types
```java
// Integer types
byte b = 127;                             // 1 byte: -128 to 127
short s = 32767;                          // 2 bytes: -32,768 to 32,767
int i = 2147483647;                       // 4 bytes: -2³¹ to 2³¹-1
long l = 9223372036854775807L;           // 8 bytes: -2⁶³ to 2⁶³-1 (note 'L')

// Floating point
float f = 3.14f;                          // 4 bytes (note 'f')
double d = 3.14159265358979;              // 8 bytes

// Character and Boolean
char c = 'A';                             // 2 bytes (Unicode)
boolean flag = true;                      // true or false

// Constants
final int MAX = 100000;
final double PI = 3.14159265358979;
```

### Wrapper Classes (Object versions of primitives)
```java
// Auto-boxing (primitive → wrapper)
Integer num = 10;                         // Auto-boxing
int x = num;                              // Auto-unboxing

// Wrapper class objects
Byte b = 127;
Short s = 32767;
Integer i = 2147483647;
Long l = 9223372036854775807L;
Float f = 3.14f;
Double d = 3.14159265358979;
Character c = 'A';
Boolean flag = true;

// Why use wrappers?
// - Collections only work with objects (ArrayList<Integer>, not ArrayList<int>)
// - Nullable values (Integer can be null, int cannot)
// - Utility methods available

// Useful wrapper methods
Integer.parseInt("123");                  // String to int
Integer.toString(123);                    // int to String
Integer.valueOf("123");                   // String to Integer object
Integer.MAX_VALUE;                        // 2,147,483,647
Integer.MIN_VALUE;                        // -2,147,483,648
Long.MAX_VALUE;                           // 9,223,372,036,854,775,807
Long.MIN_VALUE;                           // -9,223,372,036,854,775,808

Character.isDigit('5');                   // true
Character.isLetter('A');                  // true
Character.toLowerCase('A');               // 'a'
Character.toUpperCase('a');               // 'A'
```

### Type Conversion & Casting
```java
// Implicit conversion (widening)
int i = 10;
double d = i;                             // int → double (safe)
long l = i;                               // int → long (safe)

// Explicit casting (narrowing)
double d = 3.14;
int i = (int)d;                           // 3 (truncates decimal)

long l = 100L;
int i2 = (int)l;                          // Potential data loss if l > Integer.MAX_VALUE

// Safe conversion with range check
long l = 5000000000L;
if(l >= Integer.MIN_VALUE && l <= Integer.MAX_VALUE) {
    int i = (int)l;
} else {
    // Handle overflow
}

// Between char and int
char c = 'A';
int code = (int)c;                        // 65 (ASCII value)
char fromCode = (char)65;                 // 'A'

// Character arithmetic
char c = 'A';
int position = c - 'A';                   // 0 (position in alphabet)
char digit = '5';
int value = digit - '0';                  // 5 (convert digit char to int)
```

### Math Operations
```java
import java.lang.Math;

// Basic operations
int sum = a + b;
int diff = a - b;
int product = a * b;
int quotient = a / b;                     // Integer division
int remainder = a % b;                    // Modulo

// Math class methods
Math.abs(-5);                             // 5
Math.max(10, 20);                         // 20
Math.min(10, 20);                         // 10
Math.pow(2, 3);                           // 8.0
Math.sqrt(16);                            // 4.0
Math.ceil(3.2);                           // 4.0
Math.floor(3.8);                          // 3.0
Math.round(3.5);                          // 4

// Random numbers
Math.random();                            // [0.0, 1.0)
int random = (int)(Math.random() * 100);  // [0, 99]

// Using Random class
import java.util.Random;
Random rand = new Random();
int num = rand.nextInt(100);              // [0, 99]
int num2 = rand.nextInt(50) + 50;         // [50, 99]
```

---

## 📦 ARRAYS (Fixed Size)

### Declaration & Initialization
```java
// Declaration
int[] arr;                                // Preferred
int arr2[];                               // Alternative (C-style)

// Initialization
int[] arr = new int[5];                   // Size 5, all zeros
int[] arr2 = {1, 2, 3, 4, 5};            // Initialize with values
int[] arr3 = new int[]{1, 2, 3};         // Alternative

// 2D arrays
int[][] mat = new int[3][4];              // 3 rows, 4 columns, all zeros
int[][] mat2 = {{1,2,3}, {4,5,6}};       // Initialize with values

// Jagged arrays (rows with different lengths)
int[][] jagged = new int[3][];
jagged[0] = new int[2];
jagged[1] = new int[3];
jagged[2] = new int[4];
```

### Operations
```java
// Length
int length = arr.length;                  // Note: length, not length()!

// Access & Modify
arr[0] = 10;                              // Set element
int x = arr[0];                           // Get element

// Fill with value
Arrays.fill(arr, value);
Arrays.fill(arr, start, end, value);      // Range fill [start, end)

// Copy
int[] copy = arr.clone();                 // Shallow copy
int[] copy2 = Arrays.copyOf(arr, arr.length);
int[] copy3 = Arrays.copyOfRange(arr, start, end); // [start, end)

// Manual copy
int[] copy4 = new int[arr.length];
System.arraycopy(arr, 0, copy4, 0, arr.length);

// Compare
boolean equal = Arrays.equals(arr1, arr2);
boolean deepEqual = Arrays.deepEquals(mat1, mat2); // For 2D arrays

// String representation
System.out.println(Arrays.toString(arr));         // [1, 2, 3, 4, 5]
System.out.println(Arrays.deepToString(mat));     // For 2D arrays
```

### Iteration - Comprehensive Examples
```java
int[] arr = {10, 20, 30, 40, 50};

// 1. Index-based (most common)
for(int i = 0; i < arr.length; i++) {
    System.out.println(i + ": " + arr[i]);
    arr[i] *= 2;                          // Can modify
}

// 2. Enhanced for loop (for-each)
for(int x : arr) {
    System.out.println(x);                // Cannot modify through x
}

// To modify, still need index:
for(int i = 0; i < arr.length; i++) {
    arr[i] = newValue;
}

// 3. Reverse iteration
for(int i = arr.length - 1; i >= 0; i--) {
    System.out.println(arr[i]);
}

// 4. With step size
for(int i = 0; i < arr.length; i += 2) {  // Every 2nd element
    System.out.println(arr[i]);
}

// 5. Two-pointer iteration
int left = 0, right = arr.length - 1;
while(left < right) {
    System.out.println(arr[left] + " " + arr[right]);
    left++;
    right--;
}

// 6. Iterate until condition
for(int i = 0; i < arr.length && arr[i] != 0; i++) {
    System.out.println(arr[i]);
}

// 7. Sliding window (fixed size k)
int k = 3;
for(int i = 0; i <= arr.length - k; i++) {
    // Process window [i, i+k)
    for(int j = i; j < i + k; j++) {
        System.out.print(arr[j] + " ");
    }
    System.out.println();
}

// 8. Using Streams (Java 8+)
Arrays.stream(arr).forEach(x -> System.out.println(x));
Arrays.stream(arr).forEach(System.out::println);  // Method reference

// Filter and collect
int[] filtered = Arrays.stream(arr)
                       .filter(x -> x > 20)
                       .toArray();

// Map and collect
int[] doubled = Arrays.stream(arr)
                      .map(x -> x * 2)
                      .toArray();

// Sum
int sum = Arrays.stream(arr).sum();

// Max/Min
int max = Arrays.stream(arr).max().getAsInt();
int min = Arrays.stream(arr).min().getAsInt();
```

### 2D Array Iteration
```java
int[][] mat = {{1, 2, 3}, {4, 5, 6}, {7, 8, 9}};

// Row by row
for(int i = 0; i < mat.length; i++) {
    for(int j = 0; j < mat[i].length; j++) {
        System.out.print(mat[i][j] + " ");
    }
    System.out.println();
}

// Enhanced for loop
for(int[] row : mat) {
    for(int value : row) {
        System.out.print(value + " ");
    }
    System.out.println();
}

// Column by column
for(int j = 0; j < mat[0].length; j++) {
    for(int i = 0; i < mat.length; i++) {
        System.out.print(mat[i][j] + " ");
    }
    System.out.println();
}

// Diagonal
for(int i = 0; i < mat.length && i < mat[0].length; i++) {
    System.out.println(mat[i][i]);
}

// Using Streams (flatten to 1D)
Arrays.stream(mat)
      .flatMapToInt(Arrays::stream)
      .forEach(System.out::println);
```

---

## 🔗 LINKED LIST (Custom Implementation)

### Node Definition
```java
// Singly Linked List Node
class ListNode {
    int val;
    ListNode next;
    
    ListNode() {}
    ListNode(int val) { this.val = val; }
    ListNode(int val, ListNode next) { 
        this.val = val; 
        this.next = next; 
    }
}

// Doubly Linked List Node
class DListNode {
    int val;
    DListNode prev;
    DListNode next;
    
    DListNode(int val) {
        this.val = val;
        this.prev = null;
        this.next = null;
    }
}
```

### Basic Operations
```java
// Create from array
ListNode createList(int[] arr) {
    if(arr.length == 0) return null;
    
    ListNode head = new ListNode(arr[0]);
    ListNode curr = head;
    
    for(int i = 1; i < arr.length; i++) {
        curr.next = new ListNode(arr[i]);
        curr = curr.next;
    }
    return head;
}

// Insert at beginning
ListNode insertAtBegin(ListNode head, int val) {
    ListNode newNode = new ListNode(val);
    newNode.next = head;
    return newNode;  // New head
}

// Insert at end
ListNode insertAtEnd(ListNode head, int val) {
    ListNode newNode = new ListNode(val);
    
    if(head == null) return newNode;
    
    ListNode curr = head;
    while(curr.next != null) {
        curr = curr.next;
    }
    curr.next = newNode;
    return head;
}

// Insert at position (0-indexed)
ListNode insertAtPos(ListNode head, int pos, int val) {
    if(pos == 0) return insertAtBegin(head, val);
    
    ListNode curr = head;
    for(int i = 0; i < pos - 1 && curr != null; i++) {
        curr = curr.next;
    }
    
    if(curr == null) return head;  // Invalid position
    
    ListNode newNode = new ListNode(val);
    newNode.next = curr.next;
    curr.next = newNode;
    return head;
}

// Delete node with value
ListNode deleteNode(ListNode head, int val) {
    if(head == null) return null;
    
    // If head needs to be deleted
    if(head.val == val) {
        return head.next;
    }
    
    ListNode curr = head;
    while(curr.next != null && curr.next.val != val) {
        curr = curr.next;
    }
    
    if(curr.next != null) {
        curr.next = curr.next.next;
    }
    return head;
}

// Search for value
boolean search(ListNode head, int val) {
    ListNode curr = head;
    while(curr != null) {
        if(curr.val == val) return true;
        curr = curr.next;
    }
    return false;
}

// Get length
int getLength(ListNode head) {
    int len = 0;
    ListNode curr = head;
    while(curr != null) {
        len++;
        curr = curr.next;
    }
    return len;
}

// Get nth node (0-indexed)
ListNode getNth(ListNode head, int n) {
    ListNode curr = head;
    for(int i = 0; i < n && curr != null; i++) {
        curr = curr.next;
    }
    return curr;
}
```

### Iteration Patterns - Comprehensive
```java
ListNode head = createList(new int[]{1, 2, 3, 4, 5});

// 1. Basic traversal
void traverse(ListNode head) {
    ListNode curr = head;
    while(curr != null) {
        System.out.print(curr.val + " ");
        curr = curr.next;
    }
}

// 2. With index
void traverseWithIndex(ListNode head) {
    ListNode curr = head;
    int index = 0;
    while(curr != null) {
        System.out.println("Index " + index + ": " + curr.val);
        curr = curr.next;
        index++;
    }
}

// 3. Two pointers (slow-fast)
ListNode findMiddle(ListNode head) {
    ListNode slow = head, fast = head;
    
    while(fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
    }
    return slow;
}

// 4. Previous + Current pattern
void traverseWithPrev(ListNode head) {
    ListNode prev = null;
    ListNode curr = head;
    
    while(curr != null) {
        System.out.println("Prev: " + (prev != null ? prev.val : "null") + 
                         ", Curr: " + curr.val);
        prev = curr;
        curr = curr.next;
    }
}

// 5. Iterate until condition
void traverseUntilValue(ListNode head, int target) {
    ListNode curr = head;
    while(curr != null && curr.val != target) {
        System.out.println(curr.val);
        curr = curr.next;
    }
}

// 6. Iterate and collect values
List<Integer> toList(ListNode head) {
    List<Integer> result = new ArrayList<>();
    ListNode curr = head;
    while(curr != null) {
        result.add(curr.val);
        curr = curr.next;
    }
    return result;
}

// 7. Iterate and modify
void doubleAllValues(ListNode head) {
    ListNode curr = head;
    while(curr != null) {
        curr.val *= 2;
        curr = curr.next;
    }
}

// 8. Recursive traversal
void traverseRecursive(ListNode head) {
    if(head == null) return;
    System.out.print(head.val + " ");
    traverseRecursive(head.next);
}

// 9. Iterate with lookahead
void traverseWithLookahead(ListNode head) {
    ListNode curr = head;
    while(curr != null) {
        System.out.print("Curr: " + curr.val);
        if(curr.next != null) {
            System.out.print(", Next: " + curr.next.val);
        }
        System.out.println();
        curr = curr.next;
    }
}
```

### Copy & Clone
```java
// Deep copy (create new nodes)
ListNode deepCopy(ListNode head) {
    if(head == null) return null;
    
    ListNode newHead = new ListNode(head.val);
    ListNode curr = head.next;
    ListNode newCurr = newHead;
    
    while(curr != null) {
        newCurr.next = new ListNode(curr.val);
        newCurr = newCurr.next;
        curr = curr.next;
    }
    
    return newHead;
}

// Shallow copy (just reference)
ListNode shallowCopy(ListNode head) {
    return head;  // Both variables point to same nodes!
}

// Convert to array
int[] toArray(ListNode head) {
    List<Integer> list = new ArrayList<>();
    ListNode curr = head;
    while(curr != null) {
        list.add(curr.val);
        curr = curr.next;
    }
    
    // Convert List to array
    int[] arr = new int[list.size()];
    for(int i = 0; i < list.size(); i++) {
        arr[i] = list.get(i);
    }
    return arr;
}

// Using streams
int[] toArrayStream(ListNode head) {
    List<Integer> list = new ArrayList<>();
    ListNode curr = head;
    while(curr != null) {
        list.add(curr.val);
        curr = curr.next;
    }
    return list.stream().mapToInt(i -> i).toArray();
}
```

### Common Patterns
```java
// Reverse linked list
ListNode reverse(ListNode head) {
    ListNode prev = null;
    ListNode curr = head;
    
    while(curr != null) {
        ListNode next = curr.next;
        curr.next = prev;
        prev = curr;
        curr = next;
    }
    return prev;
}

// Detect cycle
boolean hasCycle(ListNode head) {
    ListNode slow = head, fast = head;
    
    while(fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if(slow == fast) return true;
    }
    return false;
}

// Merge two sorted lists
ListNode mergeTwoLists(ListNode l1, ListNode l2) {
    ListNode dummy = new ListNode(0);
    ListNode curr = dummy;
    
    while(l1 != null && l2 != null) {
        if(l1.val < l2.val) {
            curr.next = l1;
            l1 = l1.next;
        } else {
            curr.next = l2;
            l2 = l2.next;
        }
        curr = curr.next;
    }
    
    curr.next = (l1 != null) ? l1 : l2;
    return dummy.next;
}

// Remove nth node from end
ListNode removeNthFromEnd(ListNode head, int n) {
    ListNode dummy = new ListNode(0);
    dummy.next = head;
    
    ListNode first = dummy;
    ListNode second = dummy;
    
    // Move first n+1 steps ahead
    for(int i = 0; i <= n; i++) {
        first = first.next;
    }
    
    // Move both until first reaches end
    while(first != null) {
        first = first.next;
        second = second.next;
    }
    
    // Remove node
    second.next = second.next.next;
    return dummy.next;
}
```

---

## ⚡ Fast I/O Boilerplate

```java
import java.util.*;
import java.io.*;

class Solution {
    // Fast I/O using BufferedReader
    static class FastReader {
        BufferedReader br;
        StringTokenizer st;
        
        public FastReader() {
            br = new BufferedReader(new InputStreamReader(System.in));
        }
        
        String next() {
            while(st == null || !st.hasMoreElements()) {
                try {
                    st = new StringTokenizer(br.readLine());
                } catch(IOException e) {
                    e.printStackTrace();
                }
            }
            return st.nextToken();
        }
        
        int nextInt() { return Integer.parseInt(next()); }
        long nextLong() { return Long.parseLong(next()); }
        double nextDouble() { return Double.parseDouble(next()); }
        
        String nextLine() {
            String str = "";
            try {
                str = br.readLine();
            } catch(IOException e) {
                e.printStackTrace();
            }
            return str;
        }
    }
    
    // Fast output
    static PrintWriter out = new PrintWriter(System.out);
    
    // Constants
    static final int MOD = 1000000007;
    static final int MOD2 = 998244353;
    static final int INF = Integer.MAX_VALUE;
    static final long LINF = Long.MAX_VALUE;
    static final double EPS = 1e-9;
    
    public static void main(String[] args) {
        FastReader sc = new FastReader();
        
        // Your code here
        
        out.close();  // Don't forget to close!
    }
}
```

---

## 📊 ARRAYLIST (Dynamic Array)

### Declaration & Initialization
```java
ArrayList<Integer> list = new ArrayList<>();
ArrayList<Integer> list = new ArrayList<>(Arrays.asList(1, 2, 3));
ArrayList<Integer> list = new ArrayList<>(n);  // Initial capacity
ArrayList<Integer> list = new ArrayList<>(otherList);  // Copy

// 2D ArrayList
ArrayList<ArrayList<Integer>> list2D = new ArrayList<>();
for(int i = 0; i < n; i++) {
    list2D.add(new ArrayList<>());
}
```

### Core Operations
```java
// Adding elements
list.add(x);                           // O(1) amortized - add to end
list.add(i, x);                        // O(n) - insert at index
list.addAll(Arrays.asList(1, 2, 3));  // Add multiple

// Removing elements
list.remove(i);                        // O(n) - remove at index (returns element)
list.remove(Integer.valueOf(x));       // O(n) - remove by value (returns boolean)
list.clear();                          // Remove all

// Access & Update
list.get(i);                           // O(1) - get element at index
list.set(i, x);                        // O(1) - update element at index

// Size & Check
list.size();                           // Number of elements
list.isEmpty();                        // Check if empty

// Search
list.contains(x);                      // O(n) - check if contains
list.indexOf(x);                       // O(n) - first occurrence (-1 if not found)
list.lastIndexOf(x);                   // O(n) - last occurrence
```

### Iteration
```java
// Enhanced for loop
for(int x : list) {
    System.out.println(x);
}

// Index-based
for(int i = 0; i < list.size(); i++) {
    int x = list.get(i);
}

// Iterator
Iterator<Integer> it = list.iterator();
while(it.hasNext()) {
    int x = it.next();
}

// forEach (Java 8+)
list.forEach(x -> System.out.println(x));
```

### Sorting & Searching
```java
// Sorting
Collections.sort(list);                     // Ascending
Collections.sort(list, Collections.reverseOrder());  // Descending
Collections.reverse(list);                  // Reverse

// Custom comparator
Collections.sort(list, (a, b) -> a - b);   // Ascending
Collections.sort(list, (a, b) -> b - a);   // Descending

// Binary search (requires sorted list)
int idx = Collections.binarySearch(list, x);  // Returns index or -(insertion_point+1)

// Min/Max
int max = Collections.max(list);
int min = Collections.min(list);

// Frequency
int count = Collections.frequency(list, x);
```

### Conversion
```java
// ArrayList to Array
Integer[] arr = list.toArray(new Integer[0]);
Integer[] arr = list.toArray(new Integer[list.size()]);

// Array to ArrayList
Integer[] arr = {1, 2, 3};
ArrayList<Integer> list = new ArrayList<>(Arrays.asList(arr));

// For primitive int array
int[] arr = {1, 2, 3};
ArrayList<Integer> list = new ArrayList<>();
for(int x : arr) list.add(x);

// Stream API (Java 8+)
List<Integer> list = Arrays.stream(arr).boxed().collect(Collectors.toList());
```

---

## 📝 ARRAYS

### Declaration & Initialization
```java
int[] arr = new int[n];                    // All zeros
int[] arr = {1, 2, 3, 4, 5};              // Initialize with values
int[] arr = new int[]{1, 2, 3};           // Alternative

// 2D arrays
int[][] mat = new int[n][m];              // All zeros
int[][] mat = {{1, 2}, {3, 4}};          // Initialize

// Jagged arrays
int[][] jagged = new int[n][];
for(int i = 0; i < n; i++) {
    jagged[i] = new int[m];
}
```

### Operations
```java
// Length
arr.length;                                // Not arr.length()!

// Fill with value
Arrays.fill(arr, value);
Arrays.fill(arr, start, end, value);      // Range fill [start, end)

// Copy
int[] copy = arr.clone();
int[] copy = Arrays.copyOf(arr, arr.length);
int[] copy = Arrays.copyOfRange(arr, start, end);  // [start, end)

// Sorting
Arrays.sort(arr);                          // Ascending
Arrays.sort(arr, start, end);             // Sort range [start, end)

// For Integer[] (not int[])
Integer[] arr = {3, 1, 4, 1, 5};
Arrays.sort(arr, Collections.reverseOrder());  // Descending
Arrays.sort(arr, (a, b) -> a - b);        // Custom comparator

// Binary search (requires sorted array)
int idx = Arrays.binarySearch(arr, x);    // Returns index or -(insertion_point+1)

// Equality
Arrays.equals(arr1, arr2);                // Check if equal
Arrays.deepEquals(mat1, mat2);            // For 2D arrays

// String representation
Arrays.toString(arr);                      // "[1, 2, 3]"
Arrays.deepToString(mat);                  // For 2D arrays
```

### Sorting 2D Arrays
```java
int[][] intervals = {{1, 3}, {2, 6}, {8, 10}};

// Sort by first element
Arrays.sort(intervals, (a, b) -> a[0] - b[0]);

// Sort by second element
Arrays.sort(intervals, (a, b) -> a[1] - b[1]);

// Sort by first, then second
Arrays.sort(intervals, (a, b) -> {
    if(a[0] != b[0]) return a[0] - b[0];
    return a[1] - b[1];
});

// Use Comparator.comparingInt for clarity (Java 8+)
Arrays.sort(intervals, Comparator.comparingInt(a -> a[0]));
```

---

## 📝 STRING

### Declaration & Initialization
```java
String s = "hello";
String s = new String("hello");
String s = new String(charArray);

// String from characters
char[] chars = {'h', 'e', 'l', 'l', 'o'};
String s = new String(chars);
String s = String.valueOf(chars);
```

### Core Operations
```java
// Length & Access
s.length();                                // Length (not size()!)
s.charAt(i);                               // Get character at index
s.isEmpty();                               // Check if empty

// Substring
s.substring(start);                        // From start to end
s.substring(start, end);                   // [start, end)

// Search
s.indexOf("sub");                          // First occurrence (-1 if not found)
s.indexOf('c');                            // Find character
s.indexOf("sub", fromIndex);               // Find from index
s.lastIndexOf("sub");                      // Last occurrence
s.contains("sub");                         // Check contains

// Check prefix/suffix
s.startsWith("prefix");
s.endsWith("suffix");

// Case conversion
s.toLowerCase();                           // To lowercase
s.toUpperCase();                           // To uppercase

// Trim & Strip
s.trim();                                  // Remove leading/trailing whitespace
s.strip();                                 // Java 11+ (handles Unicode)

// Replace
s.replace('a', 'b');                       // Replace all char occurrences
s.replace("old", "new");                   // Replace all substring occurrences
s.replaceAll("regex", "new");              // Replace with regex
s.replaceFirst("regex", "new");            // Replace first match

// Split
String[] parts = s.split(" ");             // Split by space
String[] parts = s.split(",");             // Split by comma
String[] parts = s.split("\\s+");          // Split by whitespace (regex)

// Join
String result = String.join(", ", list);   // Join with delimiter
String result = String.join("-", "a", "b", "c");
```

### Comparison
```java
// Equality
s1.equals(s2);                             // Content equality (USE THIS!)
s1.equalsIgnoreCase(s2);                   // Ignore case
s1 == s2;                                  // Reference equality (DON'T USE!)

// Lexicographic comparison
s1.compareTo(s2);                          // Returns <0, 0, or >0
s1.compareToIgnoreCase(s2);                // Ignore case
```

### Conversion
```java
// String to Number
int num = Integer.parseInt(s);
long lnum = Long.parseLong(s);
double dnum = Double.parseDouble(s);

// Number to String
String s = String.valueOf(123);
String s = Integer.toString(123);
String s = "" + 123;                       // Simple but creates temp objects

// String to char array
char[] chars = s.toCharArray();

// char array to String
String s = new String(chars);
String s = String.valueOf(chars);
```

### Character Methods
```java
// Character checks
Character.isLetter(c);                     // Is letter
Character.isDigit(c);                      // Is digit
Character.isLetterOrDigit(c);              // Is alphanumeric
Character.isLowerCase(c);                  // Is lowercase
Character.isUpperCase(c);                  // Is uppercase
Character.isWhitespace(c);                 // Is whitespace

// Case conversion
Character.toLowerCase(c);
Character.toUpperCase(c);

// Character to digit
int digit = c - '0';                       // For digit characters
int pos = c - 'a';                         // Position in alphabet (lowercase)
int pos = c - 'A';                         // Position in alphabet (uppercase)
```

---

## 🔨 STRINGBUILDER (Mutable String)

### Declaration & Operations
```java
StringBuilder sb = new StringBuilder();
StringBuilder sb = new StringBuilder("hello");
StringBuilder sb = new StringBuilder(capacity);

// Append
sb.append("text");                         // Append string
sb.append(123);                            // Append number
sb.append('c');                            // Append char

// Insert
sb.insert(index, "text");                  // Insert at index
sb.insert(index, 123);

// Delete
sb.delete(start, end);                     // Delete range [start, end)
sb.deleteCharAt(index);                    // Delete at index

// Replace
sb.replace(start, end, "new");             // Replace range

// Reverse
sb.reverse();                              // Reverse string

// Access & Modify
sb.charAt(i);                              // Get char at index
sb.setCharAt(i, 'c');                      // Set char at index

// Length
sb.length();                               // Current length
sb.setLength(newLen);                      // Set length

// Convert to String
String s = sb.toString();
```

### When to Use StringBuilder
```java
// ❌ SLOW - Creates many intermediate String objects
String result = "";
for(int i = 0; i < n; i++) {
    result += i;                           // O(n²) overall!
}

// ✅ FAST - Mutable, no intermediate objects
StringBuilder sb = new StringBuilder();
for(int i = 0; i < n; i++) {
    sb.append(i);                          // O(n) overall
}
String result = sb.toString();
```

---

## 🗺️ HASHMAP

### Declaration
```java
HashMap<Integer, Integer> map = new HashMap<>();
HashMap<String, Integer> map = new HashMap<>();
HashMap<Integer, List<Integer>> map = new HashMap<>();

// With initial capacity
HashMap<Integer, Integer> map = new HashMap<>(capacity);

// From another map
HashMap<Integer, Integer> map = new HashMap<>(otherMap);
```

### Operations - O(1) Average
```java
// Insert/Update
map.put(key, value);                       // Insert or update

// Access
map.get(key);                              // Get value (null if not exists)
map.getOrDefault(key, defaultValue);       // Get with default

// Remove
map.remove(key);                           // Remove key-value pair
map.remove(key, value);                    // Remove only if matches value

// Check
map.containsKey(key);                      // Check if key exists
map.containsValue(value);                  // Check if value exists (O(n))

// Size
map.size();
map.isEmpty();
map.clear();
```

### Advanced Operations
```java
// Put if absent
map.putIfAbsent(key, value);

// Compute methods (Java 8+)
map.computeIfAbsent(key, k -> new ArrayList<>());  // Useful for map of lists
map.computeIfPresent(key, (k, v) -> v + 1);
map.compute(key, (k, v) -> (v == null) ? 1 : v + 1);

// Merge (useful for counting)
map.merge(key, 1, Integer::sum);           // Increment count
map.merge(key, value, (oldVal, newVal) -> oldVal + newVal);

// Replace
map.replace(key, newValue);
map.replace(key, oldValue, newValue);      // Replace only if matches oldValue
```

### Iteration
```java
// Iterate through entries
for(Map.Entry<Integer, Integer> entry : map.entrySet()) {
    int key = entry.getKey();
    int value = entry.getValue();
}

// Iterate through keys
for(Integer key : map.keySet()) {
    int value = map.get(key);
}

// Iterate through values
for(Integer value : map.values()) {
    System.out.println(value);
}

// forEach (Java 8+)
map.forEach((key, value) -> {
    System.out.println(key + " -> " + value);
});
```

---

## 🗺️ TREEMAP (Sorted Map)

### Declaration & Operations - O(log n)
```java
TreeMap<Integer, Integer> map = new TreeMap<>();

// All HashMap operations work
map.put(key, value);
map.get(key);
map.remove(key);
map.containsKey(key);

// Additional ordered operations
map.firstKey();                            // Smallest key
map.lastKey();                             // Largest key
map.lowerKey(key);                         // Largest key < key (null if none)
map.floorKey(key);                         // Largest key <= key
map.ceilingKey(key);                       // Smallest key >= key
map.higherKey(key);                        // Smallest key > key

// Entry operations
map.firstEntry();                          // Entry with smallest key
map.lastEntry();                           // Entry with largest key
map.lowerEntry(key);                       // Entry with largest key < key
map.floorEntry(key);                       // Entry with largest key <= key
map.ceilingEntry(key);                     // Entry with smallest key >= key
map.higherEntry(key);                      // Entry with smallest key > key

// Poll (remove and return)
map.pollFirstEntry();                      // Remove and return smallest
map.pollLastEntry();                       // Remove and return largest

// Submap views
map.headMap(toKey);                        // Keys < toKey
map.tailMap(fromKey);                      // Keys >= fromKey
map.subMap(fromKey, toKey);                // Keys in [fromKey, toKey)
```

---

## 📦 HASHSET

### Declaration & Operations - O(1) Average
```java
HashSet<Integer> set = new HashSet<>();
HashSet<String> set = new HashSet<>();
HashSet<Integer> set = new HashSet<>(Arrays.asList(1, 2, 3));

// Insert
set.add(x);                                // Add element (returns boolean)
set.addAll(Arrays.asList(1, 2, 3));       // Add multiple

// Remove
set.remove(x);                             // Remove element (returns boolean)
set.clear();                               // Remove all

// Check
set.contains(x);                           // Check if contains
set.isEmpty();
set.size();

// Iteration (unordered)
for(int x : set) {
    System.out.println(x);
}
```

---

## 📦 TREESET (Sorted Set)

### Declaration & Operations - O(log n)
```java
TreeSet<Integer> set = new TreeSet<>();

// All HashSet operations work
set.add(x);
set.remove(x);
set.contains(x);
set.size();
set.isEmpty();

// Additional ordered operations
set.first();                               // Smallest element
set.last();                                // Largest element
set.lower(x);                              // Largest element < x (null if none)
set.floor(x);                              // Largest element <= x
set.ceiling(x);                            // Smallest element >= x
set.higher(x);                             // Smallest element > x

// Poll (remove and return)
set.pollFirst();                           // Remove and return smallest
set.pollLast();                            // Remove and return largest

// Subset views
set.headSet(toElement);                    // Elements < toElement
set.tailSet(fromElement);                  // Elements >= fromElement
set.subSet(fromElement, toElement);        // Elements in [fromElement, toElement)

// Iteration (sorted order)
for(int x : set) {
    System.out.println(x);                 // In ascending order
}

// Descending iteration
for(int x : set.descendingSet()) {
    System.out.println(x);
}
```

---

## 📚 STACK

### Declaration & Operations - All O(1)
```java
Stack<Integer> stack = new Stack<>();

stack.push(x);                             // Add to top
stack.pop();                               // Remove and return top
stack.peek();                              // Access top (doesn't remove)
stack.isEmpty();
stack.size();
stack.search(x);                           // Distance from top (1-indexed, -1 if not found)
```

### Common Patterns
```java
// Process all elements
while(!stack.isEmpty()) {
    int x = stack.pop();
    // Process x
}

// Monotonic stack (next greater element)
int[] nextGreater(int[] arr) {
    int n = arr.length;
    int[] result = new int[n];
    Arrays.fill(result, -1);
    Stack<Integer> stack = new Stack<>();  // Store indices
    
    for(int i = n-1; i >= 0; i--) {
        while(!stack.isEmpty() && arr[stack.peek()] <= arr[i]) {
            stack.pop();
        }
        if(!stack.isEmpty()) result[i] = arr[stack.peek()];
        stack.push(i);
    }
    return result;
}
```

---

## 📋 QUEUE

### Declaration & Operations - All O(1)
```java
Queue<Integer> queue = new LinkedList<>();

queue.offer(x);                            // Add to back (returns boolean)
queue.add(x);                              // Add to back (throws exception if fails)
queue.poll();                              // Remove and return front (null if empty)
queue.remove();                            // Remove and return front (throws exception if empty)
queue.peek();                              // Access front (null if empty)
queue.element();                           // Access front (throws exception if empty)
queue.isEmpty();
queue.size();
```

---

## 🔄 DEQUE (Double-Ended Queue)

### Declaration & Operations - All O(1)
```java
Deque<Integer> deque = new ArrayDeque<>();

// Add
deque.offerFirst(x);                       // Add to front
deque.offerLast(x);                        // Add to back
deque.addFirst(x);                         // Add to front (throws exception)
deque.addLast(x);                          // Add to back (throws exception)

// Remove
deque.pollFirst();                         // Remove from front (null if empty)
deque.pollLast();                          // Remove from back (null if empty)
deque.removeFirst();                       // Remove from front (throws exception)
deque.removeLast();                        // Remove from back (throws exception)

// Access
deque.peekFirst();                         // Access front (null if empty)
deque.peekLast();                          // Access back (null if empty)
deque.getFirst();                          // Access front (throws exception)
deque.getLast();                           // Access back (throws exception)

// Size
deque.isEmpty();
deque.size();
```

### Use Cases
```java
// Sliding window maximum
int[] maxSlidingWindow(int[] nums, int k) {
    int n = nums.length;
    int[] result = new int[n - k + 1];
    Deque<Integer> deque = new ArrayDeque<>();  // Store indices
    
    for(int i = 0; i < n; i++) {
        // Remove elements outside window
        while(!deque.isEmpty() && deque.peekFirst() <= i - k) {
            deque.pollFirst();
        }
        
        // Maintain decreasing order
        while(!deque.isEmpty() && nums[deque.peekLast()] < nums[i]) {
            deque.pollLast();
        }
        
        deque.offerLast(i);
        
        if(i >= k - 1) {
            result[i - k + 1] = nums[deque.peekFirst()];
        }
    }
    return result;
}
```

---

## 🏔️ PRIORITYQUEUE (Heap)

### Declaration
```java
PriorityQueue<Integer> pq = new PriorityQueue<>();  // Min heap (smallest on top)
PriorityQueue<Integer> maxPq = new PriorityQueue<>(Collections.reverseOrder());  // Max heap

// Custom comparator
PriorityQueue<Integer> pq = new PriorityQueue<>((a, b) -> a - b);  // Min heap
PriorityQueue<Integer> pq = new PriorityQueue<>((a, b) -> b - a);  // Max heap

// For arrays/lists
PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[0] - b[0]);  // Sort by first element

// Using Comparator.comparingInt (Java 8+)
PriorityQueue<int[]> pq = new PriorityQueue<>(Comparator.comparingInt(a -> a[0]));
```

### Operations
```java
pq.offer(x);                               // O(log n) - add element
pq.add(x);                                 // O(log n) - add element (throws exception)
pq.poll();                                 // O(log n) - remove and return min/max
pq.remove();                               // O(log n) - remove and return (throws exception)
pq.peek();                                 // O(1) - access min/max
pq.element();                              // O(1) - access (throws exception)
pq.isEmpty();
pq.size();
pq.clear();
```

### Common Use Cases
```java
// Kth largest element
int findKthLargest(int[] nums, int k) {
    PriorityQueue<Integer> minHeap = new PriorityQueue<>();
    
    for(int num : nums) {
        minHeap.offer(num);
        if(minHeap.size() > k) {
            minHeap.poll();
        }
    }
    return minHeap.peek();
}

// Merge K sorted lists
class Solution {
    public ListNode mergeKLists(ListNode[] lists) {
        PriorityQueue<ListNode> pq = new PriorityQueue<>((a, b) -> a.val - b.val);
        
        for(ListNode node : lists) {
            if(node != null) pq.offer(node);
        }
        
        ListNode dummy = new ListNode(0);
        ListNode curr = dummy;
        
        while(!pq.isEmpty()) {
            ListNode node = pq.poll();
            curr.next = node;
            curr = curr.next;
            if(node.next != null) pq.offer(node.next);
        }
        
        return dummy.next;
    }
}
```

---

## 🎯 ALGORITHMS

### Sorting
```java
// Arrays.sort() - for arrays
int[] arr = {3, 1, 4, 1, 5};
Arrays.sort(arr);                          // Ascending

// For Integer[] (not int[])
Integer[] arr = {3, 1, 4, 1, 5};
Arrays.sort(arr, Collections.reverseOrder());  // Descending
Arrays.sort(arr, (a, b) -> a - b);        // Custom comparator

// Collections.sort() - for lists
ArrayList<Integer> list = new ArrayList<>(Arrays.asList(3, 1, 4, 1, 5));
Collections.sort(list);                    // Ascending
Collections.sort(list, Collections.reverseOrder());  // Descending

// Sort 2D array
int[][] intervals = {{1, 3}, {2, 6}, {8, 10}};
Arrays.sort(intervals, (a, b) -> a[0] - b[0]);  // Sort by first element
Arrays.sort(intervals, (a, b) -> {         // Sort by first, then second
    if(a[0] != b[0]) return a[0] - b[0];
    return a[1] - b[1];
});

// Sort by multiple criteria using Comparator (Java 8+)
Arrays.sort(intervals, Comparator.comparingInt((int[] a) -> a[0])
                                 .thenComparingInt(a -> a[1]));
```

### Binary Search
```java
// Arrays.binarySearch()
int idx = Arrays.binarySearch(arr, target);  // Returns index or -(insertion_point+1)

// Collections.binarySearch()
int idx = Collections.binarySearch(list, target);

// Custom binary search
int binarySearch(int[] arr, int target) {
    int left = 0, right = arr.length - 1;
    
    while(left <= right) {
        int mid = left + (right - left) / 2;  // Avoid overflow
        
        if(arr[mid] == target) return mid;
        if(arr[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

// Binary search on answer (find minimum)
int binarySearchAnswer(int low, int high) {
    int ans = -1;
    
    while(low <= high) {
        int mid = low + (high - low) / 2;
        
        if(check(mid)) {
            ans = mid;
            high = mid - 1;                // Search left
        } else {
            low = mid + 1;
        }
    }
    return ans;
}

// Lower bound (first >= target)
int lowerBound(int[] arr, int target) {
    int left = 0, right = arr.length;
    
    while(left < right) {
        int mid = left + (right - left) / 2;
        if(arr[mid] < target) left = mid + 1;
        else right = mid;
    }
    return left;
}

// Upper bound (first > target)
int upperBound(int[] arr, int target) {
    int left = 0, right = arr.length;
    
    while(left < right) {
        int mid = left + (right - left) / 2;
        if(arr[mid] <= target) left = mid + 1;
        else right = mid;
    }
    return left;
}
```

### Two Pointers
```java
// Find pair with sum in sorted array
int[] twoSum(int[] arr, int target) {
    int left = 0, right = arr.length - 1;
    
    while(left < right) {
        int sum = arr[left] + arr[right];
        if(sum == target) return new int[]{left, right};
        if(sum < target) left++;
        else right--;
    }
    return new int[]{-1, -1};
}

// Remove duplicates in sorted array
int removeDuplicates(int[] arr) {
    if(arr.length == 0) return 0;
    
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
```java
// Fixed size window - Maximum sum of k elements
int maxSumKElements(int[] arr, int k) {
    int sum = 0;
    for(int i = 0; i < k; i++) sum += arr[i];
    int maxSum = sum;
    
    for(int i = k; i < arr.length; i++) {
        sum += arr[i] - arr[i - k];
        maxSum = Math.max(maxSum, sum);
    }
    return maxSum;
}

// Variable size - Longest substring with at most k distinct
int longestSubstringKDistinct(String s, int k) {
    HashMap<Character, Integer> freq = new HashMap<>();
    int left = 0, maxLen = 0;
    
    for(int right = 0; right < s.length(); right++) {
        char c = s.charAt(right);
        freq.put(c, freq.getOrDefault(c, 0) + 1);
        
        while(freq.size() > k) {
            char leftChar = s.charAt(left);
            freq.put(leftChar, freq.get(leftChar) - 1);
            if(freq.get(leftChar) == 0) freq.remove(leftChar);
            left++;
        }
        
        maxLen = Math.max(maxLen, right - left + 1);
    }
    return maxLen;
}
```

### Prefix Sum
```java
// 1D prefix sum
int[] buildPrefixSum(int[] arr) {
    int n = arr.length;
    int[] prefix = new int[n + 1];
    
    for(int i = 0; i < n; i++) {
        prefix[i + 1] = prefix[i] + arr[i];
    }
    return prefix;
}

// Query sum [l, r]
int rangeSum(int[] prefix, int l, int r) {
    return prefix[r + 1] - prefix[l];
}

// 2D prefix sum
int[][] build2DPrefix(int[][] matrix) {
    int n = matrix.length, m = matrix[0].length;
    int[][] prefix = new int[n + 1][m + 1];
    
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
int query2D(int[][] prefix, int r1, int c1, int r2, int c2) {
    return prefix[r2+1][c2+1] 
         - prefix[r1][c2+1] 
         - prefix[r2+1][c1] 
         + prefix[r1][c1];
}
```

---

## 📈 GRAPH ALGORITHMS

### Graph Representation
```java
// Adjacency List
int n = 5;  // Number of nodes
List<List<Integer>> adj = new ArrayList<>();
for(int i = 0; i < n; i++) {
    adj.add(new ArrayList<>());
}

// Add edge
adj.get(u).add(v);                         // Directed
adj.get(u).add(v);                         // Undirected
adj.get(v).add(u);

// Weighted graph
List<List<int[]>> adj = new ArrayList<>();  // List of {neighbor, weight}
for(int i = 0; i < n; i++) {
    adj.add(new ArrayList<>());
}
adj.get(u).add(new int[]{v, weight});
```

### BFS
```java
int[] bfs(int start, List<List<Integer>> adj) {
    int n = adj.size();
    int[] dist = new int[n];
    Arrays.fill(dist, -1);
    Queue<Integer> queue = new LinkedList<>();
    
    queue.offer(start);
    dist[start] = 0;
    
    while(!queue.isEmpty()) {
        int u = queue.poll();
        
        for(int v : adj.get(u)) {
            if(dist[v] == -1) {
                dist[v] = dist[u] + 1;
                queue.offer(v);
            }
        }
    }
    return dist;
}

// BFS on grid
int[][] directions = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};

void bfsGrid(int startRow, int startCol, int[][] grid) {
    int n = grid.length, m = grid[0].length;
    boolean[][] visited = new boolean[n][m];
    Queue<int[]> queue = new LinkedList<>();
    
    queue.offer(new int[]{startRow, startCol});
    visited[startRow][startCol] = true;
    
    while(!queue.isEmpty()) {
        int[] curr = queue.poll();
        int x = curr[0], y = curr[1];
        
        for(int[] dir : directions) {
            int nx = x + dir[0];
            int ny = y + dir[1];
            
            if(nx >= 0 && nx < n && ny >= 0 && ny < m 
               && !visited[nx][ny] && grid[nx][ny] != -1) {
                visited[nx][ny] = true;
                queue.offer(new int[]{nx, ny});
            }
        }
    }
}
```

### DFS
```java
void dfs(int u, List<List<Integer>> adj, boolean[] visited) {
    visited[u] = true;
    
    // Process node u
    
    for(int v : adj.get(u)) {
        if(!visited[v]) {
            dfs(v, adj, visited);
        }
    }
}

// DFS with parent (for trees)
void dfs(int u, int parent, List<List<Integer>> adj) {
    for(int v : adj.get(u)) {
        if(v != parent) {
            dfs(v, u, adj);
        }
    }
}

// DFS cycle detection (directed)
boolean hasCycle(int u, List<List<Integer>> adj, 
                 boolean[] visited, boolean[] recStack) {
    visited[u] = true;
    recStack[u] = true;
    
    for(int v : adj.get(u)) {
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
```java
int[] dijkstra(int start, List<List<int[]>> adj) {
    int n = adj.size();
    int[] dist = new int[n];
    Arrays.fill(dist, Integer.MAX_VALUE);
    PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> a[0] - b[0]);  // {dist, node}
    
    dist[start] = 0;
    pq.offer(new int[]{0, start});
    
    while(!pq.isEmpty()) {
        int[] curr = pq.poll();
        int d = curr[0], u = curr[1];
        
        if(d > dist[u]) continue;
        
        for(int[] edge : adj.get(u)) {
            int v = edge[0], w = edge[1];
            
            if(dist[u] + w < dist[v]) {
                dist[v] = dist[u] + w;
                pq.offer(new int[]{dist[v], v});
            }
        }
    }
    return dist;
}
```

### Union-Find (Disjoint Set Union)
```java
class UnionFind {
    int[] parent, rank, size;
    int components;
    
    public UnionFind(int n) {
        parent = new int[n];
        rank = new int[n];
        size = new int[n];
        components = n;
        
        for(int i = 0; i < n; i++) {
            parent[i] = i;
            size[i] = 1;
        }
    }
    
    public int find(int x) {
        if(parent[x] != x) {
            parent[x] = find(parent[x]);   // Path compression
        }
        return parent[x];
    }
    
    public boolean union(int x, int y) {
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
    
    public boolean connected(int x, int y) {
        return find(x) == find(y);
    }
    
    public int getSize(int x) {
        return size[find(x)];
    }
    
    public int getComponents() {
        return components;
    }
}
```

### Topological Sort (Kahn's Algorithm)
```java
List<Integer> topologicalSort(List<List<Integer>> adj) {
    int n = adj.size();
    int[] indegree = new int[n];
    
    // Calculate indegree
    for(int u = 0; u < n; u++) {
        for(int v : adj.get(u)) {
            indegree[v]++;
        }
    }
    
    Queue<Integer> queue = new LinkedList<>();
    for(int i = 0; i < n; i++) {
        if(indegree[i] == 0) {
            queue.offer(i);
        }
    }
    
    List<Integer> result = new ArrayList<>();
    while(!queue.isEmpty()) {
        int u = queue.poll();
        result.add(u);
        
        for(int v : adj.get(u)) {
            if(--indegree[v] == 0) {
                queue.offer(v);
            }
        }
    }
    
    return result.size() == n ? result : new ArrayList<>();  // Empty if cycle
}
```

---

## 🎯 BIT MANIPULATION

### Basic Operations
```java
// Check if ith bit is set
boolean isSet = ((n & (1 << i)) != 0);

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

// Count set bits
int count = Integer.bitCount(n);
int count = Long.bitCount(n);  // For long

// Check if power of 2
boolean isPow2 = (n > 0) && ((n & (n - 1)) == 0);
```

### Subset Generation
```java
// Generate all subsets
void generateSubsets(int[] nums) {
    int n = nums.length;
    
    for(int mask = 0; mask < (1 << n); mask++) {
        List<Integer> subset = new ArrayList<>();
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
```java
// GCD
int gcd(int a, int b) {
    return b == 0 ? a : gcd(b, a % b);
}

// LCM
int lcm(int a, int b) {
    return (a / gcd(a, b)) * b;
}
```

### Prime Numbers
```java
// Check if prime
boolean isPrime(int n) {
    if(n <= 1) return false;
    if(n <= 3) return true;
    if(n % 2 == 0 || n % 3 == 0) return false;
    
    for(int i = 5; i * i <= n; i += 6) {
        if(n % i == 0 || n % (i + 2) == 0) return false;
    }
    return true;
}

// Sieve of Eratosthenes
boolean[] sieve(int n) {
    boolean[] isPrime = new boolean[n + 1];
    Arrays.fill(isPrime, true);
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
Map<Integer, Integer> primeFactorize(int n) {
    Map<Integer, Integer> factors = new HashMap<>();
    
    for(int i = 2; i * i <= n; i++) {
        while(n % i == 0) {
            factors.put(i, factors.getOrDefault(i, 0) + 1);
            n /= i;
        }
    }
    
    if(n > 1) factors.put(n, 1);
    return factors;
}
```

### Modular Arithmetic
```java
// Modular addition
int addMod(int a, int b, int mod) {
    return ((a % mod) + (b % mod)) % mod;
}

// Modular multiplication
long mulMod(long a, long b, long mod) {
    return ((a % mod) * (b % mod)) % mod;
}

// Modular exponentiation
long powerMod(long base, long exp, long mod) {
    long result = 1;
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

// Modular inverse (Fermat's Little Theorem - when mod is prime)
long modInverse(long a, long mod) {
    return powerMod(a, mod - 2, mod);
}
```

### Combinatorics
```java
// nCr with Pascal's triangle
long[][] pascalTriangle(int n) {
    long[][] C = new long[n + 1][n + 1];
    
    for(int i = 0; i <= n; i++) {
        C[i][0] = C[i][i] = 1;
        for(int j = 1; j < i; j++) {
            C[i][j] = C[i-1][j-1] + C[i-1][j];
        }
    }
    return C;
}
```

---

## 📦 DYNAMIC PROGRAMMING PATTERNS

### 1D DP
```java
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

// House robber
int rob(int[] nums) {
    int n = nums.length;
    if(n == 0) return 0;
    if(n == 1) return nums[0];
    
    int prev2 = nums[0];
    int prev1 = Math.max(nums[0], nums[1]);
    
    for(int i = 2; i < n; i++) {
        int curr = Math.max(prev1, prev2 + nums[i]);
        prev2 = prev1;
        prev1 = curr;
    }
    return prev1;
}
```

### 2D DP
```java
// Longest Common Subsequence
int longestCommonSubsequence(String s1, String s2) {
    int m = s1.length(), n = s2.length();
    int[][] dp = new int[m + 1][n + 1];
    
    for(int i = 1; i <= m; i++) {
        for(int j = 1; j <= n; j++) {
            if(s1.charAt(i-1) == s2.charAt(j-1)) {
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                dp[i][j] = Math.max(dp[i-1][j], dp[i][j-1]);
            }
        }
    }
    return dp[m][n];
}

// 0/1 Knapsack
int knapsack01(int[] weights, int[] values, int W) {
    int n = weights.length;
    int[][] dp = new int[n + 1][W + 1];
    
    for(int i = 1; i <= n; i++) {
        for(int w = 1; w <= W; w++) {
            if(weights[i-1] <= w) {
                dp[i][w] = Math.max(dp[i-1][w], 
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

### Integer Overflow
```java
// ❌ WRONG
int mid = (left + right) / 2;

// ✅ CORRECT
int mid = left + (right - left) / 2;

// ❌ WRONG - Multiplication overflow
int result = a * b;

// ✅ CORRECT
long result = (long)a * b;
```

### Comparator Subtraction Overflow
```java
// ❌ WRONG - Can overflow if a-b exceeds int range
Arrays.sort(arr, (a, b) -> a - b);

// ✅ CORRECT - Use Integer.compare()
Arrays.sort(arr, (a, b) -> Integer.compare(a, b));
Arrays.sort(arr, Integer::compare);  // Method reference
```

### Array vs ArrayList
```java
// Arrays.sort() for arrays
int[] arr = {3, 1, 4};
Arrays.sort(arr);

// Collections.sort() for lists
ArrayList<Integer> list = new ArrayList<>();
Collections.sort(list);

// ❌ WRONG - Can't sort primitive array in reverse
int[] arr = {3, 1, 4};
Arrays.sort(arr, Collections.reverseOrder());  // Compile error!

// ✅ CORRECT - Use Integer[]
Integer[] arr = {3, 1, 4};
Arrays.sort(arr, Collections.reverseOrder());
```

### String Concatenation in Loops
```java
// ❌ SLOW - O(n²) due to immutability
String result = "";
for(int i = 0; i < n; i++) {
    result += i;  // Creates new String object each time
}

// ✅ FAST - O(n)
StringBuilder sb = new StringBuilder();
for(int i = 0; i < n; i++) {
    sb.append(i);
}
String result = sb.toString();
```

### == vs equals()
```java
// ❌ WRONG - Compares references
String s1 = new String("hello");
String s2 = new String("hello");
if(s1 == s2) {}  // false

// ✅ CORRECT - Compares content
if(s1.equals(s2)) {}  // true
```

### Modulo with Negative Numbers
```java
// ❌ WRONG - Can be negative in Java
int mod = a % MOD;

// ✅ CORRECT
int mod = ((a % MOD) + MOD) % MOD;
```

---

## 🚀 TIME COMPLEXITY QUICK REFERENCE

```java
// O(1)
arr[i], map.get(key), set.contains(x)

// O(log n)
Binary search, TreeMap/TreeSet operations

// O(n)
Single loop, linear search, ArrayList operations

// O(n log n)
Sorting: Arrays.sort(), Collections.sort()

// O(n²)
Nested loops

// O(2ⁿ)
All subsets, exponential recursion

// O(n!)
All permutations
```

---

## 📏 COMMON LIMITS

```java
// Integer types
int:          -2,147,483,648 to 2,147,483,647  (±2×10⁹)
long:         -9×10¹⁸ to 9×10¹⁸
Integer.MAX_VALUE:  2,147,483,647
Integer.MIN_VALUE:  -2,147,483,648
Long.MAX_VALUE:     9,223,372,036,854,775,807

// Safe operations
10⁶ operations:     Usually safe
10⁷ operations:     Might be tight
10⁸ operations:     Risky
10⁹ operations:     Usually TLE
```

---

**Happy Coding! ☕**
