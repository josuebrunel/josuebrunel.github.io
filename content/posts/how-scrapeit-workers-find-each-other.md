---
title: "How Scrapeit's Workers Find Each Other Without a Central Broker"
date: 2025-07-22
description: "A REST endpoint as a rendezvous point, a Kademlia DHT for wide discovery, mDNS for the LAN, and a polling loop that keeps Postgres and Ethereum honest with each other: the plumbing behind Scrapeit's worker swarm."
tags: ["golang", "libp2p", "p2p", "distributed-systems", "networking"]
---

Fully decentralized discovery sounds nice until you realize peer zero has to come from somewhere.

[Scrapeit]({{< ref "why-i-built-scrapeit.md" >}}) broadcasts scraping jobs to a swarm of workers instead of handing them out from a queue. That only works if a brand-new worker, one that has never talked to this network, can find the swarm. My answer is a small, deliberate compromise: one centralized rendezvous point to get in the door, then real peer-to-peer discovery from there on.

## One URL in

A worker starts by calling a plain REST endpoint on a known "root peer," usually the server that's already running:

```go
func (a App) Settings() echo.HandlerFunc {
	return func(c *echo.Context) error {
		peerID := a.Publisher.Node.ID.String()
		addr := getRootPeerAddr(peerID, a.Publisher.Node.Host.Addrs())

		return c.JSON(http.StatusOK, Response[env.Settings]{Data: env.Settings{
			Peer: env.Peer{
				ID:    peerID,
				Addrs: addr,
				Ipfs:  env.Get(env.IpfsAddrN),
				Topic: env.Get(env.PubTopicN),
			},
			Ethereum: env.Ethereum{
				Network:  env.Get(env.EtherAddrN),
				Contract: env.Get(env.EtherContractAddrN),
			},
		}})
	}
}
```

That one response is everything a worker needs: the root peer's libp2p address, the IPFS address for uploading results, the GossipSub topic to subscribe to, and the Ethereum network and contract to watch for payouts. `client.New()` builds its whole config from it, so there's no peer list to maintain per worker.

It's centralized in exactly one sense: the first connection. After that, the worker is a full libp2p peer like any other, and the root peer has no special authority over it.

## Joining the swarm: DHT and mDNS, side by side

With the root peer's address in hand, `common.NewNode` starts two discovery mechanisms at once:

```go
// dht discovery
dht, err := NewDHT(ctx, host, bootStrappingPeers, serverMode)
if err != nil {
	panic(err)
}
go DHTDiscover(ctx, host, dht, DiscoveryTag)
// local discovery
xlog.Info("setup local discovery")
if err := SetupDiscover(host); err != nil {
	panic(err)
}
```

The **Kademlia DHT** handles wide-area discovery. It bootstraps against the root peer, then every 10 seconds looks for other peers advertising the same rendezvous tag and dials any new ones:

```go
func DHTDiscover(ctx context.Context, h host.Host, dht *dht.IpfsDHT, rendezvous string) {
	var routingDiscover = routing.NewRoutingDiscovery(dht)
	ticker := time.NewTicker(time.Second * 10)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			peers, err := util.FindPeers(ctx, routingDiscover, rendezvous)
			// ...dial anything not already connected
		}
	}
}
```

**mDNS** covers the case the DHT is slow at: two workers on the same LAN. It broadcasts locally and connects the moment it hears back:

```go
func (d *DiscoveryNotifee) HandlePeerFound(pi peer.AddrInfo) {
	xlog.Info("discovered new peer", "peer", pi.ID)
	if err := d.h.Connect(context.Background(), pi); err != nil {
		xlog.Error("error while connecting to peer", "err", err)
	}
}
```

Running both isn't redundant. Each covers the other's weak spot. The DHT works across the internet but needs a bootstrap round trip and a polling interval to converge. mDNS is near instant but stops at the edge of the local network.

A worker on the same machine as the server finds it in milliseconds. A worker on another continent finds it a few seconds later. Either way, both peers end up on the same GossipSub topic and see the same task broadcasts.

## Publishing is the easy part

Once a task exists, getting it in front of every worker is almost anticlimactic:

```go
func (s Server) Publish(ctx context.Context, tsk *task.Task) {
	xlog.Info("publishing task", "task", *tsk, "topic", s.Node.TopicName)
	s.Node.Topic.Publish(ctx, tsk.JSONMarshal())
	xlog.Info("task published")
}
```

Every subscribed worker gets the same JSON at roughly the same time. GossipSub doesn't pick a worker, it fans the message out to all of them. So distribution isn't the hard part. The hard part is what happens when more than one worker acts on the same message.

## Trusting the chain takes patience

Here's a race that's easy to get wrong. A task is written to Postgres and its `create()` transaction is submitted to Ethereum in the same request. But a submitted transaction isn't a confirmed one.

If the server called `complete()` the moment a worker reported success, it could be completing a task the contract doesn't know about yet. So `Scrape()` doesn't wait inline. It starts a goroutine that waits for the transaction to be mined, then flips an `OnChain` flag:

```go
go func() {
	gCtx := context.Background()
	rcpt, err := a.Manager.WaitMined(gCtx, tx)
	if err != nil || rcpt.Status != types.ReceiptStatusSuccessful {
		xlog.Error("transaction failed to be mined", "error", err, "transaction", tx.Hash().Hex())
		return
	}
	if err := obj.Update(gCtx, a.bob, &models.TaskSetter{OnChain: omitnull.From(true)}); err != nil {
		xlog.Error("failed to update task", "error", err)
	}
}()
```

When a worker later reports a task complete, `waitForOnChainProcessing` polls every 10 seconds, for up to 2 minutes, until that flag is set. Only then does it call `complete()`:

```go
for {
	select {
	case <-gCtx.Done():
		xlog.Error("context done", "error", gCtx.Err())
		return
	case <-ticker.C:
		obj, err := models.FindTask(gCtx, a.bob, uuid.Must(uuid.FromString(id)))
		if err != nil {
			return
		}
		if !obj.OnChain.GetOrZero() {
			continue // funding tx not mined yet, keep waiting
		}
		if obj.Status.GetOrZero() == string(task.Failed) {
			return // don't pay out a failed task
		}
		tx, err := a.Manager.Complete(gCtx, id, obj.Assignee.GetOrZero(), output, task.TaskStatus(status) == task.Completed, a.privateKey)
		// ...
	}
}
```

There are two flags, `OnChain` and later `Paid`. Both are set asynchronously, and both are checked before the next step fires. It's a small reconciliation loop, and it keeps a database that answers instantly from disagreeing with a blockchain that doesn't.

## Stopping two workers from racing the same task

GossipSub tells everyone, so nothing stops two workers from claiming the same task. The guard lives in `Submit()`, the shared handler behind both claim and complete:

```go
if slices.Contains([]string{string(task.Completed), string(task.Active)}, tsk.Status.GetOrZero()) && tsk.Assignee.GetOrZero() != ethAddr {
	xlog.Error("invalid assignee", "assignee", reqTask.Assignee)
	return c.JSON(http.StatusBadRequest, Response[task.Task]{Error: ErrInvalidAssigneeAddress.Error()})
}
```

Once a task is `Active` or `Completed`, only the ETH address already attached as `Assignee` can move it forward. A second worker gets a 400 instead of a chance to overwrite the first one's work.

The worker's address comes from the same API-key middleware that resolves every authenticated request. There's no separate identity system to keep in sync: the address that claims a task is the one the contract pays.

## The one thing I kept centralized

None of this needed a broker, a dispatcher, or a shared queue. One REST call gets a worker in the door. A DHT and mDNS keep it connected to whoever else shows up. A couple of small polling loops keep the ledger honest.

It's not bulletproof. If a funding transaction never confirms, the reconciliation loop gives up and logs a line. And any peer that finds the rendezvous tag can join and claim work. But the trick holds: decentralize what benefits from it, and keep exactly one thing centralized, the door.

---

*Scrapeit is open source. [View on GitHub](https://github.com/josuebrunel/scrapeit).*
