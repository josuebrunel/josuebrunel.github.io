---
title: "Interview Prep — Part 2: Databases & System Design"
description: "Database optimization, system design fundamentals, distributed systems concepts, and system design case studies: 38 interview Q&As with diagrams."
url: "/interview-prep-databases-systems/"
aliases: ["/go-interview-prep-databases-systems/"]
nodate: true
hidemeta: true
nofeed: true
---

Part 2 of 6 · [Interview Prep](/interview-prep/) · ← Previous: [Part 1 — Go Language](/interview-prep-language/)

## IX. Databases & Database Optimization

| # | Question | Answer |
|---|----------|--------|
| 76 | What do the four ACID properties guarantee, with a concrete example of a violation? | Atomicity: a transaction is all-or-nothing — no partial writes are ever visible. Consistency: a transaction moves the DB from one valid state to another, respecting constraints/invariants. Isolation: concurrent transactions don't see each other's uncommitted intermediate state. Durability: once committed, a write survives a crash (typically via a write-ahead log flushed to disk before the commit is acknowledged). Violation example: without atomicity, a funds transfer that debits one account but crashes before crediting the other leaves money vanished. |
| 77 | Normalization vs. denormalization — what's the trade-off, and when would you denormalize? | Normalization (3NF and beyond) splits data into related tables joined by foreign keys so each fact is stored once — saves storage and avoids update anomalies, at the cost of needing joins to read. Denormalization intentionally duplicates or pre-joins data to avoid those joins at read time — cheaper reads, but risks write-time inconsistency and extra storage. Denormalize for read-heavy, write-light workloads, e.g. a precomputed "order summary" table instead of joining orders+items+users on every page load. |
| 80 | Why does column order matter in a composite (multi-column) index, and what makes an index "covering"? | A composite index on `(a, b, c)` is only useful for queries filtering on a left prefix of those columns — it serves `WHERE a = ?` and `WHERE a = ? AND b = ?`, but not `WHERE b = ?` alone. Put the most selective or most commonly-filtered-alone column first. A covering index additionally includes every column a query needs (via `INCLUDE`, or as a composite over all selected + filtered columns), so the DB can answer the query entirely from the index without touching the table — an "index-only scan." |
| 83 | What is the N+1 query problem, and how do you fix it? | It happens when code fetches N parent records with one query, then loops over them issuing one more query per record for related data — 1 + N queries where 2 would do. Classic ORM footgun: accessing a lazy-loaded association inside a loop. Fix: eager-load the association up front with a `JOIN`, or batch the follow-up lookups into a single `WHERE parent_id IN (...)` query and group the results in memory. |
| 85 | You're handed a slow production query — what do you check, in order? | (1) `EXPLAIN ANALYZE` it — is it doing a sequential scan on a large table it shouldn't be? (2) Confirm an index exists on the filtered/joined columns and its leading columns match the query. (3) Check whether it's actually N+1 queries in disguise from the calling code, not one slow query. (4) Check table statistics are fresh and the table isn't bloated (`ANALYZE`/`VACUUM` in Postgres). (5) Check the connection pool isn't saturated — queries queueing for a connection look slow even when the query itself is fine (Q75). (6) For a genuinely hot read path, reach for caching (Q91) or a read replica (Q84) before reaching for a bigger box. |

#### 78 — How does a B-tree index make lookups fast, and when does an index *not* help?
A B-tree keeps keys sorted in a balanced tree, so a lookup walks from root to leaf in O(log n) comparisons instead of scanning every row, and leaf nodes are linked in sorted order, which makes range scans (`BETWEEN`, `ORDER BY`) cheap too. Each leaf entry points back to the actual row. An index does *not* help when: the column has low cardinality/selectivity (a boolean flag on a huge table — half the table matches anyway, so the planner rightly prefers a sequential scan); the query wraps the column in a function (`WHERE LOWER(email) = ...`) without a matching expression index; the pattern has a leading wildcard (`LIKE '%foo'` can't use a plain B-tree — needs a trigram or full-text index); or the table is small enough that a full scan is simply cheaper than random index lookups.

```mermaid
graph TD
    Root["50"] --> L["10 | 30"]
    Root --> R["70 | 90"]
    L --> LL["1, 5, 8"]
    L --> LM["12, 15, 22"]
    L --> LR["35, 40, 45"]
    R --> RL["55, 60, 65"]
    R --> RR["75, 85, 99"]
    LL -.leaf link.-> LM -.leaf link.-> LR -.leaf link.-> RL -.leaf link.-> RR
```

#### 79 — How do you read a query execution plan to diagnose a slow query?
`EXPLAIN ANALYZE` actually runs the query and shows the plan the optimizer chose plus real timings. Key things to check: the scan type per node (`Seq Scan` = full table scan, `Index Scan` = uses an index then fetches the row, `Index Only Scan` = answered entirely from the index, `Bitmap Heap Scan` = combines several index matches before hitting the table); the cost estimate (startup..total, in arbitrary planner units); and — most important — estimated rows vs. actual rows. A big divergence between them means the table's statistics are stale (the planner is guessing wrong), which itself can cause it to pick a bad plan; the fix is often just `ANALYZE table_name`.

```sql
-- No index on customer_id:
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;

Seq Scan on orders  (cost=0.00..18334.00 rows=12 width=120) (actual time=0.02..142.30 rows=8 loops=1)
  Filter: (customer_id = 42)
  Rows Removed by Filter: 999992

-- After: CREATE INDEX idx_orders_customer_id ON orders(customer_id);
Index Scan using idx_orders_customer_id on orders  (cost=0.42..8.44 rows=12 width=120) (actual time=0.015..0.021 rows=8 loops=1)
  Index Cond: (customer_id = 42)
```

#### 81 — Explain the transaction isolation levels and the anomalies each one prevents.
Each stricter level prevents more of the "read" anomalies that come from concurrent transactions, at the cost of more locking/lower concurrency:

| Isolation level | Dirty read | Non-repeatable read | Phantom read |
|---|---|---|---|
| Read Uncommitted | possible | possible | possible |
| Read Committed | prevented | possible | possible |
| Repeatable Read | prevented | prevented | possible (Postgres's snapshot-based RR also prevents phantoms) |
| Serializable | prevented | prevented | prevented |

A **dirty read** sees another transaction's uncommitted write. A **non-repeatable read** re-reads the same row within one transaction and gets a different value because another transaction committed a change in between. A **phantom read** re-runs the same filtered query and sees a different *set* of rows because another transaction inserted/deleted matching rows in between. Most applications default to Read Committed; Serializable is reserved for invariants that absolutely cannot tolerate any anomaly, since it costs the most concurrency (often via retries on serialization failure).

#### 82 — Optimistic vs. pessimistic locking, and how does a deadlock happen?
Pessimistic locking acquires a lock before touching a row (`SELECT ... FOR UPDATE`) so nothing else can modify it until you're done — safe under contention, but reduces concurrency and can deadlock. Optimistic locking doesn't lock at all: read a version/timestamp column, do the work, then write conditionally on that version being unchanged (`WHERE version = read_version`), retrying on a mismatch — better throughput when contention is low, wasted work when it's high. A deadlock happens when two transactions each hold a lock the other is waiting for, in opposite order — a circular wait. The DB's deadlock detector picks a victim, rolls it back with an error, and the application must retry it. The fix is to always acquire locks on rows in a consistent, global order.

```sql
-- T1                                  -- T2
BEGIN;                                 BEGIN;
UPDATE accounts SET balance -= 10
  WHERE id = 1;                        UPDATE accounts SET balance -= 10
                                          WHERE id = 2;
UPDATE accounts SET balance += 10      UPDATE accounts SET balance += 10
  WHERE id = 2;  -- waits on T2's lock   WHERE id = 1;  -- waits on T1's lock
                                        -- circular wait -> DB kills one as deadlock victim
```

#### 84 — Explain leader-follower replication and replication lag.
Writes go to the leader (primary), which streams its change log (e.g. Postgres's WAL) to one or more followers (replicas), which apply the changes and can serve reads. This gives horizontal read scaling and a hot standby for failover. Because replication is usually asynchronous, followers apply changes with a delay — replication lag — so a read against a follower immediately after a write to the leader can return stale data. This bites hardest on "read your own write" right after an update: either route that specific read to the leader, or use synchronous replication for stronger consistency at a latency cost. See also sharding/partitioning (Q90), which splits data across nodes rather than copying all of it to each.

```mermaid
graph TD
    App[App] -->|writes| Leader[("Leader / Primary")]
    Leader -->|"WAL stream, async"| F1[("Follower 1")]
    Leader -->|"WAL stream, async"| F2[("Follower 2")]
    App -.->|"reads, may lag"| F1
    App -.->|"reads, may lag"| F2
```

---

## X. System Design Fundamentals

| # | Question | Answer |
|---|----------|--------|
| 86 | Difference between vertical and horizontal scaling, and when does horizontal stop being trivial? | Vertical scaling means a bigger machine — simple, but has a hard ceiling. Horizontal scaling means more machines sharing load, but stops being trivial the moment state enters the picture: stateless request handling scales linearly, but a stateful component needs partitioning, replication, or coordination logic. |
| 88 | Explain eventual consistency with a good-fit and bad-fit example. | Eventual consistency means replicas will converge given enough time without new writes, but reads shortly after a write might see stale data. Good fit: a "like count." Bad fit: an account balance check right before authorizing a large withdrawal. |
| 90 | Difference between horizontal and vertical partitioning (sharding) of a database? | Vertical partitioning splits a table by columns — same rows, different tables. Horizontal partitioning (sharding) splits a table by rows across multiple database instances based on a shard key — each shard holds a subset of rows but the full schema. |
| 92 | When would you choose Kafka vs RabbitMQ vs NATS? | Kafka: high-throughput, durable, replayable event log — ideal for event sourcing and stream processing. RabbitMQ: flexible routing, strong work-queue semantics with per-message ack/retry. NATS: extremely low latency, lightweight pub/sub. |
| 93 | Explain idempotency and why it matters in distributed systems. | An idempotent operation produces the same end result no matter how many times it's applied — critical because network failures mean clients can't always tell if a request succeeded, so they must be able to safely retry. |
| 94 | Synchronous vs asynchronous communication between services — tradeoffs? | Synchronous: simpler, immediate feedback, but couples the caller's availability to the callee's. Asynchronous: decouples services in time, at the cost of eventual consistency and more complex failure/retry/ordering handling. |
| 95 | Explain backpressure and why a fast producer + slow consumer needs it. | Backpressure is a mechanism for a slow consumer to signal a fast producer to slow down, preventing unbounded buffering that leads to memory exhaustion or unbounded latency growth. |

#### 87 — Explain CAP theorem with a concrete example.
Under a network partition, a distributed system must choose between Consistency (every read sees the latest write) and Availability (every request gets a response, even if possibly stale). Example choosing AP: a shopping cart service that keeps accepting writes during a partition and reconciles later. Example choosing CP: a bank ledger balance check that would rather return an error than risk showing a stale balance.

```mermaid
graph TD
    Client --> Router
    Router --> A[Replica A]
    Router --> B[Replica B]
    A -. network partition .- B
    CP["CP choice: reject write, return error until healed"]
    AP["AP choice: accept write, reconcile later"]
```

#### 89 — Explain L4 vs L7 load balancing.
L4 (transport layer) balances based on IP/port and TCP/UDP-level info without inspecting request content — fast, protocol-agnostic. L7 (application layer) understands HTTP and can route based on path, host header, or cookies — more flexible but adds processing overhead.

```mermaid
graph TD
    subgraph "L4 Load Balancer — transport layer"
    C1[Client] --> LB1["LB: IP / port only"]
    LB1 --> S1[Server 1]
    LB1 --> S2[Server 2]
    end
    subgraph "L7 Load Balancer — application layer"
    C2[Client] --> LB2["LB: inspects path / host / headers"]
    LB2 -->|"/api/v1/*"| SA[Service A]
    LB2 -->|"/api/v2/*"| SB[Service B]
    end
```

#### 91 — Explain caching strategies: cache-aside, write-through, write-behind.
Cache-aside: app checks cache first, on a miss reads from DB and populates the cache. Write-through: writes go to the cache and DB synchronously together — reads always fresh, writes slower. Write-behind: writes go to the cache immediately and are asynchronously flushed to the DB later — fastest writes, risks data loss if the cache fails before flushing.

```mermaid
graph TD
    subgraph "Cache-aside"
    App1[App] -->|"1: read, miss"| Cache1[(Cache)]
    App1 -->|"2: read"| DB1[(DB)]
    App1 -->|"3: populate"| Cache1
    end
    subgraph "Write-through"
    App2[App] -->|write| Cache2[(Cache)]
    Cache2 -->|sync write| DB2[(DB)]
    end
    subgraph "Write-behind"
    App3[App] -->|write| Cache3[(Cache)]
    Cache3 -. async flush .-> DB3[(DB)]
    end
```

---

## XI. Distributed Systems Concepts

| # | Question | Answer |
|---|----------|--------|
| 96 | Explain a distributed lock, and why plain mutexes don't work across services. | A `sync.Mutex` only coordinates goroutines within a single process's memory space. A distributed lock uses a shared external system (Redis Redlock, or etcd/Zookeeper with consensus-backed leases) so multiple independent processes can agree on mutual exclusion, typically with a lease/TTL. |
| 97 | What's leader election, and how does it typically work? | A mechanism for a group of distributed nodes to agree on exactly one "leader." Typically implemented via a consensus protocol like Raft — nodes propose themselves, a majority quorum must agree, and if the leader fails to renew its lease, a new election triggers. |
| 99 | At-most-once vs at-least-once vs exactly-once delivery — why is exactly-once mostly a myth? | At-most-once: message might be lost. At-least-once: guaranteed delivered, but possibly more than once. Exactly-once is extremely hard end-to-end; in practice, systems achieve "effectively exactly-once" by combining at-least-once delivery with idempotent processing. |
| 103 | How do clock skew and distributed time affect ordering of events across services? | Wall-clock timestamps from different machines aren't reliably comparable due to clock drift. Solutions: logical clocks (Lamport/vector clocks) that capture causal ordering, or a centralized sequencer/monotonic ID source when a single global order is required. |
| 105 | What is the thundering herd problem, and how do jitter/coalescing prevent it? | Thundering herd is when a large number of clients wake up or retry simultaneously, overwhelming a resource that was just recovering. Jittered backoff randomizes retry timing; request coalescing (single-flight) ensures only one actual request goes to the backend when many callers request the same resource. |
| 107 | What's the difference between Byzantine and crash-fault tolerance, and why do Raft/Paxos only handle the latter? | Crash-fault tolerance assumes a failed node simply stops responding — it never lies. Byzantine fault tolerance assumes a node can behave arbitrarily: send conflicting messages to different peers, claim false state, or act maliciously. Raft and Paxos only tolerate crash faults, which is why they're safe for trusted infrastructure you control (your own replica set) but insufficient for adversarial settings like blockchain consensus, which need BFT protocols (PBFT, Tendermint) instead. |
| 108 | What is the Two Generals' Problem, and what does it actually prove about distributed consensus? | Two armies must attack a city simultaneously to win, but can only coordinate via messengers who might be captured (messages that might be lost). No matter how many acknowledgments are exchanged, neither general can ever be 100% certain the other received the final ACK, so perfect agreement over an unreliable channel is provably impossible. In practice, systems don't solve this — they work around it with retries, timeouts, and idempotency, accepting a vanishingly small but nonzero risk instead of a mathematical guarantee. |
| 110 | What is a CRDT, and when would you reach for one instead of a distributed lock? | A Conflict-free Replicated Data Type is a data structure (counter, set, map) designed so that concurrent updates from different replicas can always be merged deterministically into the same final state, without coordination or locking — e.g. a grow-only counter that merges by taking the max per-replica count. Reach for one when replicas need to accept writes independently (offline-first apps, multi-region writes) and eventual convergence is good enough; skip it when you need a strict invariant a CRDT can't express, like "balance never goes negative." |
| 111 | How does a gossip protocol detect node failure in a cluster, and how does that differ from a centralized health check? | Each node periodically pings a few random peers and forwards what it's heard about others' health, so failure information spreads epidemic-style across the cluster in O(log N) rounds without a central bottleneck or single point of failure. A centralized health-check registry is simpler to reason about but doesn't scale as well and becomes a single point of failure itself; gossip (e.g. SWIM) trades a small amount of detection latency for horizontal scalability and resilience. |
| 113 | What does PACELC add to CAP theorem? | CAP only describes the tradeoff during a network partition (P). PACELC extends it: if Partitioned, choose Availability or Consistency (as in CAP) — Else, even with no partition at all, choose Latency or Consistency, since synchronously confirming a write across replicas for strong consistency always costs latency versus acknowledging locally and replicating asynchronously. It's a more complete lens for classifying real systems — e.g. DynamoDB is PA/EL, while a synchronously-replicated SQL cluster is PC/EC. |

#### 98 — Explain quorum-based consistency (N/R/W).
N is the total number of replicas; W is how many replicas must acknowledge a write before it's considered successful; R is how many replicas a read must query and reconcile before returning a result. If `R + W > N`, every read is guaranteed to overlap with the most recent write's replica set.

```mermaid
sequenceDiagram
    participant Client
    participant Coordinator
    participant R1 as Replica 1
    participant R2 as Replica 2
    participant R3 as Replica 3
    Client->>Coordinator: write
    Coordinator->>R1: write
    Coordinator->>R2: write
    Coordinator->>R3: write
    R1-->>Coordinator: ack
    R2-->>Coordinator: ack
    Note over Coordinator: N=3 replicas — W=2 acks to commit, R=2 reads, R+W>N
```

#### 100 — How would you design idempotency keys for a payment API?
Require the client to generate a unique idempotency key per logical operation and send it in the request header. The server checks a store keyed on that idempotency key — if seen before, return the previously stored result; if not, atomically claim the key before doing the actual charge.

```sql
INSERT INTO payment_requests (idempotency_key, status)
VALUES ($1, 'processing')
ON CONFLICT (idempotency_key) DO NOTHING;
-- 0 rows affected => a request with this key is already in
-- flight/done -- look up and return its stored result instead
-- of charging again.
```

#### 101 — Explain the outbox pattern for reliably publishing events after a DB write.
Instead of writing to the DB and then separately publishing to a message broker (which can fail independently), you write the business change and an "outbox" event row in the *same* database transaction. A separate poller/relay process reads unpublished outbox rows and publishes them, marking them sent.

```go
tx, _ := db.BeginTx(ctx, nil)
tx.Exec(`UPDATE accounts SET balance = balance - $1 WHERE id = $2`, amount, from)
tx.Exec(`INSERT INTO outbox (event_type, payload, published)
         VALUES ($1, $2, false)`, "FundsDebited", payload)
tx.Commit() // business change + outbox row commit atomically

// separate relay process:
// SELECT * FROM outbox WHERE published = false
// -> publish to broker -> mark published = true
```

```mermaid
graph LR
    App -->|same DB txn| Tables[("Business table +<br/>Outbox table")]
    Tables --> Relay["Relay / Poller"]
    Relay -->|publish| Broker[(Message Broker)]
    Relay -. mark published .-> Tables
```

#### 102 — What is a saga pattern, and when would you use it instead of 2PC?
A saga breaks a distributed transaction into a sequence of local transactions, each with a compensating action to undo it if a later step fails — instead of holding locks across services as two-phase commit does.

```mermaid
graph TD
    subgraph "2PC — coordinator-driven"
    Coord[Coordinator] -->|"1: prepare"| PA[Participant A]
    Coord -->|"1: prepare"| PB[Participant B]
    PA -->|vote yes| Coord
    PB -->|vote yes| Coord
    Coord -->|"2: commit"| PA
    Coord -->|"2: commit"| PB
    end
    subgraph "Saga — local txns + compensations"
    S1["Step 1: Reserve Inventory"] --> S2["Step 2: Charge Payment"]
    S2 --> S3["Step 3: Ship Order"]
    S2 -. failure .-> C1["Compensate: Release Inventory"]
    S3 -. failure .-> C2["Compensate: Refund Payment"]
    end
```

#### 104 — Explain consistent hashing and why it's used for sharding/caching.
Consistent hashing maps both nodes and keys onto a hash ring; a key is owned by the next node clockwise on the ring. When a node is added or removed, only the keys between it and its neighbor need to move — unlike naive `hash(key) % N` sharding, where changing N remaps almost every key.

```mermaid
graph LR
    N1((Node 1)) --> N2((Node 2)) --> N3((Node 3)) --> N4((Node 4)) --> N1
    KeyA["key A (hash)"] -. owned by .-> N2
    KeyB["key B (hash)"] -. owned by .-> N4
```

#### 106 — Walk through Raft leader election and log replication in more depth.
Every node is Follower, Candidate, or Leader, and time is divided into monotonically increasing terms. A Follower that hears no heartbeat before its election timeout becomes a Candidate, increments the term, and requests votes; it becomes Leader on receiving votes from a majority. The Leader then replicates every write as a log entry to followers; an entry is only committed (safe to apply) once a majority of nodes have persisted it, and the Leader tracks a commit index that only advances forward. If a Leader crashes mid-replication, the next elected Leader is guaranteed (by the election rule that a node only votes for candidates with an equally-or-more up-to-date log) to already have every committed entry, so no committed write is ever lost.

```mermaid
stateDiagram-v2
    [*] --> Follower
    Follower --> Candidate: election timeout, no heartbeat
    Candidate --> Leader: wins majority of votes
    Candidate --> Follower: sees higher term / loses election
    Leader --> Follower: discovers higher term
    Follower: Follower — replicates leader's log
    Candidate: Candidate — requests votes for new term
    Leader: Leader — replicates writes, sends heartbeats
```

#### 109 — Where do strong, causal, and eventual consistency sit relative to each other, and what is "read-your-writes" consistency?
Strong consistency: every read sees the latest committed write, as if there were only one copy of the data — most expensive, since it needs coordination on every read or write. Eventual consistency: replicas converge given enough time with no new writes, but a read shortly after a write can return stale data — cheapest, no coordination needed. Causal consistency sits between them: operations that are causally related (a reply to a comment) are seen by everyone in that order, but unrelated operations can be seen in different orders on different replicas. Read-your-writes is a narrower, practical guarantee often layered on top of eventual consistency: a specific client is guaranteed to see its own writes on its next read (e.g. by routing that client's reads to the replica it wrote to, or a sticky session), even if other clients might still see stale data.

```mermaid
graph LR
    Strong["Strong<br/>(linearizable)"] --> Causal["Causal<br/>(preserves cause→effect order)"] --> RYW["Read-your-writes<br/>(session-scoped)"] --> Eventual["Eventual<br/>(converges, no ordering guarantee)"]
    Strong -.->|"more coordination, higher latency"| Eventual
```

#### 112 — Explain the bulkhead pattern, and how it differs from a circuit breaker.
A circuit breaker protects a single dependency by stopping calls to it once it's clearly failing. A bulkhead protects everything else from that one dependency by isolating resources — e.g. a separate connection pool, goroutine pool, or thread pool per downstream — so a slow or exhausted dependency can only exhaust its own pool, not starve requests to unrelated services sharing the same process. The two compose: bulkheads limit blast radius, circuit breakers stop wasting the (limited) resources bulkheads gave that dependency on calls likely to fail anyway.

```mermaid
graph TD
    subgraph "No bulkhead — shared pool"
    ReqA1[Requests to A] --> Pool[Shared Worker Pool]
    ReqB1[Requests to B] --> Pool
    Pool --> SlowA[Slow Dependency A]
    Pool -.->|pool exhausted by A, B starves too| SlowB[Dependency B]
    end
    subgraph "Bulkhead — isolated pools"
    ReqA2[Requests to A] --> PoolA[Pool A]
    ReqB2[Requests to B] --> PoolB[Pool B]
    PoolA --> SlowA2[Slow Dependency A]
    PoolB --> FastB[Dependency B — unaffected]
    end
```

---

## XII. System Design Case Studies

#### 114 — Design a URL shortener.
Key components: a write path that generates a short code (base62-encode an auto-incrementing ID, or a hash with collision check) and stores `short_code → long_url`; a read path that's a simple key lookup and 301/302 redirect. Reads vastly outnumber writes, so put a cache in front of the DB for the read path.

```mermaid
graph TD
    subgraph "Read path"
    C1[Client] -->|GET /code| LB[Load Balancer]
    LB --> App1[App Server]
    App1 -->|"1: check"| Cache[(Redis Cache)]
    Cache -->|"2: miss, fallback"| Replica[(Read Replica)]
    App1 -->|301/302 redirect| C1
    end
    subgraph "Write path"
    C2[Client] -->|POST long URL| App2[App Server]
    App2 -->|generate code| Primary[(Primary DB)]
    end
```

#### 115 — Design a distributed rate limiter shared across multiple API gateway instances.
Each gateway instance can't keep its own local counter, since that under-counts total traffic. Use a shared, fast store (Redis) holding per-client counters with a sliding-window or token-bucket algorithm implemented via an atomic Lua script.

```lua
-- executed atomically via EVAL, keyed per client
local tokens = tonumber(redis.call('GET', KEYS[1]) or ARGV[1])
if tokens > 0 then
  redis.call('DECRBY', KEYS[1], 1)
  return 1 -- allowed
end
return 0 -- rate limited
```

```mermaid
graph LR
    G1[Gateway Instance 1] --> Redis[(Shared Redis)]
    G2[Gateway Instance 2] --> Redis
    G3[Gateway Instance 3] --> Redis
    Redis -->|"atomic Lua: check + decrement"| Allowed{Allowed?}
```

#### 116 — Design a real-time fraud/risk scoring system with a tight latency SLA (<100ms), adding more signals over time.
Run signals in parallel goroutines with a bounded per-request timeout, so total latency is close to the slowest single signal, not the sum. Precompute/cache expensive signals asynchronously ahead of the request, and set a hard deadline so a single slow signal degrades gracefully rather than blowing the SLA.

```mermaid
graph TD
    Req["Incoming Request"] --> Fan["Fan out, bounded by ctx deadline"]
    Fan --> S1["Signal: Device Reputation (cached)"]
    Fan --> S2["Signal: IP Intelligence (cached)"]
    Fan --> S3["Signal: Velocity Check"]
    S3 -. timeout, skipped .-> Agg[Aggregator]
    S1 --> Agg
    S2 --> Agg
    Agg --> Verdict["Risk Verdict, less than 100ms"]
```

#### 117 — Design a notification system fanning a single event out to millions of users via push/email/SMS.
Ingest the triggering event into a message queue rather than processing synchronously. A fan-out worker resolves the target user list (paginated) and publishes one message per user per channel onto per-channel queues, each with dedicated worker pools respecting that channel's own rate limits.

```mermaid
graph LR
    Event --> Kafka[(Kafka)]
    Kafka --> FanOut["Fan-out Worker"]
    FanOut --> UserList["User list, paginated"]
    UserList --> PushQ[Push Queue]
    UserList --> EmailQ[Email Queue]
    UserList --> SMSQ[SMS Queue]
    PushQ --> PushW[Push Workers] --> APNs["APNs / FCM"]
    EmailQ --> EmailW[Email Workers] --> SMTP["SMTP Provider"]
    SMSQ --> SMSW[SMS Workers] --> SMSGW["SMS Gateway"]
```

#### 118 — Design an idempotent payment processing pipeline that survives retries without double-charging.
Client sends a request with a client-generated idempotency key. Server, in a single DB transaction, tries to insert a row keyed on that idempotency key with status "processing" — a unique constraint means a concurrent duplicate insert fails immediately. Only after the row is claimed does the service call the payment processor.

```sql
INSERT INTO payment_requests (idempotency_key, status)
VALUES ($1, 'processing')
ON CONFLICT (idempotency_key) DO NOTHING;
```

```mermaid
sequenceDiagram
    participant Client
    participant Server
    participant DB
    participant Processor
    Client->>Server: POST /charge (idempotency-key)
    Server->>DB: INSERT status=processing (unique key)
    alt key already exists
        DB-->>Server: conflict
        Server-->>Client: return stored result
    else new key claimed
        Server->>Processor: charge card
        Processor-->>Server: success
        Server->>DB: update status=complete + outbox event
        Server-->>Client: 200 OK
    end
```

#### 119 — Design a distributed job scheduler where each job runs exactly once even if a node crashes.
Store jobs and their next-run-time in a shared DB. Workers poll for due jobs and atomically claim one via a conditional update, which acts as a lightweight distributed lock. Include a lease/heartbeat so if the worker crashes mid-execution, the lock expires and another worker can reclaim it.

```sql
UPDATE jobs
SET locked_by = $1, locked_at = now()
WHERE id = $2 AND locked_by IS NULL;
-- 1 row updated => this worker owns the job
-- 0 rows updated => another worker already claimed it
```

```mermaid
graph TD
    W1["Worker 1: poll due jobs"] -->|"atomic claim: UPDATE ... WHERE locked_by IS NULL"| Jobs[(Jobs Table)]
    W2["Worker 2: poll due jobs"] -. claim fails, already locked .-> Jobs
    Jobs --> Exec["Execute Job"]
    Exec -. heartbeat / lease renewal .-> Jobs
    Exec -. crash, lease expires .-> W2
```

#### 120 — Design a sharded, horizontally-scalable chat/messaging backend.
Shard users/conversations across backend nodes using consistent hashing on a conversation or user ID. A connection-routing gateway looks up which shard owns a conversation and forwards accordingly; for offline delivery, persist messages and use a pub/sub layer so any node can catch up.

```mermaid
graph TD
    Clients --> Gateway["Connection Gateway<br/>(consistent hash on conversation ID)"]
    Gateway --> N1[Shard Node 1]
    Gateway --> N2[Shard Node 2]
    Gateway --> N3[Shard Node 3]
    N1 --> PubSub[("Pub/Sub: Kafka or Redis")]
    N2 --> PubSub
    N3 --> PubSub
    PubSub --> Store[(Message Store)]
```

#### 121 — Design a system for ingesting and aggregating high-throughput event streams (e.g., sports data) with the right delivery semantics.
Producers publish events partitioned by a natural key (e.g., game ID) so ordering is preserved per entity. Consumers process with at-least-once semantics and make aggregation idempotent (upserts keyed on event ID) so reprocessing after a crash doesn't double-count.

```mermaid
graph LR
    Producers -->|partition by game ID| Kafka[(Kafka Partitions)]
    Kafka --> Consumers["Consumers, at-least-once"]
    Consumers -->|idempotent upsert by event ID| State[(Aggregated State)]
    Consumers -. checkpoint offsets .-> Kafka
```

#### 122 — How would you evolve a monolith into microservices without a risky big-bang rewrite?
Use the strangler fig pattern: put a routing layer in front of the monolith, then incrementally extract one bounded-context feature at a time into a new service, routing that specific traffic there while everything else still goes to the monolith.

```mermaid
graph LR
    Client --> Proxy["Routing Proxy"]
    Proxy -->|legacy traffic| Monolith
    Proxy -->|extracted feature| NewService["New Service"]
    NewService -. via API, not direct DB .-> Monolith
```

#### 123 — Design an audit/compliance logging system for a fintech platform where logs must be tamper-evident and queryable.
Write audit events to an append-only store, and make tampering detectable by hash-chaining entries (each entry's hash includes the previous entry's hash). For queryability, stream/index the same events into a separate query-optimized store asynchronously, keeping the append-only log as the source of truth.

```go
type AuditEntry struct {
    Seq      int64
    Payload  []byte
    PrevHash [32]byte
    Hash     [32]byte
}

func appendEntry(prev AuditEntry, payload []byte) AuditEntry {
    h := sha256.Sum256(append(prev.Hash[:], payload...))
    return AuditEntry{
        Seq:      prev.Seq + 1,
        Payload:  payload,
        PrevHash: prev.Hash,
        Hash:     h,
    }
}
// altering any past entry changes its Hash, breaking every
// subsequent entry's PrevHash link -- tampering becomes detectable
```

```mermaid
graph LR
    Write["Write Event"] --> Log["Append-only hash-chained log<br/>(source of truth)"]
    Log -. async stream .-> Indexer
    Indexer --> Query[(Query store: Elasticsearch)]
```

---

## Notes

**[IX. Databases](#ix-databases--database-optimization):** worth its own drilling pass — indexing, isolation levels, and locking/deadlocks (78, 81, 82) come up constantly in architect-level interviews even outside a formal "system design" segment.

**[X–XII. System design](#x-system-design-fundamentals):** where the "Architect" part gets tested — practice actually drawing the diagrams for 87, 89, 91, 98, 100–105, and 114–123 from memory, not just describing them verbally.

**[XI. Distributed systems](#xi-distributed-systems-concepts):** 106 (Raft), 109 (consistency spectrum), and 112 (bulkhead) are the ones most likely to turn into a follow-up "ok, now what if the leader crashes mid-write" question, so have those diagrams reflexive, not just recitable.

---

Part 2 of 6 · [Interview Prep](/interview-prep/) · ← Previous: [Part 1 — Go Language](/interview-prep-language/) · Next: [Part 3 — Kafka & Microservices](/interview-prep-kafka-microservices/) →

<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
document.querySelectorAll('pre code.language-mermaid').forEach(function (el) {
  var div = document.createElement('div');
  div.className = 'mermaid';
  div.textContent = el.textContent;
  el.parentElement.replaceWith(div);
});
mermaid.initialize({ startOnLoad: true, theme: 'neutral' });
</script>
