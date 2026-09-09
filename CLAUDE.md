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

The 2024–2026 posts are the current standard, and they match the site's `writing` skill. Recent commits have specifically reworked older drafts to match this (see `c61eef3`, `60e5895`). Concretely:

- Simple English: short, common words over fancy ones, plain phrasing over jargon.
- No em dashes, and no plain hyphen used as a dash substitute either. Use a comma for an aside, a colon when what follows explains or delivers the point, or split into two sentences.
- First person, contractions always (don't, it's, won't). Warm and direct, with an occasional wry aside, not a joke forced into every section.
- Open a post with a claim or a small scene, not a rhetorical question.
- Content must be skimmable and easy to follow: short paragraphs, one idea each, plain sentence structure. A reader should get the gist from headers and bolded leads alone, without reading every word.
- Punchy, specific H2 headers, not "Overview" or "Conclusion."
- Code speaks for itself: don't narrate what a snippet obviously does, explain *why* it's shaped that way.
- For project or decision writeups, close with an honest `**What works:**` / `**What doesn't (yet):**` pair instead of a one-sided pitch. PulseDash and the SaaS stack post both do this; it's the standard, not the exception.
- End on a callback or payoff line, not a call-to-action.
- English only for anything new. Older posts are a mix of French and English; that's a historical fact about the archive, not a target to keep hitting.
- This applies to prose meant to sound like Josue (posts, READMEs, PR descriptions). Pure reference material (config tables, API docs) and code comments stay neutral and factual.

## Cross-linking

Posts almost never link to each other, even when they obviously should (e.g. two Go tutorials published six weeks apart, or two posts independently re-explaining the same "one binary, embedded SQLite" philosophy). When a new post overlaps with an existing one, link it with Hugo's ref shortcode instead of re-explaining:

```md
[How to Test Go Code Without a Test Framework]({{< ref "how-to-test-go-code-without-a-test-framework.md" >}})
```

## Content that's out of date

Some archived posts reference dead products (OpenERP, pre-3.4 Python's `imp` module) or are Python 2-only. These carry a `> **Note (2026):** ...` blockquote near the top or bottom flagging what's outdated, rather than being silently rewritten or deleted. If you're touching one of these posts again, prefer a real update over another disclaimer.
