---
title: "Interview Prep — Part 3: Databases & SQL"
description: "Database optimization, indexing internals, advanced query techniques, and query planning/storage/concurrency internals: 30 interview Q&As with diagrams."
url: "/interview-prep-databases-sql/"
aliases: ["/interview-prep-sql-advanced/", "/go-interview-prep-sql-advanced/"]
nodate: true
hidemeta: true
nofeed: true
quizmode: true
mermaid: true
---

Part 3 of 7 · [Interview Prep](/interview-prep/) · ← Previous: [Part 2 — Coding Patterns](/interview-prep-coding-patterns/) · Next: [Part 4 — System Design & Distributed Systems](/interview-prep-system-design/) →

Most database interviews don't stay at "what's an index." They move fast from schema and indexing into why a specific query is slow, and from there into execution plans, locking, and the storage internals that make Postgres behave the way it does. These 30 questions cover that whole span: the fundamentals you should already have, and the query and internals questions that separate a senior answer from a junior one.

**What this assumes:** you can write a `SELECT` with a `JOIN`, a `GROUP BY`, and a `WHERE`, and you know roughly what an index is for. Everything past that gets explained here.

**What you should be able to do after:** diagnose a slow query with a real method instead of a guess, and know when to reach for a window function, a partial index, or partitioning instead of brute force.

Every answer opens with **The gist**, one or two plain sentences. If the gist is all you have time for, that's still worth more than a half-remembered detail. The full answer underneath is what you say when they ask you to go deeper.

{{< toc >}}

{{< quizbar >}}

## Databases & Database Optimization

*Questions 1 to 5 are table stakes for any backend role. 6 to 10 come up in senior rounds even when the job description never mentions databases.*

### 1. What do the four ACID properties guarantee, with a concrete example of a violation? {#1}

{{% qa %}}
**The gist:** four promises a database makes about transactions. The one interviewers actually probe is atomicity: a transfer that debits one account then crashes can't leave the money nowhere.

**Atomicity:** a transaction is all-or-nothing, so no partial writes are ever visible. **Consistency:** a transaction moves the database from one valid state to another, respecting constraints and invariants. **Isolation:** concurrent transactions don't see each other's uncommitted intermediate state. **Durability:** once committed, a write survives a crash, typically via a write-ahead log flushed to disk before the commit is acknowledged.

Violation example: without atomicity, a funds transfer that debits one account but crashes before crediting the other leaves money vanished.

**What they're testing:** whether you can give a violation example. Reciting the four words is the easy half, and they'll ask for the example either way.
{{% /qa %}}

### 2. Normalization vs. denormalization: what's the trade-off, and when would you denormalize? {#2}

{{% qa %}}
**The gist:** normalize to store each fact once, denormalize to skip joins at read time. You're trading write-time safety for read-time speed.

Normalization (3NF and beyond) splits data into related tables joined by foreign keys so each fact is stored once. That saves storage and avoids update anomalies, at the cost of needing joins to read.

Denormalization intentionally duplicates or pre-joins data to avoid those joins at read time: cheaper reads, but it risks write-time inconsistency and costs extra storage.

Denormalize for read-heavy, write-light workloads, for example a precomputed "order summary" table instead of joining orders, items, and users on every page load.
{{% /qa %}}

### 3. Why does column order matter in a composite index, and what makes an index "covering"? {#3}

{{% qa %}}
**The gist:** an index on `(a, b, c)` only helps when your `WHERE` starts at `a`. It's a phone book sorted by last name then first name: useless if all you know is the first name.

A composite index on `(a, b, c)` is only useful for queries filtering on a left prefix of those columns. It serves `WHERE a = ?` and `WHERE a = ? AND b = ?`, but not `WHERE b = ?` alone. Put the most selective or most commonly-filtered-alone column first.

```sql
CREATE INDEX idx_events ON events (tenant_id, created_at, kind);

-- Uses the index: filters start at the leading column.
SELECT * FROM events WHERE tenant_id = 7;
SELECT * FROM events WHERE tenant_id = 7 AND created_at > now() - '1d';

-- Does not use it: skips the leading column entirely.
SELECT * FROM events WHERE created_at > now() - '1d';
```

A covering index additionally includes every column a query needs, via `INCLUDE` or as a composite over all selected and filtered columns, so the database answers the query entirely from the index without touching the table. That's an index-only scan.

**Try it:** create the two-column index above on a scratch table, then run `EXPLAIN` on a query that filters only on the second column. Watch the planner ignore the index and fall back to a sequential scan.
{{% /qa %}}

### 4. What is the N+1 query problem, and how do you fix it? {#4}

{{% qa %}}
**The gist:** you fetch 100 rows, then loop and fire one more query per row. That's 101 queries where 2 would do. It's almost always an ORM lazy-load sitting inside a loop.

It happens when code fetches N parent records with one query, then loops over them issuing one more query per record for related data.

```go
// N+1: one query for orders, then one per order.
orders := db.Query(`SELECT id FROM orders WHERE user_id = $1`, uid)
for _, o := range orders {
    o.Items = db.Query(`SELECT * FROM items WHERE order_id = $1`, o.ID)
}

// Fixed: one follow-up query for every order at once.
items := db.Query(`SELECT * FROM items WHERE order_id = ANY($1)`, ids)
// then group items by order_id in memory
```

The fix is either to eager-load the association up front with a `JOIN`, or to batch the follow-up lookups into a single `WHERE parent_id IN (...)` query and group the results in memory.

**What they're testing:** whether you'd spot it in a code review. The query itself is fast, which is exactly why it hides: nothing shows up in a slow-query log.

**Try it:** turn on query logging (`log_statement = 'all'` in Postgres, or your ORM's debug logger) for one API request that renders a list with related records, and count how many queries actually ran.
{{% /qa %}}

### 5. You're handed a slow production query: what do you check, in order? {#5}

{{% qa %}}
**The gist:** work outside in. First ask whether it's really one slow query or a hundred fast ones. Then check the plan, the index, the statistics, and the connection pool before you blame the database.

1. `EXPLAIN ANALYZE` it. Is it doing a sequential scan on a large table it shouldn't be?
2. Confirm an index exists on the filtered and joined columns, and that its leading columns match the query.
3. Check whether it's actually N+1 queries in disguise from the calling code, not one slow query.
4. Check that table statistics are fresh and the table isn't bloated (`ANALYZE` and `VACUUM` in Postgres).
5. Check the connection pool isn't saturated. Queries queueing for a connection look slow even when the query itself is fine (see [connection pooling]({{< ref "interview-prep-language.md" >}}#75) in Part 1).
6. For a genuinely hot read path, reach for [caching]({{< ref "interview-prep-system-design.md" >}}#10) (Part 4) or a read replica ([Q10](#10)) before reaching for a bigger box.

**What they're testing:** whether you have a method or you guess. Saying "I'd add an index" first is the answer they're hoping you don't give.

**Try it:** take a real query from your own app, run `EXPLAIN (ANALYZE, BUFFERS)` on it, and work through the checklist above line by line before you touch an index.
{{% /qa %}}

### 6. How does a B-tree index make lookups fast, and when does an index *not* help? {#6}

{{% qa %}}
**The gist:** it's a sorted, balanced tree, so a lookup takes a handful of hops instead of reading every row. It stops helping the moment the column barely narrows anything down.

A B-tree keeps keys sorted in a balanced tree, so a lookup walks from root to leaf in O(log n) comparisons instead of scanning every row. Leaf nodes are linked in sorted order, which makes range scans (`BETWEEN`, `ORDER BY`) cheap too. Each leaf entry points back to the actual row.

An index does *not* help when:

- The column has low selectivity. A boolean flag on a huge table matches half the rows anyway, so the planner rightly prefers a sequential scan.
- The query wraps the column in a function (`WHERE LOWER(email) = ...`) without a matching expression index.
- The pattern has a leading wildcard. `LIKE '%foo'` can't use a plain B-tree, it needs a trigram or full-text index.
- The table is small enough that a full scan is simply cheaper than random index lookups.

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

**Try it:** run `EXPLAIN` on `WHERE email = 'x'` versus `WHERE LOWER(email) = 'x'` on a table with a plain index on `email`. The second one won't use the index unless you build one on the expression itself.
{{% /qa %}}

### 7. How do you read a query execution plan to diagnose a slow query? {#7}

{{% qa %}}
**The gist:** `EXPLAIN ANALYZE` runs the query and shows what the planner chose plus real timings. The single most useful thing on the page is estimated rows versus actual rows.

Key things to check:

- **Scan type per node.** `Seq Scan` is a full table scan, `Index Scan` uses an index then fetches the row, `Index Only Scan` is answered entirely from the index, `Bitmap Heap Scan` combines several index matches before hitting the table.
- **Cost estimate**, shown as startup..total in arbitrary planner units.
- **Estimated rows vs. actual rows**, which matters most. A big divergence means the table's statistics are stale, so the planner is guessing wrong, and a wrong guess is what makes it pick a bad plan. The fix is often just `ANALYZE table_name`.

```sql
-- No index on customer_id:
EXPLAIN ANALYZE SELECT * FROM orders WHERE customer_id = 42;

Seq Scan on orders
  (cost=0.00..18334.00 rows=12 width=120)
  (actual time=0.02..142.30 rows=8 loops=1)
  Filter: (customer_id = 42)
  Rows Removed by Filter: 999992

-- After: CREATE INDEX idx_orders_customer ON orders(customer_id);
Index Scan using idx_orders_customer on orders
  (cost=0.42..8.44 rows=12 width=120)
  (actual time=0.015..0.021 rows=8 loops=1)
  Index Cond: (customer_id = 42)
```

**What they're testing:** whether you read plans or just run them. "Rows Removed by Filter: 999992" is the line that tells the whole story, and they want to see you find it.

**Try it:** run `EXPLAIN ANALYZE` on a query with no index, note the estimated versus actual row counts, add the index, and run it again to see both numbers converge.
{{% /qa %}}

### 8. Explain the transaction isolation levels and the anomalies each one prevents. {#8}

{{% qa %}}
**The gist:** four levels, each preventing more of the odd things concurrent transactions can see. Most apps sit on Read Committed and never think about it again.

Each stricter level prevents more of the read anomalies that come from concurrent transactions, at the cost of more locking and lower concurrency:

| Isolation level | Dirty read | Non-repeatable read | Phantom read |
|---|---|---|---|
| Read Uncommitted | possible | possible | possible |
| Read Committed | prevented | possible | possible |
| Repeatable Read | prevented | prevented | possible (Postgres's snapshot-based RR also prevents phantoms) |
| Serializable | prevented | prevented | prevented |

A **dirty read** sees another transaction's uncommitted write. A **non-repeatable read** re-reads the same row within one transaction and gets a different value, because another transaction committed a change in between. A **phantom read** re-runs the same filtered query and sees a different *set* of rows, because another transaction inserted or deleted matching rows in between.

Most applications default to Read Committed. Serializable is reserved for invariants that absolutely cannot tolerate any anomaly, since it costs the most concurrency, often via retries on serialization failure.

**Try it:** open two `psql` sessions, set one to `REPEATABLE READ` and read a row, have the other session update and commit that row, then re-read it in the first session and watch it not change.
{{% /qa %}}

### 9. Optimistic vs. pessimistic locking, and how does a deadlock happen? {#9}

{{% qa %}}
**The gist:** pessimistic locks the row up front. Optimistic doesn't lock at all, it just checks at write time that nobody else changed it. A deadlock is two transactions each holding what the other is waiting for.

Pessimistic locking acquires a lock before touching a row (`SELECT ... FOR UPDATE`) so nothing else can modify it until you're done. Safe under contention, but it reduces concurrency and can deadlock.

Optimistic locking reads a version or timestamp column, does the work, then writes conditionally on that version being unchanged (`WHERE version = read_version`), retrying on a mismatch. Better throughput when contention is low, wasted work when it's high.

A deadlock happens when two transactions each hold a lock the other is waiting for, in opposite order: a circular wait.

```sql
-- T1                          -- T2
BEGIN;                         BEGIN;
UPDATE accounts                UPDATE accounts
  SET balance = balance - 10     SET balance = balance - 10
  WHERE id = 1;                  WHERE id = 2;

UPDATE accounts                UPDATE accounts
  SET balance = balance + 10     SET balance = balance + 10
  WHERE id = 2;                  WHERE id = 1;
-- T1 waits on T2's lock, T2 waits on T1's. Circular wait.
-- The database kills one of them as the deadlock victim.
```

The database's deadlock detector picks a victim, rolls it back with an error, and the application must retry it.

**What they're testing:** the fix, which is always to acquire locks on rows in a consistent global order. Sort the IDs before you lock them and the cycle can't form.

**Try it:** open two `psql` sessions and run the T1/T2 statements above in the interleaved order shown. Postgres will pick a victim and return `deadlock detected` in one of them.
{{% /qa %}}

### 10. Explain leader-follower replication and replication lag. {#10}

{{% qa %}}
**The gist:** writes go to one leader, followers copy the changes and serve reads. Copying takes time, so a read right after your own write can still show the old value.

Writes go to the leader (primary), which streams its change log (for example Postgres's WAL) to one or more followers (replicas), which apply the changes and can serve reads. This gives horizontal read scaling and a hot standby for failover.

Because replication is usually asynchronous, followers apply changes with a delay, called replication lag, so a read against a follower immediately after a write to the leader can return stale data.

This bites hardest on "read your own write" right after an update. Either route that specific read to the leader, or use synchronous replication for stronger consistency at a latency cost. See also [sharding and partitioning]({{< ref "interview-prep-system-design.md" >}}#3) (Part 4), which splits data across nodes rather than copying all of it to each.

```mermaid
graph TD
    App[App] -->|writes| Leader[("Leader / Primary")]
    Leader -->|"WAL stream, async"| F1[("Follower 1")]
    Leader -->|"WAL stream, async"| F2[("Follower 2")]
    App -.->|"reads, may lag"| F1
    App -.->|"reads, may lag"| F2
```
{{% /qa %}}


---

## Advanced Query Techniques

*Questions 11 to 17 are everyday SQL you can reasonably be expected to know now. 18 to 20 are where a senior screen starts.*

### 11. What's the difference between `UNION` and `UNION ALL`, and why does it matter for performance? {#11}

{{% qa %}}
**The gist:** `UNION` removes duplicates, and removing duplicates means sorting or hashing every row first. `UNION ALL` just glues the two result sets together and skips all that work.

`UNION` deduplicates the combined result set, which means sorting or hashing every row to find duplicates. `UNION ALL` just concatenates the two result sets with no dedup pass. If the query already guarantees no overlap (two mutually exclusive `WHERE` branches), `UNION ALL` is strictly cheaper and should be the default. Reach for `UNION` only when you actually need duplicates removed.

```sql
-- These branches can't overlap, so the dedup pass is pure waste.
SELECT id, 'active' AS bucket FROM orders WHERE status = 'active'
UNION ALL
SELECT id, 'closed' AS bucket FROM orders WHERE status = 'closed';
```

**Try it:** run the same query with `UNION` instead of `UNION ALL` and diff the row counts. Since the two branches can't overlap here, the counts should match, that's the dedup pass doing nothing but costing you a sort.
{{% /qa %}}

### 12. `EXISTS`, `IN`, or a `JOIN` for an existence check: does it matter which one you pick? {#12}

{{% qa %}}
**The gist:** usually the planner turns all three into the same plan, so speed isn't the real difference. `NULL` is. One `NULL` inside an `IN` subquery can silently wipe out your entire result.

Modern query planners (Postgres included) usually rewrite all three into the same semi-join plan when the subquery is uncorrelated, so raw performance is often a wash. `EXISTS` short-circuits on the first match and handles `NULL`s in the subquery correctly, where `IN` against a subquery containing a `NULL` can silently produce zero rows for the whole query. That's a classic footgun. Prefer `EXISTS` for correlated existence checks and reserve `IN` for a short, known literal list.

Here's the footgun, concretely. `NOT IN` returns nothing at all the moment the subquery yields a single `NULL`:

```sql
-- customers.referrer_id is nullable, and at least one row is NULL.

SELECT count(*) FROM orders
WHERE customer_id NOT IN (SELECT referrer_id FROM customers);
-- 0. Always 0. Not because nothing matched.

SELECT count(*) FROM orders o
WHERE NOT EXISTS (
  SELECT 1 FROM customers c WHERE c.referrer_id = o.customer_id
);
-- the answer you actually wanted
```

`NOT IN` has to prove your value differs from *every* row in the list. Against `NULL` it can't prove that, so the whole comparison goes unknown, and unknown isn't true.

**What they're testing:** whether you've been bitten by this. "They're basically the same" is a fine opening, but they want you to get to `NULL` on your own.

**Try it:** create a tiny `customers` table with one row where `referrer_id` is `NULL`, then run both queries above against it. The `NOT IN` version returns 0 rows no matter what's in `orders`, the `NOT EXISTS` version doesn't.
{{% /qa %}}

### 13. What does `INSERT ... ON CONFLICT DO UPDATE` (upsert) buy you over a separate `SELECT` then `INSERT`/`UPDATE`? {#13}

{{% qa %}}
**The gist:** check-then-write is a race. Two requests both see "no row here" and both try to insert. `ON CONFLICT` collapses the check and the write into one step the database won't let anything slip between.

A separate select-then-write is a race: two concurrent requests can both see "no row exists" and both attempt an insert, and one fails on the unique constraint (or worse, without one, you get a duplicate). `ON CONFLICT DO UPDATE` makes the whole check-then-act atomic at the database level. Pair it with `RETURNING` to get the final row back without a second query.

```sql
INSERT INTO user_settings (user_id, theme, updated_at)
VALUES ($1, $2, now())
ON CONFLICT (user_id) DO UPDATE
  SET theme = EXCLUDED.theme, updated_at = now()
RETURNING *;
```

`EXCLUDED` is the row you tried to insert, so it's how you reach the new values inside the update branch.

**Try it:** open two `psql` sessions and run the same `INSERT ... ON CONFLICT DO UPDATE` for the same `user_id` at the same time. One blocks briefly on the row lock, then both succeed, no duplicate and no error, which is the difference from a plain `INSERT` you'd otherwise have to catch a unique-violation from.
{{% /qa %}}

### 14. What's a `LATERAL` join, and when do you actually need one? {#14}

{{% qa %}}
**The gist:** a normal join's right side can't look at the row on the left. `LATERAL` lets it, which is what turns "top 3 per customer" into one readable query.

A normal join's right-hand side can't reference columns from the left-hand table. `LATERAL` lifts that restriction, letting a subquery on the right reuse a value from the current row on the left. The classic case is "top 3 orders per customer," where the subquery needs the current customer's id to filter and limit before the join happens. Without `LATERAL` that needs a window function and an extra filtering layer instead of one readable join.

```sql
SELECT c.id, c.name, o.order_id, o.amount
FROM customers c
CROSS JOIN LATERAL (
  SELECT order_id, amount
  FROM orders
  WHERE customer_id = c.id     -- c.id is only reachable because of LATERAL
  ORDER BY amount DESC
  LIMIT 3
) o;
```
{{% /qa %}}

### 15. Full-text search with `tsvector`/`tsquery` vs. a `LIKE '%term%'` scan: what's the actual difference? {#15}

{{% qa %}}
**The gist:** a leading `%` rules out the index, so the database reads every row in the table. Full-text search indexes the words themselves, so the same search becomes a lookup.

`LIKE '%term%'` with a leading wildcard can't use a standard B-tree index at all, so it's a sequential scan regardless of table size. A B-tree index is sorted by the start of the value, and a leading `%` says "I don't know the start," so the sorting buys you nothing.

`tsvector`/`tsquery` takes a different route. It breaks the text into words, normalizes them (so "running" and "ran" both reduce to "run"), drops filler words like "the", and stores the result as a document that a GIN index can index directly. A GIN index maps each word to the rows containing it, which is what turns the search into a lookup instead of a scan. It also ranks results by relevance, which `LIKE` has no concept of.

```sql
CREATE INDEX idx_articles_fts ON articles
  USING GIN (to_tsvector('english', body));

SELECT id, title
FROM articles
WHERE to_tsvector('english', body)
      @@ to_tsquery('english', 'database & index');
```

**What they're testing:** whether "the index can't be used here" is a thought you reach on your own. Naming `tsvector` functions from memory isn't the point, and they'll push a step past it.

**Try it:** `EXPLAIN` a `WHERE body LIKE '%database%'` query on a table with 100k or more rows, then `EXPLAIN` the `to_tsvector` version with the GIN index in place. The first shows `Seq Scan`, the second shows `Bitmap Index Scan`.
{{% /qa %}}

### 16. What does `pg_trgm` add on top of full-text search? {#16}

{{% qa %}}
**The gist:** full-text search matches whole words, so a typo matches nothing. Trigrams match three-letter chunks, which is how you catch "Jonh" when the row says "John."

`tsvector` search is token-based, so it won't match a typo or a substring that crosses a token boundary. `pg_trgm` indexes overlapping three-character sequences of a string, which makes fuzzy and similarity matching work, and makes substring `LIKE '%term%'` queries index-able through a GIN or GiST trigram index.

Use full-text search for "find documents about this topic" and trigram for "find rows whose name is close to what the user typo'd."

**Try it:** `CREATE EXTENSION pg_trgm;`, add `CREATE INDEX idx_customers_name_trgm ON customers USING GIN (name gin_trgm_ops);`, then run `SELECT name FROM customers WHERE name % 'Jonh Smith';` and watch it match "John Smith" even though the spelling's wrong.
{{% /qa %}}

### 17. Postgres changed how CTEs behave around version 12: what changed, and why does it matter? {#17}

{{% qa %}}
**The gist:** before Postgres 12 a CTE was a wall the planner couldn't see through. Now it's inlined by default, so the same query can be fast on one server and slow on another for no reason you can see in the SQL.

Before Postgres 12, every CTE was an optimization fence: the planner materialized it as a temporary result set and couldn't push filters from the outer query down into it, even when that would've been cheaper. From Postgres 12 on, a non-recursive CTE is inlined by default like a subquery, unless it's referenced more than once or explicitly marked `MATERIALIZED`.

That version difference is worth knowing because it's a real production surprise: the same CTE-heavy query, same data, different server, wildly different plan.

**Try it:** on Postgres 12 or later, run the same CTE-heavy query twice: once as-is, once with the CTE marked `MATERIALIZED`. `EXPLAIN` both and watch the second one refuse to push the outer `WHERE` down into the CTE, which is the pre-12 behavior forced back on.
{{% /qa %}}

### 18. How do window functions differ from `GROUP BY`, and what does `ROW_NUMBER`/`RANK`/`LAG` give you that aggregation can't? {#18}

{{% qa %}}
**The gist:** `GROUP BY` throws the individual rows away and hands back one row per group. A window function does the same maths and keeps every row, which is how you get "this row's rank within its group."

`GROUP BY` collapses a group of rows into one output row per group, so you lose access to individual rows outside the aggregate. A window function computes across a group (defined by `PARTITION BY`) without collapsing anything, so each input row still gets exactly one output row plus an extra computed column, e.g. the rank of a row within its partition. This makes "top N per group," running totals, and row-over-row comparisons possible without a self-join or a subquery per row.

```sql
SELECT
  customer_id,
  order_id,
  amount,
  RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC)
    AS rank_in_customer,
  SUM(amount) OVER (PARTITION BY customer_id ORDER BY created_at)
    AS running_total
FROM orders;
```

`ROW_NUMBER` gives a strict 1,2,3... with no ties. `RANK` leaves gaps after a tie (1,1,3), `DENSE_RANK` doesn't (1,1,2). `LAG`/`LEAD` read a value from a preceding or following row in the same partition, which is what makes period-over-period comparisons a single query instead of a self-join.

**What they're testing:** this one usually turns into "now write it." Have `PARTITION BY ... ORDER BY` ready to produce from memory, not just recognize.
{{% /qa %}}

### 19. When does a recursive CTE actually earn its complexity, and what's the failure mode if you get the recursion wrong? {#19}

{{% qa %}}
**The gist:** use one when the data is a tree of unknown depth, like an org chart or a comment thread. You can't write "however many levels deep this goes" as a fixed number of joins.

Any hierarchy of unknown, variable depth (an org chart, a category tree, a bill-of-materials, a comment thread) needs a recursive CTE, because a fixed number of joins can't express "however many levels deep this happens to go." The structure is always an anchor (the base case) `UNION ALL`'d with a recursive term that joins back to the CTE's own name, terminating when the recursive term returns no rows.

```sql
WITH RECURSIVE org_chart AS (
  SELECT id, name, manager_id, 1 AS depth
  FROM employees
  WHERE manager_id IS NULL          -- anchor: the top of the org
  UNION ALL
  SELECT e.id, e.name, e.manager_id, oc.depth + 1
  FROM employees e
  JOIN org_chart oc ON e.manager_id = oc.id   -- recursive term
)
SELECT * FROM org_chart ORDER BY depth;
```

Get the recursive term wrong, most commonly a join condition that can revisit a row it already processed, and you get infinite recursion. Postgres will eventually blow past `work_mem` or hit a recursion limit and error out rather than hang forever, but it's still the first thing to check when a recursive CTE that used to be fast suddenly isn't: a cycle got introduced in the data.

**Try it:** intentionally break the recursive term's join condition so the same row can be revisited, then run the query with a `LIMIT 20` as a safety net and watch it happily keep producing rows past where a real org chart would have stopped.
{{% /qa %}}

### 20. When should a column be `JSONB` instead of a normalized set of tables, and how do you index it? {#20}

{{% qa %}}
**The gist:** `JSONB` is right when the shape genuinely differs per row and you read the whole blob at once. It's wrong the moment you're filtering on the same two keys every day, because those keys are relational data in a costume.

`JSONB` fits data that's genuinely schema-variable per row (a plugin's arbitrary settings object, a webhook payload you need to store but not query deeply), or where the write pattern is "store the whole document, read the whole document" and normalizing would just mean reassembling it on every read.

It's the wrong choice once you're regularly filtering or joining on a handful of specific keys. At that point a normalized column with a real type and index is both faster and gets you constraints for free. A GIN index on a `JSONB` column supports the containment operator (`@>`) efficiently, but a single key queried constantly is often better served by extracting it into a real generated column with a plain B-tree index.

```sql
CREATE INDEX idx_metadata_gin ON accounts USING GIN (metadata);
SELECT * FROM accounts WHERE metadata @> '{"plan": "enterprise"}';
```

**Try it:** `EXPLAIN` that containment query against the GIN index, then `EXPLAIN` the same filter written as `metadata->>'plan' = 'enterprise'`. The first uses the index, the second usually doesn't unless you've also indexed that expression directly.
{{% /qa %}}

---

## Query Planning, Storage & Concurrency Internals

*This is the internals half, and nobody expects a junior to have all of it. But 25, 26 and 30 come up constantly the first time you're on call for a database, so they're worth the time even if the rest can wait.*

### 21. Partial index vs. indexing the whole column: when does a partial index win? {#21}

{{% qa %}}
**The gist:** if 95% of your rows are `'completed'` and you only ever query the other 5%, indexing all of them is wasted space. A partial index covers just the rows you actually look for.

A partial index (`CREATE INDEX ... WHERE condition`) only indexes the subset of rows matching the predicate, so it's smaller, faster to scan, and cheaper to maintain than a full-column index when queries consistently filter on that same condition.

```sql
-- The job queue only ever asks for pending work.
CREATE INDEX idx_jobs_pending ON jobs (created_at) WHERE status = 'pending';
```

It's a poor fit when queries filter on a wide variety of conditions, since a partial index only helps the specific predicate it was built with. Query for `status = 'failed'` and this index does nothing for you.

**Try it:** `EXPLAIN` a query for `WHERE status = 'failed'` against the table from the snippet above. The partial index only covers `status = 'pending'`, so you'll see a sequential scan even though there's an index on the table.
{{% /qa %}}

### 22. What's an advisory lock, and when do you reach for one instead of a row or table lock? {#22}

{{% qa %}}
**The gist:** a lock on an idea rather than on data. You pick a number, the database hands that number to exactly one connection at a time, and that's your "only one server runs this job" guarantee.

Row and table locks are tied to actual data and are taken and released automatically by the transaction touching that data. An advisory lock (`pg_advisory_lock`) is an arbitrary application-level lock keyed by a number you choose, with no connection to any row. You use it to coordinate application logic that isn't really a data lock, for example making sure only one instance of a scheduled job runs at a time across a fleet.

```sql
-- Returns true only for the one caller that gets it. Everyone else moves on.
SELECT pg_try_advisory_lock(42);
```

`pg_try_advisory_lock` returns immediately rather than waiting, which is usually what you want for a job runner: the losers should skip the work, not queue up behind it. It's a cheap way to get distributed mutual exclusion out of a database you already have.

**Try it:** open two `psql` sessions and run `SELECT pg_try_advisory_lock(42);` in both. The first returns `true`, the second returns `false` immediately, no waiting, which is the point.
{{% /qa %}}

### 23. When do stored procedures or triggers earn their complexity, versus just hiding logic from the app layer? {#23}

{{% qa %}}
**The gist:** put it in the database when it has to be true no matter what touches the table, including a script someone runs by hand. Keep it in the app when it's business logic that'll change next quarter.

They earn it when the logic must be true regardless of which client touches the data: an invariant enforced at the data layer that no application bug can bypass, like maintaining an audit trail, or a constraint too complex for a `CHECK`.

They become a liability when they encode business logic that changes often, since that logic is now split across the app codebase and the database, invisible to code review and hard to unit test. Default to keeping logic in the application, and push it into the database only for invariants that must hold no matter what touches the table.
{{% /qa %}}

### 24. PgBouncer's transaction pooling mode vs. session mode: what actually breaks in transaction mode? {#24}

{{% qa %}}
**The gist:** transaction mode hands your connection back to the pool the instant you commit. Anything you left sitting on that connection, a prepared statement, a `SET`, a `LISTEN`, is gone or on someone else's connection next time.

Session mode assigns one real database connection to a client connection for its entire session, so anything session-scoped (prepared statements, session-level `SET`, `LISTEN`/`NOTIFY`) works exactly like talking to Postgres directly.

Transaction mode returns the real connection to the pool as soon as a transaction commits, letting far fewer real connections serve far more clients. The catch is that a prepared statement or session variable set on one transaction can silently vanish, or land on a different underlying connection on the next.

Transaction mode is the right default for a stateless web app's pool. Session state needs a dedicated session-mode connection.

**What they're testing:** whether you know why your ORM started throwing "prepared statement does not exist" after someone put PgBouncer in front of the database. That's the war story this question is fishing for.
{{% /qa %}}

### 25. `VACUUM`, `VACUUM FULL`, and autovacuum: what does each actually do? {#25}

{{% qa %}}
**The gist:** plain `VACUUM` marks dead space reusable without locking anything. `VACUUM FULL` rewrites the table to actually shrink the file, and locks everyone out while it does. Autovacuum is plain `VACUUM` running on its own.

Plain `VACUUM` (which autovacuum runs automatically) reclaims dead tuple space for reuse by future writes and updates statistics, without an exclusive lock and without shrinking the file on disk.

`VACUUM FULL` rewrites the entire table into a new, compact file with no dead space, which does shrink it on disk but takes an exclusive lock for the duration. That makes it a rare, deliberate maintenance operation, not something to run routinely.

Autovacuum is tuned (thresholds, worker count, cost delay), not disabled. Disabling it is what leads to the bloat it exists to prevent.

**Try it:** `UPDATE` the same handful of rows in a loop a few hundred times, check `n_dead_tup` in `pg_stat_user_tables`, run `VACUUM`, and watch it drop back down without the table's on-disk size changing.
{{% /qa %}}

### 26. Why can a query slow down over time even though the query, schema, and data volume haven't meaningfully changed? {#26}

{{% qa %}}
**The gist:** the planner picks a plan from statistics, and statistics go stale. It's still working from a picture of your table taken weeks ago.

The query planner picks a plan based on row-count and distribution estimates gathered by the last `ANALYZE`. If autovacuum's analyze threshold hasn't fired recently on a table whose data distribution is shifting, the planner works from an outdated picture and can pick a sequential scan or the wrong join order.

```sql
-- Cheap first diagnostic: when did this table last get looked at?
SELECT relname, last_analyze, last_autoanalyze, n_live_tup
FROM pg_stat_user_tables WHERE relname = 'orders';

ANALYZE orders;
```

Running `ANALYZE` manually is a cheap first move before assuming a missing index is the problem. It slots into the [slow-query checklist](#5) as the "did anything actually change" step.

**Try it:** bulk-insert a few hundred thousand rows without running `ANALYZE`, then `EXPLAIN ANALYZE` a filtered query and compare the planner's row estimate to the actual row count. Run `ANALYZE` and re-run the same query to see the estimate snap back in line.
{{% /qa %}}

### 27. Nested loop, hash join, and merge join: what does the planner actually choose between, and why? {#27}

{{% qa %}}
**The gist:** three ways to match rows. Nested loop looks each one up individually, hash join builds a lookup table from the smaller side, merge join walks both sides in order like a zipper. The planner guesses which is cheapest from your table sizes and indexes.

A nested loop scans the outer table and, for every row, probes the inner table. That's cheap when the outer side is small or the inner side has a usable index, and expensive as both sides grow, since it's O(n×m) in the worst case.

A hash join builds an in-memory hash table from the smaller side, then streams the larger side through it. Good when there's no useful index but the smaller side fits comfortably in `work_mem`.

A merge join sorts both sides by the join key (or uses an already-sorted index) and walks them in lockstep, which wins when both inputs are already sorted, since the expensive sort is avoided entirely.

```mermaid
graph TD
    Q["Join query"] --> C{"Planner picks based on:<br/>size, indexes, memory"}
    C -->|"small outer + index on inner"| NL["Nested Loop<br/>O(n×m) worst case"]
    C -->|"no useful index,<br/>fits in work_mem"| HJ["Hash Join<br/>build + probe"]
    C -->|"both sides already sorted<br/>on the join key"| MJ["Merge Join<br/>sorted merge, no extra sort"]
```

[`EXPLAIN ANALYZE`](#7) shows which one actually ran. If a hash join spills to disk because the build side didn't fit in `work_mem`, that shows up as a much slower actual time than the estimate: a signal to raise `work_mem` for that query rather than assume the join type itself is wrong.

**What they're testing:** whether you can read a plan and say why the planner chose what it chose. You're not expected to pick joins by hand, you're expected to know what the planner was reacting to.

**Try it:** `SET enable_hashjoin = off;` before running a join that would normally hash, then `EXPLAIN` it again and watch the planner fall back to a nested loop or merge join instead.
{{% /qa %}}

### 28. Table partitioning vs. sharding: where's the line, and why would you reach for one over the other? {#28}

{{% qa %}}
**The gist:** partitioning splits a table into pieces on one machine. Sharding splits it across many machines. Same idea, wildly different operational cost.

Partitioning splits one logical table into physical sub-tables (by range, list, or hash on a key) that all still live on the same database instance, transparent to most queries. A query filtering on the partition key only scans the relevant partition, and you get cheap bulk drops: drop a whole month's partition instead of running a slow `DELETE`.

[Sharding]({{< ref "interview-prep-system-design.md" >}}#3) (Part 4) splits data across separate database instances entirely. That solves a write-throughput or storage-capacity ceiling a single machine can't hold, at the cost of cross-shard queries and joins becoming genuinely hard.

```mermaid
graph TD
    subgraph "Partitioning: one instance"
    T["orders (logical table)"] --> P1["orders_2026_01"]
    T --> P2["orders_2026_02"]
    T --> P3["orders_2026_03"]
    end
    subgraph "Sharding: multiple instances"
    S["orders (logical table)"] --> DB1["Shard A: customers 0-999"]
    S --> DB2["Shard B: customers 1000-1999"]
    end
```

Reach for partitioning first: it's a single-instance, low-complexity win for a large, time-ordered or naturally-bucketed table. Reach for sharding only once a single instance genuinely can't hold the write load or data volume, since it multiplies operational complexity.

**What they're testing:** whether you conflate the two. Interviewers often ask both back to back for exactly that reason.
{{% /qa %}}

### 29. Materialized view vs. a regular view: what do you give up, and how do you keep a materialized view from serving stale data? {#29}

{{% qa %}}
**The gist:** a regular view re-runs the query every time you read it. A materialized view stores the answer, so reads are free but the data is as old as your last refresh.

A regular view is just a stored query, re-executed in full against live data every time it's selected from. Always current, but paying the full query cost on every read.

A materialized view runs the query once and stores the result set physically, so reads are as cheap as reading a table. The cost is that the data is a snapshot from whenever it was last refreshed.

```sql
CREATE MATERIALIZED VIEW daily_revenue AS
  SELECT date_trunc('day', created_at) AS day, sum(amount) AS total
  FROM orders GROUP BY 1;

CREATE UNIQUE INDEX ON daily_revenue (day);   -- required by CONCURRENTLY

REFRESH MATERIALIZED VIEW CONCURRENTLY daily_revenue;
```

Plain `REFRESH MATERIALIZED VIEW` locks the view against reads for the duration. `CONCURRENTLY` avoids that lock by building the new result set alongside the old one and swapping, at the cost of needing that unique index and taking somewhat longer overall.

The right fit is an expensive aggregate read far more often than the underlying data changes: a dashboard rollup refreshed every few minutes, not something needing per-write freshness.

**Try it:** `UPDATE` a row in `orders`, `SELECT` from `daily_revenue` and see the old total, then `REFRESH MATERIALIZED VIEW CONCURRENTLY daily_revenue;` and select again to see it catch up.
{{% /qa %}}

### 30. What is MVCC, and why does it cause table bloat if autovacuum falls behind? {#30}

{{% qa %}}
**The gist:** Postgres never edits a row in place. An `UPDATE` writes a new copy and marks the old one dead, which is how readers never block on writers. If nothing cleans up the dead copies, the file just keeps growing.

Postgres never overwrites a row in place on `UPDATE` or `DELETE`. Instead it writes a new row version and marks the old one dead, which is what lets concurrent readers keep seeing a consistent snapshot without blocking on writers. That's multi-version concurrency control.

Those dead row versions aren't reclaimed immediately: they sit in the table file until vacuumed. So a table with high update or delete churn, plus autovacuum falling behind, accumulates dead tuples the table file never shrinks to remove. That's table bloat. The file on disk grows well past the size of the live data, sequential scans slow down because they're scanning dead rows too, and indexes bloat right along with the table.

```mermaid
graph LR
    R1["Row v1<br/>(live)"] -->|UPDATE| R2["Row v2<br/>(live)"]
    R1 -.->|"marked dead,<br/>not reclaimed yet"| Dead["Dead tuple<br/>(still in file)"]
    Dead -->|"VACUUM runs"| Free["Space marked<br/>reusable"]
    Dead -.->|"VACUUM falls behind"| Bloat["Table bloat<br/>(file grows, scans slow)"]
```

A long-running transaction is the classic silent cause. It holds back the oldest snapshot autovacuum has to respect, so even a healthy autovacuum schedule can't reclaim tuples newer than that snapshot until the long transaction finally commits or aborts.

**What they're testing:** whether "why is this table 40GB when it holds 4GB of data" is a question you can answer. The word they're waiting for is bloat, and then the long-running transaction behind it.

**Try it:** run `SELECT pg_size_pretty(pg_total_relation_size('orders'));` before and after a loop of a few thousand no-op `UPDATE`s on the same rows without vacuuming, and watch the number grow even though the row count and logical data size didn't change.
{{% /qa %}}

---

## What to drill first

If you're earlier in your career and short on time, start with [4](#4) (N+1) and [5](#5) (the slow-query checklist). Those turn up in ordinary backend work every week, long before anyone asks you about internals.

**[Databases & Database Optimization](#databases--database-optimization):** worth its own drilling pass. Indexing, isolation levels, and locking and deadlocks ([6](#6), [8](#8), [9](#9)) come up constantly in architect-level interviews, even outside a formal system design segment.

**[Advanced Query Techniques](#advanced-query-techniques):** [18](#18) (window functions) and [19](#19) (recursive CTEs) are the two most likely to get a "write this query" follow-up. Have the `PARTITION BY`/`OVER` syntax and the anchor-plus-recursive-term shape ready to write from memory, not just recite. [12](#12) is the one people get wrong under pressure, because the `NULL` behaviour is genuinely counterintuitive.

**[Query Planning, Storage & Concurrency Internals](#query-planning-storage--concurrency-internals):** [27](#27) (join algorithms) and [30](#30) (MVCC and bloat) are the highest-yield for a senior or architect round, since they test whether you understand what the database is doing under an `EXPLAIN ANALYZE` plan rather than just how to read one. [28](#28) is worth rehearsing next to [sharding]({{< ref "interview-prep-system-design.md" >}}#3) (Part 4): interviewers often ask both back to back to see if you conflate them.

If you're short on time otherwise, [25](#25) and [26](#26) pay off fastest. They're the two that turn "the database is slow" into an actual first move.

---

Part 3 of 7 · [Interview Prep](/interview-prep/) · ← Previous: [Part 2 — Coding Patterns](/interview-prep-coding-patterns/) · Next: [Part 4 — System Design & Distributed Systems](/interview-prep-system-design/) →
