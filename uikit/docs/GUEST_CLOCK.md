# Pinned guest wall clock

Demo content dates its items relative to launch (stupid social's demo chats are "N minutes before
now"), so a guest run shows the time of day it ran while a reference screenshot shows the time it
was taken: "15:27" where the simulator showed "9:59", and the different text width wraps
differently. A guest can start its wall clock at a chosen instant instead.

## machorun: `MACHORUN_WALL_CLOCK_START`

`MACHORUN_WALL_CLOCK_START=<unix seconds>[.<fraction, up to 9 digits>]` makes machorun's libSystem
(`machorun/darwin/src/posix.c`) report that instant as the wall clock when its bootstrap runs, and
from there the wall clock advances with the host's, as on a device whose clock was set to that
instant. It is one constant offset applied where the guest reads the wall clock:

- `clock_gettime(CLOCK_REALTIME)` (swift-foundation's `Date()` / `Date.now`, dispatch wall time),
  `clock_gettime_nsec_np(CLOCK_REALTIME)`, `gettimeofday`, `time`.
- `pthread_cond_timedwait` converts its absolute deadline (a guest wall-clock instant) back to the
  host's before glibc waits on it (`libsystem.c`).

Monotonic clocks are untouched (`CLOCK_MONOTONIC`, `CLOCK_UPTIME_RAW`, `mach_absolute_time`,
`mach_continuous_time`): animations, the host loop, timers and `Task.sleep` keep the host's pace, as
iOS's do when the wall clock is set. Dispatch wall-time deadlines become relative delays inside the
guest (`full/shims/concpatch.c`), so they stay consistent. Not shifted: file timestamps (`stat`,
`utimes`) and anything the host-side ELF bridges read themselves (none of them reads "now" for the
guest). Unset, the offset is zero. A malformed value is fatal at launch
(`machorun/libSystem: MACHORUN_WALL_CLOCK_START must be ...`).

The time zone is the process's `TZ` (swift-foundation's `TimeZone.current` reads `TZ` before
`/etc/localtime`; ICU and libc read it too).

## stupid-app-preview harness

`scripts/openuikit/stupid-social-guest.sh`:

- `SSG_NOW=<ISO-8601 instant>` (a zone designator is required, e.g. `2026-10-31T10:01:00+02:00` or
  `...Z`) becomes `MACHORUN_WALL_CLOCK_START`.
- `SSG_TZ=<IANA zone>` becomes `TZ` (must exist under `/usr/share/zoneinfo`).
- `SSG_PRINT_CLOCK=1` logs `SSG_CLOCK now=... local=... zone=... offset=...` at launch.

Neither has a default: the reference machine's zone and capture instants are passed at run time,
never committed.

The clock runs in real time from launch, so a screen that computes its times when it opens sees
`SSG_NOW` plus the time the guest took to get there (tens of seconds for a scripted run that pushes a
chat). Demo times have minute resolution: pick `SSG_NOW` at the start of the reference's minute
window (below) and keep the run short enough to stay inside it.

## Reproducing a reference capture

A reference's capture minute follows from its visible times and the demo data's offsets
(`DemoChats.swift`: each message is `now - minutes`). For stupid social at `addc1744`, the Chats
list's Apron row shows its latest message, 2 minutes old, so the list was built in the minute two
minutes after the time it shows; the other rows (4, 18, 20, 41, 150, 290 and 400 minutes old) must
agree. The times fix the local minute only: any zone with the reference's UTC offset at that date,
with the matching instant, renders the same. A pushed chat computes its
messages when it opens, so each chat reference has its own minute (the Telegram chat's four bubble
times at 64, 60, 5 and 4 minutes give it). Root feed times are relative ("3m") and need no pin. The
instants and zone themselves are the reference machine's and are passed at run time.

Verified with stupid social (iOS triple, `SSG_LOCALE` set to the reference's locale) against the iOS
27 references: the Chats list and the Apron group chat with one instant, the Telegram chat with
another; every visible time is identical to the reference.
