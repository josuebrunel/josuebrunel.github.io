---
title: "Why I Built Nutmeg (So My Friends Would Stop Lying About Their Stats)"
date: 2026-08-01
description: "Why I built Nutmeg, a self-hosted stats tracker for pickup soccer groups, after one too many arguments about who actually won."
tags: ["golang", "htmx", "self-hosted", "soccer", "side-project"]
---

Every group chat has one guy. You know the one. You score the winning goal on
Sunday, and by Tuesday he's telling the chat you "haven't scored in years."
You won two weeks ago - clean sheet, hat-trick, the whole thing - and somehow
by this week's game the official chat record is that you "haven't won in
months." Nobody fact-checks him. Nobody *can* fact-check him. The data lives
in fifteen people's unreliable memories and WhatsApp voice notes nobody
replays.

I got tired of losing arguments I was factually winning. So I built Nutmeg.

{{< figure src="/img/nutmeg/leaderboard.png" alt="Nutmeg leaderboard showing wins, draws, losses, goals, and assists for a pickup soccer group" caption="Receipts. All of them, sorted by whoever's winning." >}}

**Quick start**, if you just want to see it running:

```bash
git clone https://github.com/josuebrunel/nutmeg.git
cd nutmeg
docker compose up -d
# app at http://localhost:8080
```

---

## The Group Chat Has No Memory

The trash talk was never really about who's *better*. It's about who's
*right*, which is a much pettier and more winnable fight - if you have the
data. Half our arguments boiled down to one unanswerable question: **who is
actually the top scorer in this group?** Not "who do people think is," not
"who talks the most about it," but the actual number, sorted, indisputable.

Before Nutmeg, the answer lived nowhere. After a match, scores got typed
into the chat and immediately buried under memes. Nobody was tallying goals
and assists across sixteen Sundays of pickup games. So every claim about
form, streaks, or scoring droughts was just confident vibes.

## What It Actually Does

Nutmeg is deliberately narrow. It does one thing: it remembers your pickup
games so you don't have to, and it turns that memory into ammunition.

- **Groups with a shared roster** - one list of regulars, no re-typing names
  every week. You can even CSV-import a roster in one go if your group chat
  already has a member list somewhere.
- **Log a match in under a minute** - this is the part I'm proudest of.
  There's no dropdown of players, no "select a team" form, no typing a
  score into a box. You tap each name onto Shirts or Skins, tap the `+`
  next to a player every time they score or assist, and the final score
  fills itself in as you go - it's just addition, the app does it for you.
  Someone can log an entire match one-handed, mid-conversation, before the
  next kickoff, without ever looking at a keyboard.
- **A leaderboard that actually argues back** - wins, draws, losses, goals,
  assists, sortable, searchable. Click any name for that player's full
  profile: every match, every stat, no editorializing.
- **A public link, no account required** - admins can share a read-only
  leaderboard link straight into the WhatsApp group. Anyone can open it,
  find their name, and see their real numbers, without signing up for yet
  another app just to see if they're still top scorer.
- **Dates in your actual timezone** - a small thing, but "Date Played"
  defaults to *your* today, not the server's, so match history doesn't
  quietly drift a day off for half the group.

{{< figure src="/img/nutmeg/log-match.png" alt="Nutmeg match logging screen with tap-to-assign teams and goal/assist steppers" caption="Logging a match: tap teams, tally goals, done." >}}

That screenshot is the entire skill required to use Nutmeg. No manual, no
tooltip tour, no "click here to get started" - if you can tap a name and
tap a `+` button, you already know how to log a match. It's genuinely
faster to log the game than it is to argue about who's typing it in.

## No Accounts, No Excuses

The one feature I'm most pleased with isn't flashy: **you don't need an
account to see your own stats.** Half the people in any given pickup group
are never going to register for an app, no matter how good it is - they just
want to know if they're still top of the table. So the leaderboard, and
every individual player's page, is a plain public link. An admin logs the
matches; everyone else just clicks a link someone drops in the chat.

## The Stack (Briefly)

Nutmeg is Go, Echo, and Templ on the backend, HTMX and DaisyUI on the
front, Postgres underneath, and one `docker compose up` to run the whole
thing. It's the same "boring on purpose" philosophy I wrote about in
{{< ref "my-simple-and-happy-stack.md" >}} - applied here to a much smaller,
sillier problem than a SaaS backend, but the reasoning holds: fewer moving
parts means I can still ship a feature on a Tuesday night before I'm too
tired to care whether my own stats look good.

## What Works, What Doesn't

**What works:**
- Logging a match genuinely takes under a minute, even mid-argument about
  who owes who a substitute
- The leaderboard is the actual source of truth now - trash talk has to
  cite it or concede
- Public share links mean zero friction for the people who just want to
  look, not sign up
- Self-hosted, MIT-licensed, your data stays on your own server

**What doesn't (yet):**
- No charts or graphs - the leaderboard is a table, not a dashboard. Fine
  for now, but "form over the last 5 games" as a sparkline is tempting.
- No head-to-head view - you can't yet pull up "me vs. that one guy" and
  settle a specific rivalry directly.
- No notifications - if you don't check the group chat, you won't know a
  match got logged without you.
- Soccer-only - team labels are literally "Shirts" and "Skins." Don't ask
  it to track your five-a-side futsal league's substitution rules.

## The Payoff

Now when someone tells me I "haven't scored in years," I don't argue. I send
a link. It has my name, my goals, and the date, sorted against everyone
else's, sitting in a leaderboard he can't talk his way out of. That's the
whole pitch: not a better argument, just an unarguable one.

## What I'm Poking At Next: Getting an AI to Do the Roasting

A sorted table is unarguable, but it's not *mean*, and let's be honest, half
the fun of group-chat banter is the delivery, not the data. So the thing
I'm currently tinkering with is feeding a player's stats - goals, assists,
that four-match scoreless streak, the 0-4 they were on the losing end of
last week - to an LLM and letting it write the roast for me. Nutmeg already
knows exactly how badly you've been playing; it just doesn't say anything
about it yet.

The appeal is obvious: I'd rather spend Sunday evening editing a robot's
insults than writing my own, and a model that's only ever seen the numbers
has no loyalty to anyone - it'll roast me exactly as hard as it roasts
Chris. The harder part is tone: "funny" and "your friends actually still
like you afterward" is a narrower target than it sounds, and stats alone
don't know the difference between a good-natured jab and just being
mean about someone's bad week. If that turns into something worth shipping
instead of a pile of prompt-tuning regrets, it's a post on its own - I'm not
promising a Part 2 I haven't written yet.

**Update:** it shipped - see [I Taught Nutmeg to Roast My Pickup Soccer Group]({{< ref "i-taught-nutmeg-to-roast-my-pickup-soccer-group.md" >}}).

---

*Nutmeg is MIT-licensed and self-hosted. [View on GitHub](https://github.com/josuebrunel/nutmeg).*
