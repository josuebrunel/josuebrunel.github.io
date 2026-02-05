---
title: "My SaaS Tech Stack: Chosen by an Engineer Who Likes Simplicity"
date: 2026-02-03
description: "Why my SaaS uses a boring, simple tech stack—and why that’s exactly what makes it scalable."
tags: ["saas", "golang", "htmx", "postgres", "architecture"]
draft: false
---

Building a SaaS is full of important decisions.

Tabs or spaces.  
Dark mode or *forced* dark mode.  
And of course: *Which tech stack will ruin my weekends the least?*

After experimenting with shiny frameworks, clever abstractions, and architectures that looked amazing in diagrams, I landed on a simple rule:

> **If a system is easy to understand, it’s hard to kill.**

This is the stack I use today—and why every tool is here to *reduce* complexity, not manufacture it.

---

## Simplicity Is Not a Lack of Ambition

“Simple stack” often gets translated as:
- Small product
- Low scale
- Temporary solution

In practice, the opposite is usually true.

The first thing that breaks in a growing SaaS is not the database.  
It’s not performance.  
It’s **developer velocity and confidence**.

Complex systems slow you down long before traffic ever does.

So I default to simple—and let reality force complexity later.

---

## Go: Because I Prefer Code Over Sorcery

Go is the foundation of everything.

What I like about Go:
- One static binary
- Explicit behavior
- Predictable performance
- No hidden runtime theatrics

Go code reads like instructions, not riddles.

When something breaks, I don’t need a debugger, a blog post, and a priest—I need `grep` and a cup of coffee.

That clarity compounds over time.

---

## Echo v5: A Web Framework That Knows When to Shut Up

For HTTP routing and middleware, I use **Golang Echo v5**.

Echo hits a sweet spot:
- Fast
- Minimal
- Well-structured
- Doesn’t fight Go’s standard library

It gives me:
- Clean routing
- Sensible middleware
- Context handling without drama

Most importantly, Echo doesn’t try to become *the architecture*.  
It stays in its lane and lets the application logic stay obvious.

That’s exactly what I want from a web framework.

---

## Golang Templ: HTML That Refuses to Lie

I render HTML using **Golang Templ**.

Why?
- Type-safe templates
- Compile-time errors
- No string-based HTML chaos

If I rename a field and forget to update the template, the app simply won’t compile.

This is the kind of tough love I respect.

Templates live close to the logic, refactors are safe, and runtime surprises are rare—which is the dream.

---

## HTMX: Interactivity Without a Frontend Midlife Crisis

Most SaaS products don’t need:
- Client-side routers
- State management libraries
- JavaScript build systems that rival the backend

They need:
- Forms
- Buttons
- Tables
- Partial updates

HTMX gives me interactivity while keeping:
- The server in control
- HTML as the contract
- The browser doing what it already does well

No SPA.  
No hydration bugs.  
No “why is this state different over here?” moments.

Just HTML behaving responsibly.

---

## PostgreSQL: Shockingly Good at Being a Database

PostgreSQL handles:
- Transactions
- Constraints
- Concurrency
- Reporting

Which is incredible, considering that’s *literally its job*.

Instead of inventing clever data storage schemes, I let Postgres do what it has been doing reliably for decades—and doing extremely well.

Simple schema. Clear queries. Long runway.

---

## RiverQueue: Background Jobs Without Summoning Another System

Every SaaS eventually needs background jobs:
- Emails
- Webhooks
- Async processing
- Long-running tasks

Instead of introducing Kafka, RabbitMQ, or a new operational headache, I use **RiverQueue**, which runs directly on PostgreSQL.

That means:
- One datastore
- One backup strategy
- One mental model

Background jobs should be boring.  
RiverQueue makes them boring in the best way.

---

## Redis: Powerful, Dangerous, Used With Adult Supervision

Redis is fantastic.

Redis is also how many architectures quietly become complicated.

In this stack, Redis is:
- A cache
- Short-lived state
- Performance optimization

It is **not** a source of truth.  
It is **not** the backbone of the system.

Used intentionally, Redis speeds things up without turning the app into a distributed puzzle.

---

## CSS: I Refuse to Argue With My Stylesheet

For styling, I optimize for:
- Semantic HTML
- Accessibility
- Low maintenance

That’s why I use:
- **PicoCSS v2** for clean defaults
- **DaisyUI** when utility components make sense
- **PicoDaisy**, my own hybrid library  
  👉 https://josuebrunel.github.io/picodaisy/

The goal isn’t flashy UI—it’s shipping changes without emotional damage.

---

## The Unexpected Benefit: Operational Peace

This stack has a feature I value more than benchmarks:

**It’s calm to operate.**

Deployments are simple.  
Failures are understandable.  
Fixes don’t require a Slack war room.

No frontend-backend negotiations.  
No distributed-system cosplay.  
Just a small set of tools working together quietly.

---

## Final Thought

This stack won’t win “Most Exciting Architecture” awards.

But it will:
- Scale with the product
- Stay maintainable
- Let me focus on users instead of frameworks

And honestly?

That’s how you build something that lasts.
