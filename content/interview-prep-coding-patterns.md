---
title: "Interview Prep — Part 6: Coding Patterns"
description: "The 19 recurring patterns behind most coding-interview questions: sliding window, two pointers, tree BFS/DFS, backtracking, topological sort, Dijkstra, and more, with corrected Python examples."
nodate: true
hidemeta: true
nofeed: true
---

Part 6 of 6 · [Interview Prep](/interview-prep/) · ← Previous: [Part 5 — Advanced SQL](/interview-prep-sql-advanced/)

Most coding-interview questions aren't novel, they're a known pattern wearing a different story. Once you can name the pattern, the algorithm mostly writes itself. This part walks through the 19 patterns that cover the large majority of what shows up, each with how to recognize it and a clean, correct reference implementation in Python.

## XIX. Array, String & Pointer Patterns

#### 208 — Sliding Window: how do you recognize it, and what does the template look like?
The problem hands you a linear structure (array, string, linked list) and asks for the longest/shortest/best-value contiguous subarray or substring. Instead of recomputing a sum or count from scratch for every window, you slide a window's edges one step at a time and update the running result incrementally. A fixed-size window (like a max-sum-of-k-elements problem) just shifts both edges together; a variable-size window (like longest-substring-without-repeats) grows the right edge until a constraint breaks, then shrinks the left edge until it's satisfied again.

```python
def longest_substring_without_repeats(s: str) -> int:
    seen = set()
    left = best = 0
    for right, ch in enumerate(s):
        while ch in seen:
            seen.remove(s[left])
            left += 1
        seen.add(ch)
        best = max(best, right - left + 1)
    return best
```

The key cost you're avoiding: a naive approach re-scans the window from scratch every time it moves, O(n²) or worse. The sliding window touches each element a bounded number of times, O(n) total.

#### 209 — Two Pointers: how do you recognize it, and what does the template look like?
The input is sorted (or can cheaply be sorted), and you're looking for a pair, triplet, or subarray that satisfies some sum or comparison constraint. Two pointers start at opposite ends (or one behind the other) and move inward based on how the current pair compares to the target, so you never have to check every pair explicitly.

```python
def two_sum_sorted(nums: list[int], target: int) -> tuple[int, int] | None:
    left, right = 0, len(nums) - 1
    while left < right:
        total = nums[left] + nums[right]
        if total == target:
            return left, right
        if total < target:
            left += 1
        else:
            right -= 1
    return None
```

This turns an O(n²) pairwise check into O(n), the sortedness is what lets each pointer move monotonically in one direction without missing a valid pair.

#### 210 — Fast & Slow Pointers: how do you recognize it, and what does the template look like?
Also called the tortoise-and-hare technique. The problem involves a linked list or an implicitly cyclic sequence, and you need to detect a cycle, find a cycle's start, find the middle of a list in one pass, or check for a palindrome without extra memory. Two pointers move through the same structure at different speeds (typically 1x and 2x); if there's a cycle, the fast pointer is guaranteed to lap the slow one and they meet.

```python
def has_cycle(head) -> bool:
    slow = fast = head
    while fast and fast.next:
        slow = slow.next
        fast = fast.next.next
        if slow is fast:
            return True
    return False
```

The same fast/slow split (find the middle, then walk from there) is also how you solve "find the middle of a linked list" and "check if a linked list is a palindrome" in O(1) space instead of copying the list into an array first.

#### 211 — Merge Intervals: how do you recognize it, and what does the template look like?
The problem talks about "overlapping intervals": merging a set of ranges, inserting a new one, or finding the intersection between two sorted lists of ranges. Two intervals `[a_start, a_end]` and `[b_start, b_end]` overlap exactly when `a_start <= b_end and b_start <= a_end`; once sorted by start time, you only ever need to compare each interval to the last one you've already placed.

```python
def merge_intervals(intervals: list[list[int]]) -> list[list[int]]:
    intervals.sort(key=lambda iv: iv[0])
    merged = [intervals[0]]
    for start, end in intervals[1:]:
        if start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged
```

Sorting costs O(n log n) and dominates the total; the merge pass itself is a single O(n) sweep.

#### 212 — Cyclic Sort: how do you recognize it, and what does the template look like?
The array holds `n` (or close to `n`) numbers drawn from a known, bounded range, typically `1..n`, and you're asked to find a missing, duplicate, or out-of-place number. Instead of sorting generically, you place each number directly at its "correct" index (`value - 1`) by swapping, which sorts the array in one O(n) pass because every number has exactly one home.

```python
def find_missing_number(nums: list[int]) -> int:
    i, n = 0, len(nums)
    while i < n:
        correct = nums[i]
        if correct < n and nums[i] != nums[correct]:
            nums[i], nums[correct] = nums[correct], nums[i]
        else:
            i += 1
    for i in range(n):
        if nums[i] != i:
            return i
    return n
```

Once the cyclic sort pass finishes, any index whose value doesn't match the index itself points straight at the missing or duplicated number, no hash set required.

#### 213 — Modified Binary Search: how do you recognize it, and what does the template look like?
Anything sorted, or sorted-then-rotated, is a candidate: finding a target, finding an insertion point, or finding the minimum in a rotated array. The core move beyond textbook binary search is figuring out, at each step, which half of the current range is still properly sorted, then checking whether the target could be in that half.

```python
def find_min_in_rotated(nums: list[int]) -> int:
    left, right = 0, len(nums) - 1
    while left < right:
        mid = left + (right - left) // 2
        if nums[mid] > nums[right]:
            left = mid + 1
        else:
            right = mid
    return nums[left]
```

Computing `mid` as `left + (right - left) // 2` instead of `(left + right) // 2` avoids integer overflow in languages with fixed-width integers; it doesn't matter in Python, but it's the version worth having memorized since it's correct everywhere.

#### 214 — Top K Elements: how do you recognize it, and what does the template look like?
The problem asks for the top, smallest, or most frequent `k` elements of a set. A heap of size `k` tracks exactly the candidates that matter: for the k largest, keep a min-heap of size `k` so the smallest of your current top-k sits at the top, ready to be evicted the moment something bigger shows up.

```python
import heapq

def kth_largest(nums: list[int], k: int) -> int:
    heap = nums[:k]
    heapq.heapify(heap)
    for num in nums[k:]:
        if num > heap[0]:
            heapq.heapreplace(heap, num)
    return heap[0]
```

This runs in O(n log k) instead of the O(n log n) a full sort would cost, the win grows as `k` gets small relative to `n`.

#### 215 — K-way Merge: how do you recognize it, and what does the template look like?
You're given `k` sorted lists (or a matrix with sorted rows) and need a single sorted traversal, merge, or the smallest element across all of them. Push the first element of each list into a min-heap, keyed by value; every time you pop the overall minimum, push the next element from that same list.

```python
import heapq

def merge_k_sorted_lists(lists: list[list[int]]) -> list[int]:
    heap = [(lst[0], i, 0) for i, lst in enumerate(lists) if lst]
    heapq.heapify(heap)
    merged = []
    while heap:
        val, list_idx, elem_idx = heapq.heappop(heap)
        merged.append(val)
        if elem_idx + 1 < len(lists[list_idx]):
            heapq.heappush(heap, (lists[list_idx][elem_idx + 1], list_idx, elem_idx + 1))
    return merged
```

Total work is O(n log k) where `n` is the total element count across all lists, the heap never holds more than `k` elements at once, one per list.

#### 216 — Monotonic Stack: how do you recognize it, and what does the template look like?
The problem is a "range query" over an array: next greater element, daily temperatures, largest rectangle in a histogram. A monotonic stack keeps its elements in strictly increasing (or decreasing) order by popping anything that violates that order before pushing the new element, so once something is popped, you know exactly what popped it, that's usually the answer for it.

```python
def next_greater_elements(nums: list[int]) -> list[int]:
    result = [-1] * len(nums)
    stack = []  # indices, values kept decreasing
    for i, num in enumerate(nums):
        while stack and nums[stack[-1]] < num:
            result[stack.pop()] = num
        stack.append(i)
    return result
```

Each element is pushed once and popped at most once, so the whole pass is O(n) even though there's a `while` loop nested inside the `for`.

#### 217 — Prefix Sum: how do you recognize it, and what does the template look like?
The problem asks for the sum (or count, or XOR) of many different subarrays, often phrased as "how many subarrays sum to k." Precompute a running prefix sum once, and the sum of any subarray `[i, j]` becomes a single subtraction, `prefix[j+1] - prefix[i]`, instead of re-summing that range every time.

```python
def subarray_sum_equals_k(nums: list[int], k: int) -> int:
    count = 0
    running_sum = 0
    seen = {0: 1}  # prefix sum -> how many times it's occurred
    for num in nums:
        running_sum += num
        count += seen.get(running_sum - k, 0)
        seen[running_sum] = seen.get(running_sum, 0) + 1
    return count
```

The hash-map variant above turns "how many subarrays sum to k" into O(n): for every prefix sum you've seen, you're really asking "has `running_sum - k` shown up before," which is an O(1) lookup instead of an O(n) inner loop.

## XX. Tree, Graph, Backtracking & DP Patterns

#### 218 — In-place Reversal of a Linked List: how do you recognize it, and what does the template look like?
You need to reverse a linked list, or a sub-range of one, without allocating a second list. Walk the list once, and at each node, flip its `next` pointer to point backward at the node you just came from, tracking the previous node as you go.

```python
def reverse_list(head):
    prev = None
    node = head
    while node:
        next_node = node.next
        node.next = prev
        prev = node
        node = next_node
    return prev
```

Reversing a sub-range `[left, right]` is the same loop, just started after walking to position `left` first, then splicing the reversed segment back into the untouched parts on either side.

#### 219 — Tree BFS: how do you recognize it, and what does the template look like?
The problem needs a level-by-level view of a tree: level-order traversal, zigzag traversal, or "the minimum depth to reach a leaf." A queue holds exactly one level's worth of nodes at a time; draining the queue by its current length (captured before the loop starts) is what separates one level's processing from the next.

```python
from collections import deque

def level_order(root) -> list[list[int]]:
    if not root:
        return []
    result = []
    queue = deque([root])
    while queue:
        level = []
        for _ in range(len(queue)):
            node = queue.popleft()
            level.append(node.val)
            if node.left:
                queue.append(node.left)
            if node.right:
                queue.append(node.right)
        result.append(level)
    return result
```

That `for _ in range(len(queue))` is the whole trick: it freezes "how many nodes are in this level" before the loop starts appending next-level nodes into the same queue.

#### 220 — Tree DFS: how do you recognize it, and what does the template look like?
The problem needs a root-to-leaf path, a path sum, or an ordered (pre/in/post-order) traversal, anything where you want to go deep before you go wide. Recursion tracks the path implicitly through the call stack; the choice of pre-order, in-order, or post-order is just where you place the "process this node" step relative to the two recursive calls.

```python
def has_path_sum(root, target: int) -> bool:
    if not root:
        return False
    if not root.left and not root.right:
        return root.val == target
    remaining = target - root.val
    return (has_path_sum(root.left, remaining)
            or has_path_sum(root.right, remaining))
```

Every DFS variant, this one included, is O(n) time since it visits each node once, and O(h) space for the call stack, where `h` is the tree's height: O(log n) for a balanced tree, O(n) in the worst case of a completely skewed one.

#### 221 — Two Heaps: how do you recognize it, and what does the template look like?
The problem needs the median (or some smallest/largest split point) of a stream of numbers as they arrive, not just once at the end. Keep a max-heap for the lower half of the numbers seen so far and a min-heap for the upper half, and rebalance after every insert so the two heaps never differ in size by more than one; the median is then always at the top of one heap, or the average of both tops.

```python
import heapq

class MedianFinder:
    def __init__(self):
        self.small = []  # max-heap, stored as negatives
        self.large = []  # min-heap

    def add_number(self, num: int) -> None:
        heapq.heappush(self.small, -num)
        heapq.heappush(self.large, -heapq.heappop(self.small))
        if len(self.large) > len(self.small):
            heapq.heappush(self.small, -heapq.heappop(self.large))

    def find_median(self) -> float:
        if len(self.small) > len(self.large):
            return -self.small[0]
        return (-self.small[0] + self.large[0]) / 2
```

Pushing into one heap and immediately moving its top into the other is what keeps both heaps balanced without a separate comparison step, each insert is O(log n), and the median is always an O(1) read.

#### 222 — Subsets (Backtracking): how do you recognize it, and what does the template look like?
The problem wants every subset, permutation, or combination satisfying some constraint, and the phrase "find all" is the giveaway. Backtracking builds a partial solution one choice at a time, recurses, then undoes ("un-chooses") that step before trying the next option, so the same mutable list can represent every path down the decision tree.

```python
def backtrack(path: list, choices: list, result: list) -> None:
    if is_complete(path, choices):
        result.append(path.copy())
        return
    for choice in remaining_choices(path, choices):
        path.append(choice)
        backtrack(path, choices, result)
        path.pop()  # undo, so the next choice starts clean
```

```python
def subsets(nums: list[int]) -> list[list[int]]:
    result = []
    def backtrack(start: int, path: list[int]) -> None:
        result.append(path.copy())
        for i in range(start, len(nums)):
            path.append(nums[i])
            backtrack(i + 1, path)
            path.pop()
    backtrack(0, [])
    return result
```

The runtime is inherently exponential, O(2^n) for subsets, since that's how many subsets exist; backtracking's job is to generate exactly that many, not fewer, but without wasted work re-deriving each one from scratch.

#### 223 — Topological Sort: how do you recognize it, and what does the template look like?
The problem describes dependencies between items, course prerequisites, build steps, task scheduling, and asks for a valid order, or whether one exists at all. Track each node's in-degree (how many things must happen before it); repeatedly peel off nodes with zero remaining in-degree, and decrement their neighbors' in-degrees as you go.

```python
from collections import deque, defaultdict

def can_finish(num_courses: int, prerequisites: list[list[int]]) -> bool:
    graph = defaultdict(list)
    in_degree = [0] * num_courses
    for course, pre in prerequisites:
        graph[pre].append(course)
        in_degree[course] += 1

    queue = deque(c for c in range(num_courses) if in_degree[c] == 0)
    visited = 0
    while queue:
        node = queue.popleft()
        visited += 1
        for neighbor in graph[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)
    return visited == num_courses
```

If `visited` never reaches every node, some subset of nodes has a circular dependency on each other and can never reach in-degree zero, that's how this same code doubles as cycle detection.

#### 224 — Union-Find (Disjoint Set Union): how do you recognize it, and what does the template look like?
The problem asks whether two elements are connected, directly or through a chain of other connections, or wants you to count connected components, or detect a cycle in an undirected graph. Each element starts as its own parent; `union` merges two components by pointing one's root at the other's, and `find` walks up to a component's root, compressing the path along the way so future lookups are faster.

```python
class DSU:
    def __init__(self, n: int):
        self.parent = list(range(n))
        self.rank = [0] * n

    def find(self, x: int) -> int:
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])  # path compression
        return self.parent[x]

    def union(self, x: int, y: int) -> bool:
        root_x, root_y = self.find(x), self.find(y)
        if root_x == root_y:
            return False  # already connected: this edge closes a cycle
        if self.rank[root_x] < self.rank[root_y]:
            root_x, root_y = root_y, root_x
        self.parent[root_y] = root_x
        if self.rank[root_x] == self.rank[root_y]:
            self.rank[root_x] += 1
        return True
```

Path compression plus union-by-rank together give near-O(1) amortized operations, formally O(α(n)), the inverse Ackermann function, which is under 5 for any `n` you'd ever encounter in practice.

#### 225 — Dijkstra's Algorithm: how do you recognize it, and what does the template look like?
The problem wants the shortest path (or cost) from a source to every other node in a graph with non-negative edge weights. Think of it as a greedy BFS: always expand the unvisited node with the smallest known distance so far, since once you've settled on the shortest path to a node, no longer path through a still-unvisited node could ever beat it.

```python
import heapq
from collections import defaultdict

def dijkstra(n: int, edges: list[tuple[int, int, int]], src: int) -> list[float]:
    graph = defaultdict(list)
    for u, v, w in edges:
        graph[u].append((v, w))

    dist = [float("inf")] * n
    dist[src] = 0
    heap = [(0, src)]
    while heap:
        d, node = heapq.heappop(heap)
        if d > dist[node]:
            continue  # a shorter path to `node` was already found
        for neighbor, weight in graph[node]:
            new_dist = d + weight
            if new_dist < dist[neighbor]:
                dist[neighbor] = new_dist
                heapq.heappush(heap, (new_dist, neighbor))
    return dist
```

Runs in O(E log V) with a binary heap. It breaks the moment an edge weight goes negative, a shorter path could then appear through a node you'd already "settled," which is exactly the case Bellman-Ford handles instead.

#### 226 — Subsequence DP: how do you recognize it, and what does the template look like?
The problem asks for a longest or shortest subsequence (not necessarily contiguous, unlike a subarray), across one string or two. The number of possible subsequences is exponential, so the fact that you need one at all is the signal to reach for dynamic programming: define what a subproblem's answer means precisely, then find how it's built from smaller subproblems. For one sequence (Longest Increasing Subsequence), `dp[i]` is the LIS ending exactly at index `i`:

```python
def length_of_lis(nums: list[int]) -> int:
    dp = [1] * len(nums)
    for i in range(len(nums)):
        for j in range(i):
            if nums[j] < nums[i]:
                dp[i] = max(dp[i], dp[j] + 1)
    return max(dp) if dp else 0
```

For two sequences (Longest Common Subsequence), `dp[i][j]` is the LCS length between `text1[i:]` and `text2[j:]`, built from the bottom right corner up:

```python
def longest_common_subsequence(text1: str, text2: str) -> int:
    dp = [[0] * (len(text2) + 1) for _ in range(len(text1) + 1)]
    for i in range(len(text1) - 1, -1, -1):
        for j in range(len(text2) - 1, -1, -1):
            if text1[i] == text2[j]:
                dp[i][j] = 1 + dp[i + 1][j + 1]
            else:
                dp[i][j] = max(dp[i][j + 1], dp[i + 1][j])
    return dp[0][0]
```

Both run in O(n²) (or O(n·m) for the two-string case): every cell in the DP table is filled once, in O(1), from cells already computed.

## Notes

**[XIX. Array, string & pointer patterns](#xix-array-string--pointer-patterns):** these are the patterns most likely to show up in a phone screen. Sliding window (208) and two pointers (209) alone cover a huge fraction of "easy" and "medium" problems, get the template reflexive enough that recognizing the pattern and writing the code happen in the same breath.

**[XX. Tree, graph, backtracking & DP patterns](#xx-tree-graph-backtracking--dp-patterns):** this is where onsite rounds live. Tree BFS/DFS (219, 220) and backtracking (222) are foundational, everything else in this section is closer to a variation on one of those three. Dijkstra (225) and topological sort (223) are the two most likely to get a "now what if the graph has a cycle" or "what if a weight is negative" follow-up, know the failure mode, not just the happy path.

---

Part 6 of 6 · [Interview Prep](/interview-prep/) · ← Previous: [Part 5 — Advanced SQL](/interview-prep-sql-advanced/)
