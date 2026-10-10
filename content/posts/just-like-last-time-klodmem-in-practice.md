---
title: "Just Like Last Time: What klodmem Did for Me"
date: 2026-10-13
description: "A month after building klodmem, I audited my own Claude Code transcripts to see how often I used it and what it actually gave me."
tags: ["claude-code", "mcp", "klodmem", "ai", "workflow"]
---

I almost never tell Claude to search my history. I say "just like last time" and let it work out the rest.

That's where [klodmem]({{< ref "klodmem.md" >}}) earns its keep. I built it to make old memories and conversations searchable. A month later, I wanted to know if it actually helps. So I did the boring thing and audited my own transcripts.

## What the numbers say

Lighter use than I expected, and more specific.

- **53 sessions** across **20 projects** since I set it up.
- **5 memory files** saved by Claude so far.
- **3 real searches** in my own work, all in one session. The other calls in my logs are from writing this post.

One caveat: klodmem doesn't index tool calls, so there's no dashboard for this. I counted by reading the raw transcripts myself. That count also only covers the searches Claude ran: when another agent searches the same index, it never shows up in these transcripts at all.

Three searches isn't much. But one of them paid for the whole tool.

## The "just like last time" session

I'd opened a different repo, a work project, and typed this:

> Just like in the previous convo, can you list the open tickets and sort them by blast radius and priority.

The "previous convo" was weeks old, and it lived in a different project. Nothing in this one's context knew about it.

Claude did two searches. The memory search came back empty, because I'd never saved a note about it. The history search found my old question, where I'd asked for tickets sorted by effort and blast radius. It checked how I'd handled tickets before, ran `gh issue list`, and gave me a table: ticket, priority, blast radius, and whether it was blocked.

My next message was "proceed with #30". Two messages from me, and the whole thing was done.

This is the case memory can't cover. Nobody writes a note for "how I like tickets ranked." It happened once, in a conversation, and the conversation is the only place it exists. It's also the same habit I wrote about in [How I Deploy My SaaS With an AI Agent]({{< ref "deploying-with-an-ai-agent-and-cli-tools.md" >}}): tickets are the memory, and klodmem helps the agent find them again.

## Memory that crosses repos

The second win showed up while I was writing this post. A memory search turned up a note Claude had saved in another project, about how I want my blog posts to end. I'm in the blog repo now. The note was written during a different post.

Without klodmem, that note stays in its own silo, and I'd have given the same correction twice. This post follows it, and ends with a single closing paragraph.

## It works across agents, not just across repos

This is the part I didn't plan for, and it turned out to be the best bit.

klodmem is an MCP server, so it doesn't care which agent is asking. Any agent that can talk to it can search the same index. And that index holds my Claude Code sessions.

So I asked a different agent about my Claude work, and it just answered.

I was in Hermes, working on this post, and I wanted to check what my last session in the blog repo had been about. I typed the question the way I'd type it to myself:

> what was the last thread about in hugo blog?

Hermes called klodmem's `search_history` with those words and got my turns back, from every project, each one with its session id and the transcript path:

```
[user] 2026-10-09T12:25:02Z ...help me draft a new hugo article explaining how I manage...
       session: 03b54a2d-1edb-4576-923e-cf377e97a5e5
       file:    ~/.claude/projects/-home-...-josuebrunel-github-io/03b54a2d-....jsonl
```

Then it opened that transcript and told me what the thread was: the post about deploying a SaaS with CLI-driven agents, the favicon, the text I shared on LinkedIn, and the klodmem post I'd started. It also found the follow-up from that morning, where I'd asked for the cross-agent part. I didn't summarize anything for it, and I didn't paste a transcript in. I asked a question, and it went and read.

That's the difference from searching inside the agent I had the conversation with. A hit comes with the file path, so "continue from there" is a real instruction instead of a hope: the next agent reads the whole thread off disk rather than working from one matching line.

Before this, a conversation belonged to the tool I had it in. Now it belongs to me. I can start a problem in Claude, move to another agent when it suits the job, and the context comes along.

## The gain is not re-explaining myself

Three searches in a month isn't a lot, but each one saved me from starting over. The ticket ranking alone saved me from explaining a whole way of working to a fresh session, and the blog note saved me a correction I'd already made once. Pointing another agent at a Claude thread saved me from retelling a whole conversation. I don't need klodmem every day. I need it on the day I say "just like last time", and on that day it means I don't have to say anything else.
