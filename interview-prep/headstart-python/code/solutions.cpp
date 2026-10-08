// Interview DSA solutions (C++17). Build & test: g++ -std=c++17 -O2 solutions.cpp -o sol && ./sol
#include <bits/stdc++.h>
using namespace std;

// ===== Problems from the screening round =====

// 1. Move zeroes to end (stable) — O(n) / O(1)
void moveZeroes(vector<int>& a) {
    int write = 0;
    for (int read = 0; read < (int)a.size(); ++read)
        if (a[read] != 0) swap(a[write++], a[read]);
}

// 2. Majority element (> n/2), -1 if none — Boyer-Moore O(n) / O(1)
int majorityElement(const vector<int>& a) {
    int cand = 0, cnt = 0;
    for (int x : a) {
        if (cnt == 0) cand = x;
        cnt += (x == cand) ? 1 : -1;
    }
    long long freq = count(a.begin(), a.end(), cand);
    return freq > (long long)a.size() / 2 ? cand : -1;
}

// 3. Odd occurrence — XOR O(n) / O(1)
int oddOccurrence(const vector<int>& a) {
    int r = 0;
    for (int x : a) r ^= x;
    return r;
}

// 4. Reverse string in place — O(n) / O(1)
void reverseString(string& s) {
    int i = 0, j = (int)s.size() - 1;
    while (i < j) swap(s[i++], s[j--]);
}

// 5. Fibonacci — naive / memo / tabulation / iterative / fast doubling
long long fibNaive(int n) { return n < 2 ? n : fibNaive(n - 1) + fibNaive(n - 2); }  // O(2^n)

long long fibMemoHelper(int n, vector<long long>& memo) {                              // O(n) / O(n)
    if (n < 2) return n;
    if (memo[n] != -1) return memo[n];
    return memo[n] = fibMemoHelper(n - 1, memo) + fibMemoHelper(n - 2, memo);
}
long long fibMemo(int n) {
    vector<long long> memo(max(n + 1, 2), -1);
    return fibMemoHelper(n, memo);
}

long long fibTab(int n) {                                                              // O(n) / O(n)
    if (n < 2) return n;
    vector<long long> dp(n + 1);
    dp[0] = 0; dp[1] = 1;
    for (int i = 2; i <= n; ++i) dp[i] = dp[i - 1] + dp[i - 2];
    return dp[n];
}

long long fibIter(int n) {                                                             // O(n) / O(1)
    long long a = 0, b = 1;
    for (int i = 0; i < n; ++i) { long long t = a + b; a = b; b = t; }
    return a;
}

pair<long long, long long> fibPair(int k) {                                            // O(log n)
    if (k == 0) return {0, 1};
    auto [a, b] = fibPair(k >> 1);
    long long c = a * (2 * b - a);
    long long d = a * a + b * b;
    return (k & 1) ? make_pair(d, c + d) : make_pair(c, d);
}
long long fibFast(int n) { return fibPair(n).first; }   // exact up to n = 92 in long long

// 6. Right-shift by 1 — O(n) / O(1)
void rightShiftByOne(vector<int>& a) {
    if (a.size() < 2) return;
    int last = a.back();
    for (int i = (int)a.size() - 1; i > 0; --i) a[i] = a[i - 1];
    a[0] = last;
}

// Follow-up: right-shift by k — reversal O(n) / O(1)
void rightShiftByK(vector<int>& a, int k) {
    int n = a.size();
    if (n == 0) return;
    k %= n;
    reverse(a.begin(), a.end());
    reverse(a.begin(), a.begin() + k);
    reverse(a.begin() + k, a.end());
}

// ===== Likely next questions, same band =====

// Two Sum — hash map O(n) / O(n)
pair<int, int> twoSum(const vector<int>& a, int target) {
    unordered_map<int, int> seen;                 // value -> index
    for (int i = 0; i < (int)a.size(); ++i) {
        auto it = seen.find(target - a[i]);
        if (it != seen.end()) return {it->second, i};
        seen[a[i]] = i;
    }
    return {-1, -1};
}

// Kadane — max subarray sum O(n) / O(1)
long long maxSubarray(const vector<int>& a) {
    long long best = a[0], cur = a[0];
    for (int i = 1; i < (int)a.size(); ++i) {
        cur = max<long long>(a[i], cur + a[i]);    // extend or restart
        best = max(best, cur);
    }
    return best;
}

// Remove duplicates from sorted array in place, return new length — O(n) / O(1)
int removeDuplicates(vector<int>& a) {
    if (a.empty()) return 0;
    int w = 1;
    for (int r = 1; r < (int)a.size(); ++r)
        if (a[r] != a[w - 1]) a[w++] = a[r];
    return w;
}

// Second largest distinct element, -1 if none — one pass O(n) / O(1)
int secondLargest(const vector<int>& a) {
    int first = INT_MIN, second = INT_MIN;
    for (int x : a) {
        if (x > first) { second = first; first = x; }
        else if (x > second && x != first) second = x;
    }
    return second == INT_MIN ? -1 : second;
}

// Valid parentheses — stack O(n) / O(n)
bool isValid(const string& s) {
    stack<char> st;
    for (char c : s) {
        if (c == '(' || c == '[' || c == '{') st.push(c);
        else {
            if (st.empty()) return false;
            char o = st.top(); st.pop();
            if ((c == ')' && o != '(') || (c == ']' && o != '[') || (c == '}' && o != '{')) return false;
        }
    }
    return st.empty();
}

// Anagram — 26-count array O(n) / O(1)
bool isAnagram(const string& s, const string& t) {
    if (s.size() != t.size()) return false;
    array<int, 26> cnt{};
    for (int i = 0; i < (int)s.size(); ++i) { cnt[s[i] - 'a']++; cnt[t[i] - 'a']--; }
    for (int c : cnt) if (c) return false;
    return true;
}

int main() {
    vector<int> v{1, 2, 0, 4, 3, 0, 5, 0};
    moveZeroes(v);
    assert((v == vector<int>{1, 2, 4, 3, 5, 0, 0, 0}));
    assert(majorityElement({3, 1, 3, 3, 2}) == 3);
    assert(majorityElement({1, 2, 3}) == -1);
    assert(majorityElement({1, 1, 2, 2}) == -1);
    assert(oddOccurrence({1, 2, 3, 2, 3, 1, 3}) == 3);
    string s = "Geeks"; reverseString(s); assert(s == "skeeG");
    for (int n = 0; n < 25; ++n) {
        long long e = fibNaive(n);
        assert(fibMemo(n) == e && fibTab(n) == e && fibIter(n) == e && fibFast(n) == e);
    }
    assert(fibFast(90) == 2880067194370816120LL && fibIter(90) == fibFast(90));
    vector<int> r{1, 2, 3, 4, 5}; rightShiftByOne(r);
    assert((r == vector<int>{5, 1, 2, 3, 4}));
    vector<int> k{1, 2, 3, 4, 5}; rightShiftByK(k, 2);
    assert((k == vector<int>{4, 5, 1, 2, 3}));

    assert((twoSum({2, 7, 11, 15}, 9) == make_pair(0, 1)));
    assert(maxSubarray({-2, 1, -3, 4, -1, 2, 1, -5, 4}) == 6);
    assert(maxSubarray({-3, -1, -2}) == -1);
    vector<int> d{1, 1, 2, 2, 2, 3}; assert(removeDuplicates(d) == 3);
    assert(secondLargest({12, 35, 1, 10, 34, 1}) == 34);
    assert(secondLargest({10, 10}) == -1);
    assert(isValid("{[()]}") && !isValid("(]") && !isValid("(("));
    assert(isAnagram("listen", "silent") && !isAnagram("rat", "car"));
    cout << "All C++ tests passed\n";
}
