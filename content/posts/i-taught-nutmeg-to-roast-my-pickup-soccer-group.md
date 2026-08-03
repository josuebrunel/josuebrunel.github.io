---
title: "I Taught Nutmeg to Roast My Pickup Soccer Group (So I Wouldn't Have To)"
date: 2026-08-03
description: "Nutmeg's stats now get read out loud by an LLM - savage player roasts and full satirical match reports, grounded strictly in real numbers. Here's how it works and what almost went wrong."
tags: ["golang", "llm", "self-hosted", "soccer", "side-project"]
---

Last time I said this might be a post on its own, if it turned into something worth shipping instead of a pile of prompt-tuning regrets. It shipped. Nutmeg now writes its own trash talk.

{{< figure src="/img/nutmeg/player-roast.png" alt="Nutmeg player profile showing an AI-generated roast: 'Seven goal contributions in two games and Josh still managed to lose a match.'" caption="Josh scored five goals and assisted twice in two games. He still lost one. The robot noticed." >}}

## What Actually Shipped

I promised one thing: feed a player's stats to an LLM and let it write the roast. That part's live - every player's profile page has a box labeled **THE ROAST**, regenerated after every match they play in. But it grew past that. Nutmeg also writes a full match report after every game now, a fake sports-desk recap of who did what to whom, headline included.

{{< figure src="/img/nutmeg/match-article.png" alt="Nutmeg match report headlined 'Shawn Ascends To Godhood In Parulas' Narrow Triumph' after an 8-7 win" caption="Parulas won 8-7. Shawn had three goals and four assists. The headline writes itself, mostly because I told the model to write the headline." >}}

Click any logged match, public link or not, and you get a made-up headline ("Shawn Ascends To Godhood In Parulas' Narrow Triumph") and three paragraphs of a model doing color commentary on a Sunday pickup game like it's a Champions League final. It's a genuinely funny bit that costs me nothing to read every week, and I built it by accident while trying to do the smaller thing.

## The Hard Part Was Exactly What I Thought It'd Be

I called it out last time: "funny" and "your friends actually still like you afterward" is a narrower target than it sounds. Stats alone don't know the difference between a good-natured jab and just being mean about someone's bad week.

The fix wasn't a smarter model, it was a stricter leash. Every prompt gets one instruction that matters more than the rest: only use the real numbers below, never invent a stat, an event, or a player. No minutes played (Nutmeg doesn't track that), no manufactured drama, no guessing at what "probably" happened. If a team had no assists, the prompt says so explicitly instead of leaving a gap for the model to fill in with something dramatic-sounding.

That single constraint solved most of the mean-vs-funny problem for free. A model roasting real numbers reads as banter. A model roasting a number it made up reads as an insult built on a lie, and that's the version where someone actually gets hurt. Grounding it in facts wasn't just an accuracy decision, it was the tone decision.

## It Never Gets to Block the Match

The generation itself happens in the background. You log a match, the score and stats save immediately like they always did, and a queued job goes and asks the model for a roast and a match report after the fact. If the model's slow, unreachable, or just returns something empty or broken, the request that logged your match never notices or waits on any of it. Worst case, you see "Full match report coming soon" for a few seconds until the job finishes.

That also means a bad generation never overwrites a good one. Every generation gets validated (not empty, not longer than the character budget, doesn't trip a blocklist) before it's allowed to replace whatever was there before. A failure just leaves the previous roast standing and gets logged - the site never shows you half-written garbage.

## Same Public Links, More to Read

The public share link I bragged about last time (no account, no signup, just click and see your stats) shows the match reports too now. Someone who's never logged into Nutmeg in their life can open a link from the group chat and read a fake headline about how badly they lost on Tuesday. That felt like the right default: the roast is only worth anything if the person it's about can actually see it.

## What Works, What Doesn't (Yet)

**What works:**
- The roasts and match reports are consistently funny without me babysitting every generation
- Nobody's felt actually insulted yet - the "only real stats" rule is doing its job
- It runs against a local model or Google's API interchangeably, so you're not locked into paying for tokens just to read jokes about your own five-a-side team
- A bad or slow generation never blocks logging a match or shows broken content

**What doesn't (yet):**
- No memory across matches beyond the last ten, so a running rivalry doesn't build up the way a real commentator would reference "last time these two played"
- The regenerate button has a cooldown, so if the first roast lands flat you're waiting ten minutes for a second opinion
- Still no way to tune the tone per group - everyone gets the same savage-but-friendly default whether their group chat is savage or gentle

## The Payoff

Shawn had three goals and four assists in an 8-7 win, and the model decided that made him a god. Josh scored five times across two games and still has a losing record, and the model just... pointed that out. Neither of those is an argument I had to make. I just built the thing that reads the box score out loud.

---

*Nutmeg is MIT-licensed and self-hosted. [View on GitHub](https://github.com/josuebrunel/nutmeg).*
