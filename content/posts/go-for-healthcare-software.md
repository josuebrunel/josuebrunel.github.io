---
title: "Go for Healthcare Software: 3 Problems, One Language"
date: 2026-09-01
description: "Generating fake patients, running recurring jobs, and keeping an AI layer honest and de-identified downstream of an EMR: 3 different problems, and Go's answer to each one still fits in a small file."
tags: ["golang", "healthcare", "emr", "concurrency", "architecture", "ai"]
---

2 posts ago I loaded 1,163 fake patients into [an EMR that ships with nothing in it]({{< ref "oscar-emr-ships-empty.md" >}}). Last post, I found [a faster way to make more of them]({{< ref "generating-synthetic-oscar-patients-without-synthea.md" >}}). Both posts were about getting data in. This one is about what happens next: moving that data through recurring background work, and putting an AI layer on top of it that has to reach into the same data safely. 3 jobs that don't look alike on the surface, and Go's answer to each one still fits in a small file.

## What we're building, and why the data has to be fake

What's sitting on top of all that fake data is still under wraps, stealth mode has its reasons, but here's the shape of it: something that sits on top of an EMR and uses AI to help physicians do part of their job. Whatever the specifics, the requirement underneath is the same one any EMR-adjacent tool runs into first: you need patients in the database to build against, let alone demo. Hundreds of them, connected across tables the way real patients are: a diagnosis links to a medication, a screening links to an age and a sex, a lab result links to a date that has to make sense next to the others.

Real patient records would do that job perfectly. They're also the one thing you shouldn't reach for while writing and testing code, and once there's an AI layer reading that data too, the case against using the real thing only gets stronger. Health data carries weight a typical SaaS dataset doesn't. A name, a diagnosis, a medication list: ordinary facts on their own. Together, in a system a developer is actively debugging, printing to logs, copying into a bug report, they're exactly what health-privacy regulation exists to protect, and exactly what you don't want sitting in a dev database with `SELECT *` access for anyone on the team. Using real records to build a demo isn't a shortcut. It's a liability with a due date.

So the actual requirement was never "load some data." It was "generate thousands of realistic, internally consistent, fake patients, fast enough that waiting for a dataset is a non-issue." That stopped being a data modeling problem. It became a concurrency problem.

## How one Go CLI faked the population

It's a single Go binary with three modes: `-csv-dir` imports a Synthea export, the default path from [the CSV-loading post]({{< ref "oscar-emr-ships-empty.md" >}}); `-generate` fabricates patients in memory; `-backfill-measure` adds one data domain's records to patients that already exist in a running OSCAR instance. Each mode lives in its own small file, and neither needed a framework.

`-generate` isn't a clinical simulator. It's a few curated code tables producing the same record shapes a CSV export would, built `-patient-batch-size` at a time, each chunk generated, ingested, then discarded, so memory stays bounded no matter the total. The database-writing half is the same `ingestPatientBatch` the CSV path uses, unchanged. `-backfill-measure screening` works the other way: it reads active patients' real birth dates and sex back out of the `demographic` table and runs the same generators over them, which is how a mammography record only ever lands on a woman aged 40-74. It's also idempotent per patient per record type, so re-running converges instead of accumulating.

Both modes fan out over the same worker pool, 16 goroutines by default, each patient in their own transaction. The race that only shows up once you go concurrent is the subtle one: in backfill mode the generators run inside the workers, and a `math/rand` source shared across them is a data race. The fix was one line per worker, its own generator seeded from the base seed plus its worker ID, so a debug run stays reproducible and a production run stays race-free. The payoff: 10,000 patients, their full health records along with them, generated and ingested in 1m14s, zero failures. That's the embarrassingly parallel half of this story: independent patients, fanned out over goroutines, gathered back through a channel. The dashboard reading that data back out doesn't have that problem. It has a different one.

## RiverQueue: one queue for every recurring job

Extraction has to run nightly. Measure computation has to run monthly. Neither one is the fan-out problem the generator has, independent patients processed in parallel, it's recurring, scheduled background work that has to run reliably without falling over or double-running. For that, the dashboard reaches for [RiverQueue](https://riverqueue.com/), a job queue library that's itself written in Go and runs on the same Postgres database the dashboard already has open.

What RiverQueue buys is the boring infrastructure nobody wants to hand-write twice. A job insert happens inside the same database transaction as the work that triggered it, so a job never goes missing between "the code decided to schedule this" and "the queue actually has it." Failed jobs retry with backoff automatically, no cron script polling a table and hoping. Everything lives in Postgres tables the dashboard already migrates and backs up, not a second datastore with its own uptime to babysit. The integration surface for one recurring job is this small:

```go
type MeasureComputeWorker struct {
    river.WorkerDefaults[MeasureComputeArgs]
    Computer *MeasureComputer
}

func (w *MeasureComputeWorker) Work(ctx context.Context, _ *river.Job[MeasureComputeArgs]) error {
    return w.Computer.RunAll(ctx, time.Now())
}
```

Embed the defaults, implement one method. No Redis, no RabbitMQ, no separate broker process to keep alive and monitor, and no second language runtime bolted on just to run a task queue. It's the same reason a Go binary was the right call for the generator, applied to a completely different concurrency shape: a hand-rolled worker pool for fanning out over patients, a typed library, also written in Go, for running the same handful of jobs on a schedule, and neither needed a framework to get there.

Because this eventually points at real patient data, not just synthetic, the same plainness shows up in a few small, checkable guardrails around it. The service that computes measures connects to the EMR through a database user that can only read, enforced by the database itself. A published rate sits behind a trigger that refuses `UPDATE` or `DELETE` outright. A rate computed from too small a cohort doesn't get published at all. One of these caught something real this week: before publishing a new snapshot, the pipeline compares this run's data volume against the last comparable run, and it refused to publish when that swing hit 322%, logging why instead of guessing. Every one of those is a migration, a trigger, or a comparison between two integers, and none of them care whether the thing reading the result next is a chart or a model.

The same queue runs the de-identification pass that stands between raw EMR data and anything else in the system, and that includes the AI layer. Patient records keep a birth year, never a full date of birth. Postal codes get trimmed down to a forward sortation area, nothing more precise. That job runs on its own schedule, the same way it always has, whether or not a model is on the other end of the data. The AI layer doesn't get a special path around it. It's just one more consumer standing downstream of a queue that was already there.

That's the part that turned out easy: the assistant never needed its own anonymization step, because reaching for already-de-identified data was the default, not a case someone had to remember to add. What sits on top of that is a small, ordinary layer of Go: typed functions for whatever the assistant is allowed to look up, wired into a loop that keeps talking to the model until it stops asking for more. No prompt-chaining framework, no separate orchestration service, nothing beyond what any Go developer already knows how to build.

The part that actually needed care wasn't the loop, it was seeing into it. A system that decides on its own what to look up and how to use it isn't something you leave as a black box, not with patient data on one side of it and a model's judgment on the other. Every call in and out gets logged the same plain, structured way as everything else in this codebase, no extra ceremony just because a model is involved: what was asked, what got looked up, what came back. When the model gets something wrong, and eventually it will, that log is the difference between pointing at exactly what happened and shrugging. Observability isn't a nice-to-have here. With this much at stake, it's the only way to actually trust a system you didn't write the judgment for.

## What 2 Go processes cost to run

Here's where the arithmetic gets almost unfair. On a small demo VM, 2 vCPUs, about 8GB of RAM, the whole stack runs side by side: Postgres for the dashboard, the EMR's own MariaDB, the EMR's Java and Tomcat web app, and the dashboard's 2 Go services. At rest:

| Container | CPU | Memory |
|---|---|---|
| Go server | ~0% | 31.8 MiB |
| Go worker | 0.5% | 11.2 MiB |
| Postgres | 0.2% | 164.9 MiB |
| EMR's own database | 0.0% | 141.9 MiB |
| EMR's Java/Tomcat app | 0.2% | 814.7 MiB |

The 2 Go services together use about 43 MiB of RAM and well under 1% CPU combined. The Java EMR alone, doing nothing but sitting there ready for a browser, uses roughly 19x that much memory by itself.

The container images tell the same story before anything even runs:

| Image | Size |
|---|---|
| Go server | 84.6 MB |
| Go worker | 34 MB |
| EMR's Java/Tomcat app | 1.81 GB |

That's a 21x difference, and none of it took tuning: `CGO_ENABLED=0 go build` and a small base image gets you there by default. On that VM, 5 containers ran together comfortably with almost 4GB still free, and nearly all of the machine's budget went to the one piece nobody on this project controls, the third-party EMR, not the Go services actually doing the work.

## A pattern, not a coincidence

Add it up and it's a pattern, not a coincidence. A hand-rolled worker pool cut an 18-minute serial CSV load down to 10, and the generator does 10,000 patients in just over a minute. A job queue, also written in Go, needed one embedded struct and one method to take over recurring background work with no separate broker, and it was already the thing standing between raw EMR data and anything downstream by the time the AI layer showed up looking for a way in. That layer was easy to build for the same reason, plain typed functions and a small loop, and easy to keep honest, the same structured logging as everywhere else in the codebase, wrapped around every call it makes. None of it lowers the stakes of putting a model next to a health record, that's a cost the model adds all on its own, but none of it made those stakes any harder to see, either.

Every one of those is a different problem, and Go's answer to each one was the same shape: plain types you can read start to finish, the standard library where it's enough, one well-chosen dependency where it isn't, nothing hidden in between. That's not a small thing when the two things you're building on are somebody's health record and a model you don't fully control. Health data doesn't forgive a wrong column the way a marketing dashboard does. An AI layer doesn't forgive a swallowed error the way a batch script does. Go's whole personality, plain and a little stubborn about hiding nothing, turns out to fit that combination better than I expected going in.
