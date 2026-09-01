---
title: "Generating Synthetic OSCAR Patients Without the 20GB Synthea Download"
date: 2026-08-17
description: "Getting a Synthea population usually means a Java CLI run and a bulk export that dwarfs what OSCAR actually needs. Here's an in-memory, chunked patient generator that skips all of it."
tags: ["golang", "healthcare", "emr", "data-migration", "synthea", "oscar"]
---

Last time, I loaded **1,163** synthetic patients into [OSCAR EMR]({{< ref "oscar-emr-ships-empty.md" >}}). That post was mostly about what happens after you have the data: the schema archaeology, the load-order bugs, the rows that structurally don't fit anywhere. What it didn't dwell on is how I got that data in the first place. Synthea runs on Java and dumps a CSV/FHIR export that can run into the tens of gigabytes, all for a population you're going to shrink down to about ten tables' worth of fields.

That part bugged me enough to go back and remove it. `-generate` fabricates patients directly in memory, in bounded chunks, with no Synthea, no Java, no CSV export sitting on disk. Same shape of data going into OSCAR, none of the ceremony getting there.

## Most of that export was never going to be used

Synthea is a clinical simulator. It models disease progression, comorbidities, care pathways over a patient's simulated lifetime, and dumps all of it as CSV or FHIR bundles. That's the right tool if you need clinically plausible trajectories. It's a lot of tool if what you actually need is: rows in `demographic`, `allergies`, `dxresearch`, `drugs`, `preventions`, `casemgmt_notes`, and a handful of other OSCAR tables, referentially consistent enough that the GUI doesn't choke on them.

I'd already done the work of figuring out what that target shape looks like, table by table, the hard way, in the last post. Once you know the shape, you don't need a full clinical simulation to produce it. You need names, dates, a handful of curated code tables for conditions and meds and immunizations, and something that ties records together by patient ID without contradicting itself.

## What `-generate` actually does

It's a new flag on the same CLI, sitting next to `-csv-dir`:

```go
flag.IntVar(&cfg.generate, "generate", 0, "fabricate this many synthetic patients in memory instead of reading -csv-dir (0 = disabled, use CSV mode). Processed in -patient-batch-size chunks, each generated then ingested then discarded, so memory stays bounded regardless of the total.")
flag.Int64Var(&cfg.generateSeed, "generate-seed", 0, "seed for -generate's RNG (0 = time-seeded, a fresh population every run). Set a nonzero value to reproduce the same generated population across runs.")
```

In use:

```bash
./synthea-oscar -generate 10000 -patient-batch-size 1000 \
  -dsn "oscar:oscar@tcp(127.0.0.1:3306)/oscar"
```

No `-csv-dir`, because there's no CSV. `-dry-run` is explicitly rejected when `-generate` is set: dry-run exists to preview what a CSV import would do before touching the database, and there's nothing to preview for data that doesn't exist until the moment it's generated.

## Chunking is the whole trick

The `-patient-batch-size` flag already existed before this feature. It came out of an earlier fix, scaling the CSV ingest past memory limits by re-scanning the input in batches instead of holding the whole population in memory at once. `-generate` reuses the same discipline, just on the producing side instead of the reading side:

```go
for generated := 0; generated < cfg.generate; generated += chunkSize {
    data := generateChunk(n, rng)
    bOK, bFail, err := ingestPatientBatch(ctx, db, cfg, data)
    // ...
}
```

Each chunk gets generated, ingested, and dropped before the next one is built. Ask for 10,000 patients and the process never holds more than one chunk's worth of records in memory at a time. The total requested is unbounded in the same way the CSV path's total was unbounded: you're not trading one memory ceiling for another, you're just moving where the batching happens.

## One writer, two producers

The more interesting change is underneath: the old `ingestBatch` function got split so its database-writing internals live in a new `ingestPatientBatch(ctx, db, cfg, data)`, taking a `batchData` struct: patients, allergies, conditions, meds, immunizations, consults, diagnostics, imaging, procedures, care plans, each keyed by patient ID. Both the CSV path (`ingestBatch`, parsing Synthea's export) and the new in-memory path (`generateChunk`) build that same struct and hand it to the same writer.

That matters more than it sounds like. The transactional insert logic, the worker-pool fan-out, the idempotent `hin` hashing, all the correctness work from the last post's Go rewrite, none of that got duplicated for the generator. It's the same battle-tested code writing the rows; only where the rows come from changed.

## What this deliberately isn't

`generate.go`'s header comment says it plainly:

> This is not a clinical simulator: there's no disease progression or comorbidity modeling like Synthea's, just structurally valid, referentially consistent, varied-enough records drawn from small curated code tables. Good enough for a demo/load-test population, not a Synthea replacement.

Concretely: a patient gets 1-6 conditions pulled from a `conditionTemplates` table, and medications are derived from whatever conditions that patient has. Allergies, immunizations, consults, diagnostics, and imaging come from their own curated slices, and procedures and care plans are generated together as clinical events. Names, streets, and locales all come from small hardcoded lists. Patient IDs are minted by `randID`, a UUID-shaped random string with no relationship to Synthea's own IDs. It's internally consistent, plausible-looking data. It is not a simulation of anyone's actual disease trajectory, and it doesn't pretend to be.

If you need clinically realistic progression, comorbidity patterns, or anything research-grade, that's still Synthea's job, and `-generate` isn't trying to take it.

## The idempotency you give up

The CSV path has a property I leaned on heavily in the last post: re-running the ingest is a no-op, because `fakeHIN` is a hash of Synthea's own stable UUID for each patient. Run it twice, get the same 1,163 patients, no duplicates. That's also where most of the "~18min → 3.5min" rerun speedup came from.

`-generate` doesn't have that. Every run mints fresh random patient IDs, so running `-generate 10000` twice doesn't refresh a population, it adds a second one on top of the first. `-generate-seed N` gets you a reproducible population, same names, same conditions, same everything, across runs with the same seed, but reproducible isn't the same as idempotent. Two runs with the same seed against a fresh database produce identical data; two runs with the same seed against the *same* database still produce two populations. If you need re-runs to converge rather than accumulate, this isn't that tool yet.

## When to reach for which

`-generate` is what I use now for anything that just needs plausible-looking volume: local dev seeding, load testing the ingest path itself, demo environments where nobody's going to audit whether patient #4,832's diabetes progressed realistically. It has no external dependencies and no disk footprint beyond the database it's writing to.

Real Synthea exports still earn their weight when the fidelity of the data matters, disease trajectories, comorbidity realism, anything closer to research-grade synthetic data. That's a different job than "give OSCAR something to render," and `-generate` was never trying to do it.

## The number that made it worth doing

From the commit that shipped this: **10,000** patients generated and ingested in **1m14s**, zero failures, zero orphan or duplicate rows. No Java, no CSV export, no **20GB** sitting on disk waiting to be parsed down to the handful of fields OSCAR was ever going to use. Same destination as before, a much shorter way to get there.

## Post-publish update: backfilling measures into existing patients

`-backfill-measure` joined the CLI after this post went out. Where `-generate` fabricates brand-new patients, backfill does the opposite: it adds one data domain's synthetic records to patients that already exist in a running OSCAR instance, and leaves everything else alone.

It queries `demographic WHERE patient_status = 'AC'` (capped by `-limit`, 0 = all active patients), reads each patient's real birth date and sex back out of the database, and runs them through the same generators `-generate` uses. So a screening like mammography only ever lands on a woman aged 40-74, computed from the patient's actual recorded age and sex instead of fabricated alongside a new chart:

```bash
./synthea-oscar -backfill-measure screening -limit 500 \
  -dsn "oscar:oscar@tcp(127.0.0.1:3306)/oscar"
```

Six measures exist so far: `screening`, `immunizations`, `allergies`, `conditions`, `medications`, and `consultations`. The `medications` one even scales its count off the patient's existing condition count, so a patient with more problems gets more drugs, same rule as `-generate`. Diagnostics, imaging, procedures, and care plans aren't backfillable yet: they write into `measurements`, which needs its `measurementType` rows seeded first, and the backfill worker pool doesn't have that pre-seed step.

The part I liked most is that backfill fixes the idempotency gap this post complained about. `-generate` re-running mints a second population; backfill converges instead. Every measure checks for an existing row of that type per patient before inserting, so re-running only fills in what's missing. Not always in one run: `screening` and `immunizations` converge within a few runs, while `allergies` and `conditions` draw from a bigger template pool and can take more. The guarantee is "no duplicates," not "one run reaches the final state."

One concurrency detail is the mirror image of the chunking story above. In `-generate` the generators run single-threaded before any goroutine starts, so one seeded RNG is safe. In backfill the generators run *inside* the worker pool, one goroutine per patient, so a shared `*rand.Rand` would be a data race. The fix is the same shape as the rest of the codebase: each worker gets its own RNG, seeded from the base seed plus its worker ID.

`-dry-run` behaves differently too. The CSV and `-generate` dry-runs never touch the database. Backfill's dry-run still connects and reads existing patients, because it has to know who to generate for; it just skips the insert and commit, logging what it would have written instead.
