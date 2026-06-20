# ncdu vs NcduUI: scan & aggregation architecture

Deep comparison of the reference ncdu implementation (`reference/ncdu/`) and NcduUI (`NcduUI/DiskScanner.swift`, `FileNode.swift`), with analysis of why aggregation currently uses ~100% CPU on an 18-core machine, and concrete recommendations.

---

## Executive summary

| | ncdu | NcduUI (today) |
|---|---|---|
| **Scan model** | Single-threaded DFS | Parallel work-queue over directories |
| **Aggregation** | **Inline**, per file, during scan | **Separate pass**, after scan completes |
| **Aggregation CPU** | Same thread as scan (~1 core) | **Dedicated single-threaded pass** (~1 core) |
| **Visible “freeze”** | Never — totals update live | “Aggregating sizes…” with no path updates |
| **Hard-link accounting** | `hlink_check()` at insert time | Same algorithm, replayed over full tree |
| **Memory per node** | One `malloc`, intrusive list | Swift class + `Array` + 2× `String` + `UUID` |

**Root cause of the screenshot (~100% CPU, stuck at “Aggregating sizes…”):** the parallel scan finishes, then NcduUI runs a **second, fully sequential** traversal over all ~1.7M nodes. That phase never uses more than one core. ncdu never has this phase — directory totals are already correct when the last file is read.

---

## Pipeline comparison

### ncdu: streaming input → output

```
dir_scan_init()
    └─ dir_process()                    [single thread]
           ├─ dir_read(".")             read all names in current dir into buffer
           ├─ dir_walk(names)
           │     └─ dir_scan_item(name)
           │           ├─ lstat / filters
           │           └─ dir_output.item()  ──► dir_mem.c::item()
           │                    ├─ malloc + link into tree
           │                    ├─ addparentstats()   ◄── aggregation HERE
           │                    ├─ hlink_check()      ◄── hard links HERE
           │                    └─ propagate FF_SERR
           └─ dir_output.final()
```

Key property: **scan and aggregate are one loop**. When ncdu prints “Scanning…”, `dir_output.size` and `dir_output.items` already reflect fully rolled-up directory totals.

Relevant files:
- `reference/ncdu/src/dir_scan.c` — filesystem walk (input)
- `reference/ncdu/src/dir_mem.c` — tree build + per-item accounting (output)
- `reference/ncdu/src/util.c` — `addparentstats()`

### NcduUI: parallel scan, then sequential aggregate

```
performScan()
    ├─ walk()                           [N worker threads, N = activeProcessorCount]
    │     └─ readDirectory() per dir
    │           ├─ opendir / readdir / lstat (absolute paths)
    │           ├─ append FileNode to parent.children
    │           └─ flushProgress()      (own sizes only, no rollup)
    │
    └─ aggregate()                      [ONE thread, after walk() returns]
          ├─ stack DFS over entire tree again
          ├─ addParentStats() per node
          └─ hlinkCheck() per hard-link candidate
```

Key property: **two full passes** over the tree. The second pass is what the UI labels “Aggregating sizes…”.

Relevant files:
- `NcduUI/DiskScanner.swift` — `walk()`, `readDirectory()`, `aggregate()`
- `NcduUI/FileNode.swift` — in-memory tree

---

## Phase-by-phase comparison

### 1. Directory traversal

| Aspect | ncdu (`dir_scan.c`) | NcduUI (`DiskScanner.swift`) |
|---|---|---|
| **Concurrency** | 1 thread | `activeProcessorCount` workers (18 on your Mac) |
| **Navigation** | `chdir(name)` + relative `lstat` | Absolute paths: `path + "/" + name` |
| **Directory read** | `dir_read()`: slurp all entries into one buffer, `closedir`, then walk buffer | Streaming `readdir` loop per directory |
| **Descriptor budget** | At most 1 `DIR*` open (per thread) | At most 1 `DIR*` per worker (~18) |
| **Recursion** | Implicit via `chdir` stack | Explicit work queue of `(node, path)` pairs |
| **Ordering** | Depth-first, deterministic | Nondeterministic across workers (stack + races) |

**ncdu rationale for `dir_read()` first:** avoid holding many directory descriptors open in deep trees (`dir_scan.c` comment lines 150–152). NcduUI achieves the same bound per worker but parallelizes across workers.

**NcduUI win:** parallel `lstat`/`readdir` on APFS/SSD — metadata I/O can overlap across cores during the **scan** phase.

**NcduUI cost:** every child path is built as a new Swift `String` (`path + "/" + name`). For 1.7M files that is a lot of allocation traffic ncdu avoids (relative names only, one reusable `dir_curpath` buffer).

---

### 2. Tree structure

#### ncdu `struct dir` (`global.h`)

```c
struct dir {
  int64_t size, asize;      // aggregate (updated incrementally)
  uint64_t ino, dev;
  struct dir *parent, *next, *prev, *sub, *hlnk;
  int items;
  unsigned short flags;
  char name[];              // flexible array, inline with struct
};
```

- Children: singly linked list (`sub` → `next`)
- Siblings: doubly linked (`prev` / `next`)
- One `malloc` per node (`dir_memsize(name)`)
- No per-node UUID, no stored absolute path
- `size` / `asize` start as own values, become aggregates as children are inserted

#### NcduUI `FileNode`

```swift
final class FileNode {
    let id = UUID()
    let name: String
    let path: String          // absolute, stored at creation
    var size, asize: Int64    // start as ownSize; aggregated in pass 2
    var ownSize, ownASize: Int64
    var children: [FileNode] // Swift Array (heap buffer + refcount)
    unowned(unsafe) var parent: FileNode?
    unowned(unsafe) var hlnk: FileNode?
    // + dev, ino, nlink, mode, mtime, flags, kind, symlinkTarget...
}
```

| | ncdu | NcduUI |
|---|---|---|
| Nodes for 1.7M scan | ~1.7M small C structs | ~1.7M ObjC/Swift heap objects |
| Child storage | Intrusive linked list | `Array` (reallocation on growth) |
| Path storage | Reconstructed via `getpath()` when needed | `let path: String` per node (duplicate UTF-8) |
| Identity | Pointer | `UUID` + `ObjectIdentifier` |
| Cache behaviour | Sequential access, good locality per dir | Random access across workers; pointer chasing |

**Rough memory impact (order of magnitude):** NcduUI likely uses **3–5× more RAM** than ncdu for the same tree, which matters at 1.7M nodes and makes the second pass slower (more cache misses).

---

### 3. Aggregation (the critical difference)

#### ncdu: incremental, zero extra pass

On every `dir_output.item()` (`dir_mem.c`):

```c
if (item->flags & FF_HLNKC) {
    addparentstats(item->parent, 0, 0, 0, 1);  // count item only
    hlink_check(item);                          // size via hlnk list
} else {
    addparentstats(item->parent, item->size, item->asize, mtime, 1);
}
```

`addparentstats` (`util.c`):

```c
void addparentstats(struct dir *d, int64_t size, int64_t asize, uint64_t mtime, int items) {
  while (d) {
    d->size = adds64(d->size, size);
    d->asize = adds64(d->asize, asize);
    d->items += items;
    d = d->parent;
  }
}
```

`hlink_check` uses a circular `hlnk` list and **stops walking ancestors** as soon as a covering sibling link is found (`i && par` guards in `dir_mem.c` lines 79–89).

**Work per file:** O(depth) parent-pointer walks, executed once, on the scan thread.

**CPU profile:** ~100% of one core for the entire operation (scan + aggregate combined). ncdu never tries to use 1200% because it is intentionally single-threaded.

#### NcduUI: deferred batch aggregation

During `readDirectory()`:
- `FileNode.size` / `asize` are set to **own** values only (`makeNode`)
- No parent rollup

After **all** workers finish `walk()`:
- `aggregate()` DFS-es the entire tree again
- For each of ~1.7M nodes: walk parent chain (`addParentStats`) and possibly `hlinkCheck`

**Work per file:** same O(depth) parent walks as ncdu, but:
1. Done in a **second** pass (2× tree touch)
2. Done on **one thread** (screenshot: 100% CPU)
3. On Swift objects with worse locality than ncdu's contiguous structs
4. `hlinkCheck` still runs the circular-list algorithm (now correct after the port), but over the full deferred tree

**Why it feels “forever”:** at 1.7M items × ~15–30 depth × Swift indirection, the aggregate pass can take minutes on CoreSimulator trees with heavy hard-link fan-out — while the UI shows a frozen counter and one busy core.

---

### 4. Hard-link handling

Both implementations share the same *algorithm* (circular `hlnk` list + early ancestor termination). The difference is **when** it runs:

| | ncdu | NcduUI |
|---|---|---|
| **When** | Immediately on `item()` | In `aggregate()` after full scan |
| **Inode table** | `khashl` hash set (`hl_t *links`) | `Dictionary<InodeKey, FileNode>` |
| **Thread safety** | Single-threaded — no locks | Must be single-threaded in aggregate pass |
| **Parallel scan interaction** | N/A | Cannot run during parallel scan without sync |

ncdu's own comment in `hlink_check`: *"This may not be the most efficient algorithm"* — but it runs **once per file at insert time** on fast C pointers. NcduUI replays it over the entire tree in a slower language/runtime.

---

### 5. Progress & UI

| | ncdu | NcduUI |
|---|---|---|
| **Phases** | One: “Scanning…” | Two: “Scanning…” → “Aggregating sizes…” |
| **Live totals** | `dir_output.size` is always final rollup | `totalSize` during scan is sum of **own** sizes only |
| **Current path** | `dir_curpath` updated per item | `currentPath` updated during scan; cleared during aggregate |
| **Main-thread updates** | ncurses redraw on timer | `ScanProgressRelay` → `@MainActor` |

The second phase is unique to NcduUI and is what your screenshot shows.

---

### 6. CPU utilisation: why ~100% not ~1200%?

Your Activity Monitor screenshot during **aggregation**:

```
NcduUI   100.8% CPU   6 threads
```

Explanation:

1. **`aggregate()` is strictly single-threaded.** It runs on the same GCD worker that called `performScan`, after `group.wait()` returns. No parallelism.

2. **The parallel scan phase already finished.** The UI switched to “Aggregating sizes…”, so worker pool is idle.

3. **6 threads ≠ 6 busy cores.** Likely: 1 hot aggregation thread + main thread + progress relay + Swift runtime/GC + system helpers. Only one does real CPU work.

4. **ncdu also uses ~100% CPU** — but for the *whole* job, not a surprise second act. NcduUI uses many cores during scan, then collapses to one core for the long tail.

```
NcduUI CPU timeline (conceptual):

Scan:        ████████████████░░░░  (multi-core, I/O + CPU mixed)
Aggregate:   ████████████████████  (single core, CPU-bound)  ← screenshot
Cleanup:     ██░░░░░░░░░░░░░░░░░░  (background, TreeLock)
```

---

## Why NcduUI diverged from ncdu

The parallel `walk()` was added for APFS/SSD throughput: multiple directories can be `readdir`/`lstat`'d concurrently. ncdu's single-threaded `chdir` walk cannot do that.

The split happened because **incremental aggregation requires updating shared parent nodes** while workers are still scanning sibling/parent directories. That needs either:

- locking on every `addParentStats` (ancestor chain locks → serialization), or
- deferring aggregation (current approach).

NcduUI chose deferral for scan parallelism. The cost is the second pass and single-core aggregation.

---

## Recommendations (ordered by impact)

### 1. Eliminate the separate aggregation pass (highest impact)

**Goal:** match ncdu's “aggregate on insert” model.

**Option A — Single-threaded scan like ncdu (simplest, surprisingly viable)**

Revert to one scan thread with incremental `addParentStats` / `hlinkCheck` on each `lstat`, ncdu-style. Lose parallel directory walk; gain zero aggregate pass.

- Pros: 1:1 ncdu semantics, no freeze, simpler code, lower memory churn
- Cons: scan phase may be slower on some volumes (but **total time** may still beat scan+aggregate today)
- When to try: CoreSimulator-style trees where aggregate pass dominates

**Option B — Incremental aggregation with fine-grained atomics (best long-term)**

Keep parallel `readDirectory`, but after each file:

```swift
// size/items: atomic add on each ancestor
// OR lock only the direct parent chain (short critical section)
addParentStats(node.parent, ...)
hlinkCheck(node)  // needs global inode table behind a lock
```

- `size`, `asize`, `items` on `FileNode` → `ManagedAtomic<Int64>` (or a lock per node)
- `hlinkCheck` → single `NSLock` around inode hash + hlnk list mutation (fast: only `FF_HLNKC` files)
- Remove `aggregate()` entirely

Expected result: no second phase, multi-core scan stays, aggregate work spread across workers.

**Option C — Two-phase rollup without full replay**

1. Parallel scan: store only `ownSize` (current)
2. Parallel **bottom-up** per-subtree rollup: when a worker finishes a directory's children, roll child totals into that directory (post-order). Hard links handled in a final small single-threaded pass over `FF_HLNKC` nodes only.

Expected result: aggregation mostly parallel; hard-link fixup on a much smaller set.

---

### 2. Reduce per-node overhead (medium impact)

| Change | Rationale |
|---|---|
| Drop `UUID` from `FileNode` | Not needed for tree identity; `ObjectIdentifier` suffices |
| Store `path` lazily or only for UI-selected nodes | ncdu reconstructs paths; 1.7M strings is expensive |
| Use `ContiguousArray` / pre-sized child buffers | Avoid `Array` growth copies during scan |
| Arena allocator / struct nodes | Match ncdu's one-allocation-per-node pattern |
| Relative names + worker-local path buffer | Avoid `path + "/" + name` per entry |

At 1.7M nodes, halving per-node memory can noticeably speed **both** passes.

---

### 3. Faster directory I/O (medium impact, scan phase)

| Technique | Notes |
|---|---|
| `getattrlistbulk` / `readdir` batching (macOS) | Fewer syscall transitions per entry |
| `fts_open` / `nftw` with single-thread | Baseline comparison |
| Skip `readSymlink` during scan | Defer to inspector on demand |
| `hasCacheDirTag` | Currently `fopen` per candidate dir — expensive; cache or skip during parallel scan |

---

### 4. Parallel aggregation (hard, lower priority)

Tree aggregation is inherently sequential along parent edges. True multi-core rollup requires:

- **Subtree ownership:** each worker owns disjoint subtrees, rolls up locally, then merges at boundaries (complex with hard links)
- **Atomic parent updates:** `fetch_add` on `size`/`items` per ancestor (simple, works for non-hard-link portion)

Hard links break naive parallel rollup — keep `hlinkCheck` centralized or run as a final correction pass.

---

### 5. UI / perceived performance (quick win)

Even before architectural changes:

- Remove “Aggregating sizes…” as a separate user-visible phase by doing incremental rollup (recommendation 1)
- If a post-pass remains temporarily: run it on a **background** `Task.detached` and allow browsing with partial data (own sizes) while totals refine
- Show indeterminate progress without implying a hang

---

## Suggested target architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Parallel directory workers (N cores)                       │
│    readDirectory(dir)                                       │
│      for entry:                                             │
│        lstat → makeNode (ownSize only)                      │
│        addParentStats(parent, ...)     ← move here          │
│        hlinkCheck(node)               ← move here (locked)  │
│        enqueue subdirs                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ScanResult(root)   ← totals already correct
                              │
                              ▼
                    UI: phase = .ready   ← no aggregate phase
```

Changes required:
1. Delete `aggregate()` and `ScanProgress.Phase.aggregating`
2. Move `addParentStats` / `hlinkCheck` into `readDirectory` after each node creation
3. Add synchronization:
   - atomics for `size` / `asize` / `items` on ancestors, **or** per-node lock with short parent-chain hold
   - `NSLock` around global `linkRep` + `hlnk` mutation
4. Keep `unowned(unsafe) parent` (raw pointers) — required for hot parent walks

---

## Comparison matrix (quick reference)

| Feature | ncdu | NcduUI now | Recommended NcduUI |
|---|---|---|---|
| Scan threads | 1 | 18 | 18 |
| Aggregate threads | 1 (inline) | 1 (deferred) | 18 (inline per file) |
| Extra tree pass | No | **Yes** | No |
| Stored absolute path | No | Yes | Lazy / on demand |
| Hard-link algo | `hlink_check` | Ported `hlinkCheck` | Same, at insert time |
| Peak CPU | ~100% | ~100% scan IO-bound, then ~100% aggregate | ~N×100% during scan |
| User-visible freeze | No | **Yes** (aggregate) | No |

---

## References in this repo

| Topic | ncdu | NcduUI |
|---|---|---|
| Filesystem walk | `reference/ncdu/src/dir_scan.c` | `NcduUI/DiskScanner.swift` `walk()`, `readDirectory()` |
| Tree + per-item accounting | `reference/ncdu/src/dir_mem.c` | `DiskScanner.aggregate()` (deferred) |
| Parent rollup | `reference/ncdu/src/util.c` `addparentstats()` | `DiskScanner.addParentStats()` |
| Data model | `reference/ncdu/src/global.h` `struct dir` | `NcduUI/FileNode.swift` |
| Architecture overview | `reference/ncdu/src/dir.h` | this document |

---

## Bottom line

NcduUI is **not** slow because the hard-link math is wrong anymore — it is slow because it **does twice the work** (scan + aggregate) and the second pass is **single-threaded Swift** over **1.7M heap objects**. ncdu does neither.

The highest-leverage fix is to **merge aggregation into the scan path** the way `dir_mem.c::item()` does, using atomics or fine-grained locks so parallel workers can still update ancestor totals safely. That removes the “Aggregating sizes…” phase entirely and spreads CPU work across cores instead of leaving one core at 100% while seventeen sit idle.
