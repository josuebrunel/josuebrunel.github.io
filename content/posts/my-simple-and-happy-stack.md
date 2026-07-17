---
title: "My SaaS Tech Stack: Chosen by an Engineer Who Likes Simplicity"
date: 2026-02-03
description: "Why my SaaS uses a boring, simple tech stack - and why that's exactly what makes it scalable."
tags: ["saas", "golang", "htmx", "postgres", "architecture"]
draft: false
---

Building a SaaS is full of important decisions.

Tabs or spaces.  
Dark mode or *forced* dark mode.  
And of course: *Which tech stack will ruin my weekends the least?*

After experimenting with shiny frameworks, clever abstractions, and architectures that looked amazing in diagrams, I landed on a simple rule:

> **If a system is easy to understand, it's hard to kill.**

Every tool here is chosen to *reduce* complexity, not manufacture it.

---

## Simplicity Is Not a Lack of Ambition

"Simple stack" often gets translated as:
- Small product
- Low scale
- Temporary solution

In practice, the opposite is usually true.

The first thing that breaks in a growing SaaS is not the database.  
It's not performance.  
It's **developer velocity and confidence**.

Complex systems slow you down long before traffic ever does. Every abstraction layer, every event bus, every microservice you add before you need it is a tax on future you. I've been that future me, staring at a production incident at 2 AM, trying to trace a request through five services, three queues, and a cache that may or may not have the data I need.

So I default to simple and let reality force complexity later. Reality rarely shows up.

---

## Go: Because I Prefer Code Over Sorcery

Go is the foundation of everything.

What I like about Go:
- One static binary
- Explicit behavior
- Predictable performance
- No hidden runtime theatrics

Go code reads like instructions, not riddles. Here's a typical handler in this stack:

```go
func (h *Handler) ListInvoices(c echo.Context) error {
    invoices, err := h.queries.ListInvoices(c.Request().Context())
    if err != nil {
        return c.String(http.StatusInternalServerError, "something went wrong")
    }
    return render(c, pages.Invoices(invoices))
}
```

That's it. Get data, render HTML, return. No serialization layer, no DTO mapping, no JSON contract to maintain between frontend and backend. The handler fetches a `[]db.Invoice` slice and passes it straight to a Templ component that knows how to render it.

When something breaks, I don't need a debugger, a blog post, and a priest. I need `grep` and a cup of coffee. That clarity compounds over time.

---

## Echo v5: A Web Framework That Knows When to Shut Up

For HTTP routing and middleware, I use **Golang Echo v5**.

The setup is minimal:

```go
e := echo.New()
e.Use(middleware.Logger())
e.Use(middleware.Recover())

api := e.Group("/api", h.RequireAuth)
api.GET("/invoices", h.ListInvoices)
api.POST("/invoices", h.CreateInvoice)
api.POST("/invoices/:id/void", h.VoidInvoice)
```

Echo hits a sweet spot:
- Fast
- Minimal
- Well-structured
- Doesn't fight Go's standard library

It gives me clean routing, sensible middleware, and context handling without drama. Echo doesn't try to become *the architecture*. It stays in its lane and lets the application logic stay obvious.

---

## Golang Templ: HTML That Refuses to Lie

I render HTML using **Golang Templ**.

```templ
package pages

templ Invoices(invoices []db.Invoice) {
    <div class="overflow-x-auto">
        <table class="table">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Customer</th>
                    <th>Amount</th>
                    <th>Status</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                for _, inv := range invoices {
                    <tr>
                        <td>{ inv.ID }</td>
                        <td>{ inv.CustomerName }</td>
                        <td>{ fmt.Sprintf("$%.2f", inv.Total) }</td>
                        <td>
                            <span class="badge badge-{ statusColor(inv.Status) }">
                                { inv.Status }
                            </span>
                        </td>
                        <td>
                            <button hx-post={ fmt.Sprintf("/api/invoices/%d/void", inv.ID) }
                                    hx-target="closest tr"
                                    hx-swap="outerHTML"
                                    class="btn btn-ghost btn-xs">
                                Void
                            </button>
                        </td>
                    </tr>
                }
            </tbody>
        </table>
    </div>
}
```

Why Templ instead of Go's `html/template`?
- Type-safe templates. If I rename a struct field and forget to update the template, the app simply won't compile.
- Compile-time errors instead of runtime panics.
- No string-based HTML chaos with `.` and `$` and pipe functions.

This is the kind of tough love I respect. Templates live close to the logic, refactors are safe, and runtime surprises are rare.

---

## HTMX: Interactivity Without a Frontend Midlife Crisis

Most SaaS products don't need:
- Client-side routers
- State management libraries
- JavaScript build systems that rival the backend

They need forms, buttons, tables, and partial updates. HTMX handles all of that by extending HTML with attributes.

Notice the `hx-post`, `hx-target`, and `hx-swap` attributes in the Templ snippet above. That button sends a POST to `/api/invoices/:id/void`, and the response HTML replaces the table row. No fetch wrapper, no loading state boilerplate, no JSON parsing.

The server returns HTML, the browser swaps it in:

```go
func (h *Handler) VoidInvoice(c echo.Context) error {
    id := c.Param("id")
    invoice, err := h.queries.VoidInvoice(c.Request().Context(), id)
    if err != nil {
        return c.String(http.StatusInternalServerError, "failed to void")
    }
    return render(c, pages.InvoiceRow(invoice))
}
```

The endpoint returns a fragment - just the row, not the full page. HTMX swaps it into the DOM. No SPA, no hydration bugs, no "why is this state different over here?" moments. Just HTML behaving responsibly.

---

## PostgreSQL: Shockingly Good at Being a Database

PostgreSQL handles transactions, constraints, concurrency, and reporting. Incredible, considering that's *literally its job*.

More specifically, I reach for Postgres features that eliminate entire categories of bugs:

- **CHECK constraints** to enforce business rules at the database level, not just in application code
- **Generated columns** for derived data that can never drift out of sync
- **Foreign keys** with cascade deletes so I can't orphan records
- **Partial unique indexes** for soft-delete scenarios where only one active row should exist

Instead of inventing clever data storage schemes, I let Postgres do what it has been doing reliably for decades. Simple schema, clear queries, long runway.

---

## RiverQueue: Background Jobs Without Summoning Another System

Every SaaS eventually needs background jobs: emails, webhooks, async processing, long-running tasks.

Instead of introducing Kafka, RabbitMQ, or a new operational headache, I use **RiverQueue**, which runs directly on PostgreSQL.

```go
type SendEmailWorker struct {
    mailer *mail.Client
}

func (w *SendEmailWorker) Work(ctx context.Context, job *rivertypes.Job[SendEmailArgs]) error {
    return w.mailer.Send(ctx, job.Args.To, job.Args.Subject, job.Args.Body)
}
```

Enqueueing a job is a single function call:

```go
_, err := riverClient.Insert(ctx, SendEmailArgs{
    To:      "user@example.com",
    Subject: "Your invoice is ready",
    Body:    renderEmail(invoice),
})
```

One datastore, one backup strategy, one mental model. No broker cluster to maintain, no network partition to worry about, no schema synchronization between systems. Background jobs should be boring, and RiverQueue makes them boring in the best way.

---

## Redis: Powerful, Dangerous, Used With Adult Supervision

Redis is fantastic. Redis is also how many architectures quietly become complicated.

In this stack, Redis is:
- A cache for expensive queries
- Short-lived session state
- Rate limiter counters

It is **not** a source of truth.  
It is **not** the backbone of the system.

Used intentionally, Redis speeds things up without turning the app into a distributed puzzle. If Redis goes down, the app still works - it's just slower.

---

## CSS: I Refuse to Argue With My Stylesheet

For styling, I optimize for semantic HTML, accessibility, and low maintenance.

That's why I use:
- **PicoCSS v2** for clean defaults that make unstyled HTML look presentable
- **DaisyUI** when utility components like dropdowns and modals save time
- **PicoDaisy** (https://josuebrunel.github.io/picodaisy/), my own hybrid library that bridges the two

The goal isn't flashy UI - it's shipping changes without emotional damage. A button should look like a button without me writing 40 lines of CSS.

---

## The Unexpected Benefit: Operational Peace

This stack has a feature I value more than benchmarks:

**It's calm to operate.**

Deployments are a single binary scp'd to a server. Rollbacks are the previous binary. If I want containers, it's a `Dockerfile` with `FROM alpine:latest` and `COPY myapp .` - no distroless multi-stage orchestration dance.

Failures are understandable. When something breaks, the signal-to-noise ratio is high. A Go stack trace tells me exactly which line panicked. An Echo error log tells me which route and method. A Postgres query log tells me which query is slow.

No frontend-backend negotiations about API contracts. No distributed-system cosplay. Just a small set of tools working together quietly.

---

## The Specifics

Zero-dependency binary deployment means I can run this stack on a $5 VPS and sleep well. The binary, a PostgreSQL connection string, and an environment file are all I need to go from zero to production.

CI/CD is a single GitHub Actions workflow that runs tests, builds the binary, and scps it to the server. No Docker registry, no Kubernetes manifest, no Helm chart.

Database migrations use `golang-migrate/migrate` with embedded SQL files:

```go
import (
    "embed"
    "github.com/golang-migrate/migrate/v4"
    _ "github.com/golang-migrate/migrate/v4/database/postgres"
    "github.com/golang-migrate/migrate/v4/source/iofs"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

func runMigrations(dbURL string) error {
    source, err := iofs.New(migrationsFS, "migrations")
    if err != nil {
        return err
    }
    m, err := migrate.NewWithSourceInstance("iofs", source, dbURL)
    if err != nil {
        return err
    }
    if err := m.Up(); err != nil && err != migrate.ErrNoChange {
        return err
    }
    return nil
}
```

Migrations are SQL files embedded in the binary. Deploying applies them automatically. No separate migration step, no drift between migration tool versions.

---

## Final Thought

This stack won't win "Most Exciting Architecture" awards.

But it will:
- Scale with the product
- Stay maintainable
- Let me focus on users instead of frameworks

And honestly?

That's how you build something that lasts.
