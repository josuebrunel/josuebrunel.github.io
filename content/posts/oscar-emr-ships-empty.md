---
title: "OSCAR EMR Ships Empty (So I Loaded 1,163 Fake Patients Into It)"
date: 2026-08-13
description: "OSCAR EMR has no sample data out of the box. Here's how Synthea and a Go CLI filled it with 1,163 synthetic patients, and what a 15-year-old EMR schema taught me about healthcare data."
tags: ["golang", "healthcare", "emr", "data-migration", "synthea", "oscar"]
---

I wanted to try OSCAR EMR for a project. OSCAR ships empty.

No demo patients, no sample charts, no seeded data of any kind: just a
login screen and a database shaped like a full electronic medical record
with nothing in it. You can't evaluate an EMR, or demo one, by staring at
an empty schema. I needed patients: people with allergies, prescriptions,
lab results, a messy medical history. Real patients weren't an option, so
I reached for [Synthea](https://synthetichealth.github.io/synthea/), which
generates exactly that kind of synthetic-but-realistic history, and set out
to load a CSV export of a few thousand fake people into OSCAR.

That sounded like a CSV-to-database problem. It wasn't. It turned into
reading a 15-year-old Ontario EMR's schema like an archaeologist,
decompiling a Java class to find a missing null check, and eventually
writing a Go CLI that goes from an empty `oscar` database to **1,163**
fully-populated patients in under ten minutes. Here's what I learned along
the way.

## The schema is not a data model, it's a history

The tool writes straight to MariaDB with `database/sql`, skipping OSCAR's
own REST API and its Java/Hibernate layer entirely. For synthetic dev data
that's a reasonable trade: speed and control, at the cost of every
invariant Hibernate would normally enforce for you. More on that trade
later, because it comes back to bite.

To do that honestly, I needed OSCAR's *real* schema, not a stand-in. The
first version shipped with a toy 246-line schema, six tables, enough to
get something moving. A real migration test needs the real thing: the
actual ~580-table Open-O/OSCAR 19 schema, vendored as-is from upstream.
`oscarinit.sql` alone is **13,209** lines. `oscardata_bc.sql` is another
**20,919**. Loading that in the right order, and discovering that order
*matters*, is where the archaeology starts.

Two examples:

- `bc_pharmacies.sql` references a `pharmacyInfo.uid` column that doesn't
  exist yet when it runs: it's only added by `oscarinit_2025.sql`, a file
  that loads *after* it in the upstream install order. I skipped
  pharmacies since I didn't need them, but the bug is still sitting there
  in OSCAR's own installer, unnoticed because nobody's tried to load that
  file in isolation.
- `dxresearch_code`, the column that stores a patient's problem-list code,
  is a `varchar(10)`. Fine for short legacy codes. Not fine for modern
  SNOMED codes, **652** of which in my export ran longer than 10 characters.
  I widened the column in my dev bootstrap, but any real deployment
  ingesting SNOMED-coded data hits the exact same wall.

You don't learn either of these from documentation. You learn them by
trying to pour real-shaped data through the pipe and watching where it
backs up.

## Some data doesn't fit anywhere

The `dxresearch` table, OSCAR's problem list, has no description column at
all. Only a code survives, tagged `coding_system = 'SNOMED'`. Whatever
free text Synthea generated for that condition just doesn't have anywhere
to go: it's dropped structurally, not by a bug, by design.

Immunizations taught me a different lesson: OSCAR has *two* tables for the
same concept. A legacy `immunizations` table, which the application no
longer reads, and a modern `preventions` table, which is what the GUI
actually queries. The legacy one is just an obsolete text blob nobody
bothered to remove. Write to the wrong one and everything looks correct in
your `INSERT` statement and invisible in the app. An EMR schema this old
isn't one data model, it's several generations of one stacked on top of
each other, and you have to know which layer is still alive.

## Synthea has its own opinions

Not every quirk was OSCAR's fault. `imaging_studies.csv` writes one row
per DICOM *instance*, not per study: a single CT scan that's one clinical
event in real life shows up as dozens or hundreds of rows in the export.
Loading that naively would've flooded OSCAR's `measurements` table with
what looks like the same scan repeated 500 times. I collapsed rows by
patient, date, modality, and body site before writing anything, so one
study became one measurement, the way a clinician would actually read it.
The synthetic data generator has its own model of the world, and it isn't
always OSCAR's.

## The data was right. The screen lied anyway.

Two bugs looked identical from the outside: a patient's medication list
and allergy list rendered blank in the GUI, even though the rows were
sitting in the database, correct, queryable, `SELECT *`-able.

The medication one turned out to be a column mismatch. OSCAR's
`ListDrugs.jsp` renders the medication name by calling
`RxPrescriptionData.getFullOutLine(drug.getSpecial())`: it never touches
the `BN` column at all. I'd been writing the drug description into `BN`
and leaving `special` empty. Correct data, wrong column, blank screen.

The allergy one was the same shape: `casemgmt/allergies.jsp` renders
`reaction` as its own column, separate from `description` (the allergen
itself, like "Latex (substance)"). I was only writing `description`.
Every allergy showed up with no reaction, every time, silently.

A third bug was uglier: a `NullPointerException` that only fired when
opening a patient's Encounter view. There's no source jar for OSCAR's
compiled classes, so I decompiled the live one with `javap -c -l` and read
the bytecode, the same no-docs-read-the-artifact-instead move as
[reverse-engineering the Pulse Series One's BLE protocol]({{< ref "building-pulsedash.md" >}}). `RxPrescriptionData.toPrescription` was unboxing
`drug.getRepeat().intValue()` with no null check, while the field right
next to it in the same method *did* have one. `hide_cpp`, `takemin`,
`takemax` all map to Java primitives on OSCAR's Hibernate entity: a NULL
there isn't a missing value, it's an exception the first time anyone views
that patient.

The fix in all three cases was the same: write the row Hibernate would
have insisted on if I'd gone through it. Skipping an ORM doesn't remove
its invariants. It just hands you the job of enforcing them yourself.

## Where Go actually earned its keep

The first version loaded whole CSVs into memory. Fine for a few thousand
patients. It falls over on a real Synthea export, which can run well past
20GB. The rewrite is where Go's standard library did most of the work.

- `streamCSV` reads row by row with `encoding/csv`'s `ReuseRecord = true`,
  so there's no per-row allocation for the raw record buffer.
- Patients get batched (500 at a time, by default). For each batch, every
  per-patient CSV gets re-streamed from disk and filtered down to just
  that batch's patient IDs. It trades extra I/O for a hard ceiling on
  memory, which is the whole point: an export "well over **20GB**" ingests
  without OOMing, no matter the machine.
- A small worker pool does the writing, the same manual goroutines-and-WaitGroup
  instinct as [Simple Concurrent Web Scraping in Go]({{< ref "simple-concurrent-web-scraping-in-go.md" >}}):

```go
jobs := make(chan Patient)
results := make(chan patientResult)

var wg sync.WaitGroup
for i := 0; i < workers; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        for p := range jobs {
            results <- ingestPatient(ctx, db, p)
        }
    }()
}
go func() { wg.Wait(); close(results) }()
```

  Each worker opens its own connection and runs each patient in its own
  transaction, so nothing contends for the same rows. Patients are the
  natural unit of work, which makes the fan-out almost boring to write.
- Idempotency matters more here than in a typical batch job, because I
  reran this tool constantly while chasing the bugs above. A deterministic
  hash of the Synthea patient ID becomes the `demographic.hin`, and every
  insert checks a natural key before writing. Rerun it and it converges
  instead of duplicating.

The payoff, on the same dataset: **~18 minutes serial down to ~10 minutes
parallel** for a fresh load, and **~18 minutes down to ~3.5 minutes** for
an idempotent rerun against already-loaded data.

None of this is exotic. That's the point: the same [boring beats
clever]({{< ref "my-simple-and-happy-stack.md" >}}) instinct as everywhere
else. Goroutines and channels made the worker pool small enough to read in
one sitting instead of a class hierarchy. A single static binary sits next
to a Tomcat-and-MariaDB stack without dragging in a second runtime. And typed Go structs on the
Synthea-to-OSCAR field mapping meant a wrong column showed up as a compile
error, not a blank cell three screens deep in the GUI.

## What works, what doesn't (yet)

**What works:**
- 1,163 synthetic patients, fully populated, GUI renders correctly across
  meds, allergies, labs, imaging, and problem lists
- Streaming + batching handles exports well past 20GB without OOMing
- Idempotent reruns in under 4 minutes, which made debugging the schema
  and GUI issues above actually tolerable
- Skipping OSCAR's REST/Hibernate layer is fine, as long as you're honest
  that it's *only* fine for throwaway synthetic data

**What doesn't (yet):**
- `claims.csv`, `devices.csv`, `organizations.csv`, `payers.csv`,
  `providers.csv`, and `supplies.csv` all sit unused in the export: never
  ingested
- Only the first allergy reaction gets captured; a second reaction, if
  Synthea generates one, is dropped
- Provider access to a patient's program isn't handled out of the box: I had
  to manually seed `program_provider` grants, because the vendored CAISI
  data doesn't grant any provider access to any program by default

## The payoff

Final count: 1,163 patients, **369,205** measurements spanning **390** distinct
measurement types, matching the source data's distinct-code count exactly.

Once it was loaded, the next problem was a nicer one to have: *which*
fake patient tells the best story in a demo. So I queried the loaded data
and built a small cheat sheet: patient #257, "Mertz280, Rozella39," tops
the list with nearly **10,000** rows across every category; #514 has the
heaviest medication and problem list; #831 is the one to pull up if
someone wants to see CT imaging. OSCAR isn't empty anymore, and when I
need to demo it, I already know exactly which name to search for.
