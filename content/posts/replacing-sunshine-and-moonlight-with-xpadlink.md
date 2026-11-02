---
title: "I Replaced Sunshine and Moonlight with My Own Gamepad App"
date: 2026-11-02
description: "How I built XPadLink, a small Go daemon and Android app that turns my phone, or a GameSir pad clipped to it, into a virtual Xbox controller for Cemu and other emulators on Linux."
tags: ["linux", "golang", "flutter", "android", "gaming", "cemu", "ai", "xpadlink"]
---

I really love this new era. When an app doesn't do what you want, you don't have to wait for the maker or settle for it anymore. With AI, you can make it better, or just replace it.

That's what happened here. In my [GameSir post]({{< ref "gamesir-android-controller-for-cemu.md" >}}), I used Sunshine and Moonlight to get a phone controller into Cemu. It worked, but it was a video streaming stack doing a controller's job. So I replaced the whole thing with something of my own: **XPadLink**.

{{< figure src="/img/xpadlink/logo.png" alt="The XPadLink logo: a white gamepad under three Wi-Fi arcs on a purple background" caption="XPadLink. A gamepad, and some Wi-Fi." >}}

## Why replace something that worked?

It did work. But Sunshine and Moonlight are built to stream **video**. I only wanted the controller.

I was running a full stream session just to get a virtual pad. And the order mattered every time: start the stream, press a button, and only then could Cemu see the pad. Stop the stream and the pad was gone.

I wanted the small version. A phone sends button presses, the PC shows a gamepad. Nothing else.

## The idea: 18 bytes, 60 times a second

```
phone (Flutter app) --UDP--> xpadlinkd (Go) --/dev/uinput--> virtual Xbox 360 pad
```

That's the whole system. Three pieces:

- **xpadlinkd:** a Go daemon on the PC. It listens on UDP and creates one virtual pad per phone through `/dev/uinput`.
- **The app:** Flutter for the UI, a little Kotlin to read a physical controller plugged into the phone.
- **The protocol:** one state packet, 18 bytes: a sequence number, a button bitmask, four sticks and two triggers.

Why UDP? Because a late button press is a useless button press. If a packet gets lost, the next one arrives 16 ms later with the full state anyway. Each packet carries a sequence number, so the server drops anything stale.

The virtual pad reports the Xbox 360 vendor and product IDs (`045e:028e`). SDL, Steam, Proton and Cemu already know that pair, so there's no mapping to do.

## Seeing it work

Open the app and it finds your PC on its own. It sends a UDP broadcast, and the server answers with its hostname and port. No typing an IP.

{{< figure src="/img/xpadlink/app-connect.png" alt="The XPadLink connect screen with one saved server and one nearby server, both called loking at 192.168.1.207:9777" caption="Saved servers on top, nearby servers found by broadcast below." >}}

Tap the server, and the touch controller appears. Sticks, D-pad, ABXY, bumpers, triggers, and L3 and R3 for the stick clicks.

{{< figure src="/img/xpadlink/app-controller.png" alt="The XPadLink touch controller in landscape: two sticks, a D-pad, ABXY buttons, LT LB RB RT, and a green dot with Player 1" caption="The touch layout. Plug a controller in and it hides itself." >}}

On the PC, the server logs the join:

```
level=INFO msg="client joined" from=[::ffff:192.168.1.2]:35680 player=1 name=LokingUle
```

And the kernel sees a new gamepad:

```
N: Name="XPadLink - Xbox Controller 1 (LokingUle)"
```

The browser sees it too. This is [hardwaretester.com/gamepad](https://hardwaretester.com/gamepad) with the left stick pushed from the phone:

{{< figure src="/img/xpadlink/hardwaretester.png" alt="The Hardware Tester gamepad page showing XPadLink - Xbox Controller 1 connected with a standard mapping and the left stick moved" caption="Connected, standard mapping, and the left stick follows my thumb on the phone." >}}

## Into Cemu

Same steps as before: **Options, Input settings, SDLController**, pick the pad from the dropdown, **Auto-assign**.

{{< figure src="/img/xpadlink/cemu-input.png" alt="Cemu's input settings with a Wii U Pro Controller emulated, the controller set to X360 Controller [SDLController], and every button, stick and D-pad mapped" caption="Auto-assign mapped everything: sticks, D-pad, shoulders, ZL and ZR." >}}

No manual mapping, no profile tweaking. It just looks like an Xbox pad.

## The bugs that taught me something

**The GameSir that wasn't there.** I pressed buttons on the GameSir and nothing happened in the app. The logs showed no gamepad at all, only the touchscreen and the headset jack. The reason was silly: my phone has one USB-C port, and `adb` was using it. The GameSir X2 plugs into that same port.

I switched `adb` to Wi-Fi (`adb tcpip 5555`), plugged the pad in, and the log lit up:

```
input device first event id=29 name='GAMESIR Gamesir-X2 Type-C' vendor=1452 product=15110 pad=true axes=[HAT_Y,BRAKE,GAS,Z,Y,HAT_X,RZ,X]
physical pad active: GAMESIR Gamesir-X2 Type-C
```

No code change. Just a cable.

**Two players, one phone.** I was suddenly "player 2". Something else held slot 1. I looked at the UDP sockets on the phone and found a port owned by a different app: the first build of XPadLink, from before I renamed it, still running in the background. I uninstalled it and the pad dropped out on timeout.

**The silent wrong token.** Type the wrong token and the app just said "Connecting…" forever. The server was ignoring me, politely. Now it answers with a reject packet and the app says **Wrong token** in red.

**macOS CI crash.** The GitHub Actions build failed on macOS with `missing LC_UUID load command`. Go 1.22 test binaries don't start on current macOS. I pinned CI to Go 1.24.

**Cemu's pad name.** I named the virtual pad `XPadLink - Xbox Controller 1`. The browser shows that name, but Cemu shows `X360 Controller`. SDL swaps in its own label for the Xbox 360 vendor and product pair. That's the price of needing no mapping, and it's only a problem if you plug in a second Xbox pad and need to tell them apart.

## Logs, because Wi-Fi isn't perfect

My Wi-Fi isn't super stable. It wasn't with Moonlight either. So the app logs a summary every 5 seconds:

```
link: connected=true hello=5 state=94 ack=4 sendFail=0 maxAckGap=2114ms (5 s)
```

Now I can see it: mostly 1 second gaps between acks, which is normal, and the odd 2 second one when a packet gets lost. Guessing is gone.

The server uses structured logs too, so `journalctl` tells the same story from the other side.

## Run it as a service

I didn't want to start the daemon by hand. XPadLink can install itself:

```bash
xpadlinkd install
```

On Linux that's a systemd user unit. It starts at login, and the token is saved once so the phone never needs a new one. I killed it with `kill -9` to check, and systemd brought it back.

```bash
journalctl --user -u xpadlinkd -f
xpadlinkd uninstall
```

macOS (launchd) and Windows (a scheduled task) are in there too.

## Try it

The server is a single binary. Grab it from the [releases page](https://github.com/josuebrunel/xpadlink/releases), then:

```bash
make uinput-setup   # one time: udev rule + input group, then log out and in
xpadlinkd install   # start it in the background
```

For the app you need the Flutter SDK:

```bash
make app && make app-run
```

The code is at [github.com/josuebrunel/xpadlink](https://github.com/josuebrunel/xpadlink).

## Where it stands

**What works:**
- Phone touch controls and a GameSir pad plugged into the phone.
- Automatic server discovery, saved servers, up to 4 phones at once.
- Linux daemon as a service, with release binaries for Linux, macOS and Windows.

**What doesn't (yet):**
- Only Linux can create the virtual pad. The macOS and Windows builds compile but I haven't tried them on real machines.
- Vibration and gyro (for Cemu's tilt games) are built, but I haven't tested them in a game yet.
- LAN only, no encryption. The token just keeps strangers on your Wi-Fi from sending input.
- Bluetooth controllers should work like the GameSir does, but I haven't tested one.

Sunshine and Moonlight are uninstalled. XPadLink is the new sheriff in town.

The bigger point isn't the gamepad. It's that when no app fits your need, you can now build the one that does.
