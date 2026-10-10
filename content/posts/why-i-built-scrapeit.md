---
title: "Why I Built Scrapeit: A Decentralized Scraping Marketplace"
date: 2025-07-08
description: "Scraping at any real scale costs money in infrastructure, proxies, and upkeep. Scrapeit is a marketplace where anyone can earn ETH scraping pages for people who'd rather pay a few cents than run the infrastructure themselves."
tags: ["golang", "web-scraping", "ethereum", "libp2p", "marketplace", "solidity"]
---

Scraping a page sounds trivial until you have to do it forty times a day without getting blocked.

A single headless browser eats a lot of memory. Push too many requests through one IP address and most sites start throwing captchas, or quietly return garbage. Proxy providers charge by the gigabyte for IPs that haven't been flagged yet. Every few months a site changes how it detects bots, and someone has to keep watching the pipeline just to keep it working.

None of that is the actual scrape. It's the infrastructure standing in front of it, and it costs real money whether you scrape one page a day or a million.

## Most of that infrastructure sits idle

If you need forty product pages checked once a week, you don't need a fleet of always-on browsers. You need forty page loads, on a Tuesday, from somewhere.

Meanwhile plenty of people have a spare laptop, a home server, or a connection nobody's ever tried to scrape through. They'd happily let it run a job in the background for a small reward.

That's the gap Scrapeit closes. You submit a URL and a reward. The first independent worker to pick it up gets paid the moment it proves the job's done. No platform sets prices, approves workers, or takes a cut. A smart contract holds the reward and releases it.

**Quick start**, if you want to see it:

```bash
git clone git@github.com:josuebrunel/scrapeit.git
cd scrapeit
docker compose up
# submit a task
curl -X POST localhost:8080/api/v1/task \
  -H "Authorization: <api-key>" \
  -d '{"url": "https://example.com"}'
```

## Who actually needs this

**Requesters** need scraping occasionally, not constantly. Think of a small team checking competitor prices once a week, a researcher pulling a one-time dataset, or a journalist collecting public records for a story that wraps up in a month. None of them want to rotate proxies and babysit an anti-bot arms race for a handful of jobs. A few cents per page beats standing up infrastructure you'll use twice.

**Workers** have spare capacity and no easy way to monetize it: a mostly idle home server, an old laptop that still runs fine. Run the worker software and that capacity earns automatically. No client, no invoice, no rate to negotiate.

Both sides show up because the alternative is worse. One builds infrastructure for occasional use, the other lets good hardware earn nothing.

## Money without trust

A marketplace between strangers only works if neither side has to trust the other first. The requester doesn't know who will pick up the task. The worker doesn't know if the requester will pay.

That's why this needed a smart contract instead of a payment processor. The reward is locked the moment a task is submitted, before any work happens. It's only released once the worker proves the job succeeded. Nobody has to trust me, my code, or a support queue.

The reward is small, a fraction of a cent by default. If contract fees ate more than the reward, the whole idea would collapse. So I spent real time keeping them low, and the contract's gas cost was one of the last things I tuned.

## How to take part

Running a worker is one program. It watches for jobs, claims one, scrapes it, and reports back. There's no approval step and no minimum commitment.

Submitting a task is one request with a URL and a reward. The job is recorded, funded, and broadcast to every listening worker at once. It isn't a queue I control, so nobody decides who sees it first. How a brand-new worker finds that network at all is a story of its own: [How Scrapeit's Workers Find Each Other]({{< ref "how-scrapeit-workers-find-each-other.md" >}}).

Neither side needs my database or a relationship with me. A worker needs the software and a wallet. A requester needs an API key and a URL.

## Still a proof of concept

Scrapeit says so in its own nav bar, on purpose. The reward is a flat rate instead of being priced by task difficulty. There's no automated test suite yet. The contract also trusts more than a production payment system should. But the core idea works end to end today: scraping doesn't have to be something only companies with infrastructure budgets can afford, and idle bandwidth doesn't have to earn nothing.

---

*Scrapeit is open source. [View on GitHub](https://github.com/josuebrunel/scrapeit).*
