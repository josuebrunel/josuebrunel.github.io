# josuebrunel.github.io

A Hugo blog (theme: `hugo-vitae`). Posts live flat in `content/posts/*.md` — no subdirectories, no series folders.

## Front matter

Every post needs:

```toml
title: "..."
date: 2026-01-01
description: "One sentence, factual, no clickbait. Shows up in search results and social previews."
tags: ["lowercase", "no-spaces-preferred"]
```

- `description` is required on every post. It's the single highest-leverage field for SEO and link previews — don't skip it.
- `tags` are always lowercase (`golang`, not `Golang`). No enforced taxonomy beyond that; free-tag as needed.
- `categories` is legacy — it was used through 2024 (`Programming`, `Linux`, `Openerp`, `Projects`, `About Me`) but dropped from newer posts in favor of just `tags`. Don't add it to new posts.
- `author` is omitted on posts from 2024 onward. Don't add it back.
- If a post is genuinely unfinished, use `draft: true` — but don't let a draft sit empty indefinitely. An empty draft is a candidate for deletion, not a permanent placeholder.
- Planning a multi-part post? Say so explicitly in the text (e.g. "Part 2 covers X") only once Part 2 actually exists, or use a `series` field if you add one. Don't title something "Partie I" on the promise of a sequel — one post did that in 2012 and Partie II never happened.

## Images

Two conventions exist in the archive:
- Legacy posts use plain `![alt](/images/...)` markdown.
- `building-pulsedash.md` (the newest, most polished post) introduced the theme's figure shortcode instead: `{{< figure src="/img/..." alt="..." caption="..." >}}`.

**Use the shortcode for all new posts.** It gets you captions for free and matches the current direction. Don't bother retrofitting old posts — not worth the churn.

## Voice

The 2024–2026 posts are the current standard: technical, confident, dry wit used sparingly, no forced enthusiasm. Recent commits have specifically reworked older drafts to match this (see `c61eef3`, `60e5895`). Concretely:

- Hyphens, not em dashes.
- Short paragraphs. Code speaks for itself — don't narrate what a snippet obviously does, explain *why* it's shaped that way.
- It's fine to say what didn't work or what you'd reconsider. The strongest posts on this site (PulseDash, the SaaS stack post) both include an honest "what doesn't work" or "what I'd reconsider" section — don't write one-sided pitches.
- English only for anything new. Older posts are a mix of French and English; that's a historical fact about the archive, not a target to keep hitting.

## Cross-linking

Posts almost never link to each other, even when they obviously should (e.g. two Go tutorials published six weeks apart, or two posts independently re-explaining the same "one binary, embedded SQLite" philosophy). When a new post overlaps with an existing one, link it with Hugo's ref shortcode instead of re-explaining:

```md
[How to Test Go Code Without a Test Framework]({{< ref "how-to-test-go-code-without-a-test-framework.md" >}})
```

## Content that's out of date

Some archived posts reference dead products (OpenERP, pre-3.4 Python's `imp` module) or are Python 2-only. These carry a `> **Note (2026):** ...` blockquote near the top or bottom flagging what's outdated, rather than being silently rewritten or deleted. If you're touching one of these posts again, prefer a real update over another disclaimer.
