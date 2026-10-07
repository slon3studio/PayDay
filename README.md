# PayDay

**A shift and pay tracker for people who work more than one job.**

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![UI](https://img.shields.io/badge/SwiftUI-SwiftData-blue)

Most hour trackers assume one employer and a fixed salary. PayDay assumes the
opposite: a bar on weekends, a studio on Tuesdays, deliveries when they come
up — different rates, different hours, some with tips and some without.

It answers three questions. What have I worked this month? What will the month
pay me? And did the payslip actually match?

---

## What it does

**A tab per job.** Add as many as you like. Each keeps its own hourly rate,
usual hours, colour and icon, and gets its own tab in the bar.

**Shifts logged in seconds.** Repeat your last shift with one tap, or pick a
day straight from the week strip or the month calendar. A shift that runs past
midnight is counted toward the day it started, not the day it ended.

**Tips**, for the jobs that have them and hidden for the ones that don't.

**A projection of the month.** Hours logged so far, plus the remaining days
filled in at your average. Remaining days can be counted as weekdays, as every
day, or weighted by how often you actually work each weekday — so a Friday and
Saturday job isn't projected across all five weekdays.

**A monthly goal** in hours or money, with progress on the job's card.

**Payslip checking.** Mark a month as paid, enter what actually landed in your
account, and PayDay tells you whether it matched what the shifts came to, and
by how much it didn't.

**Timesheets.** Any month as a table of dates, times and hours, exported as a
PDF to print or hand in, or a CSV for a spreadsheet.

**iCloud sync** through your own private database, across every device signed
in to the same Apple Account. The app works fully without it.

No account, no ads, no analytics, no third-party SDKs.

---

## Get it

**App Store** — _not published yet. Link goes here once it is._

**TestFlight** — not open yet.

### Build from source

Requires macOS with Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/slon3studio/PayDay.git
cd PayDay
./generate.sh
open PayDay.xcodeproj
```

Pick an iPhone simulator and run. iPhone only, portrait only — the layout is
tuned for a 402pt-wide screen.

> **Use `./generate.sh`, not `xcodegen generate`.** XcodeGen can't write the
> nested target attributes Xcode's Signing & Capabilities tab reads, so the
> script runs XcodeGen and then patches iCloud, Push and Background Modes into
> the project file. Running XcodeGen alone produces a project that builds but
> shows "the capability associated with ICLOUD could not be determined".

Signing and iCloud both need a team selected. On your own account you'll want
to change `PRODUCT_BUNDLE_IDENTIFIER` and the iCloud container in
`project.yml`, then run `./generate.sh` again. **Edit build settings there, not
in Xcode's UI** — the next generate overwrites anything set in Xcode.

Without an iCloud container the app still runs; it falls back to local-only
storage and says so in Settings.

---

## How it works

**`Job` is data, not an enum.** Earlier versions hard-coded two jobs, then one.
Everything that used to be a constant — rate, colour, tips, usual hours — is now
a stored property on a `Job` record, which is what makes the tab bar dynamic.

**Shifts freeze their rate.** Each `Shift` stores the `rate` it was logged at,
so raising a job's hourly rate doesn't silently repay every month you've
already been paid for.

**Migration runs off `jobRaw`.** `Shift` and `MonthPayment` keep a legacy
`jobRaw` field written by the two-job version. `AppSetup.migrateIfNeeded` uses
it, and only it, to decide whether there's anything to carry over — so a device
part-way through its first iCloud sync can't be mistaken for an upgrade.

**The store degrades instead of crashing.** `PayDayApp` tries an
iCloud-backed container, falls back to local-only, and only then shows an error
screen. A force-unwrap here used to kill the app on launch for anyone without
iCloud, which is the normal state of an App Review device.

**CloudKit needs all properties optional or defaulted**, and every relationship
needs an inverse. That constraint shapes the model layer more than anything
else in it.

**Keyboard dismissal is a window-level gesture.** A tap gesture on a `Form`
swallows taps meant for the form's own buttons since iOS 18. `KeyboardDismisser`
attaches to the window with `cancelsTouchesInView = false` instead, so the tap
reaches the button and closes the keyboard on the way.

---

## Project structure

| Path | What's in it |
| --- | --- |
| `PayDay/App/` | Entry point, store setup, the tab bar |
| `PayDay/Models/` | `Job`, `Shift`, `MonthPayment`, settings, migration |
| `PayDay/Stats/` | All the maths: totals, averages, projection, chart buckets |
| `PayDay/Views/` | Job tab, history, timesheet, editors, shared components |
| `PayDay/Support/` | Formatting, export, keyboard, preview data |
| `project.yml` + `generate.sh` | Where the Xcode project comes from |
| `Backups/` | Snapshots from before the two rewrites, kept for reference |

---

## Privacy

Everything stays on the device and in the user's own private CloudKit
database. The developer has no access to it. The app requests no permissions,
contains no analytics, and links no third-party SDKs — the only imports are
Apple's own.

---

## Not done yet

- **Rate bands.** A Sunday or night shift is currently priced the same as a
  Tuesday afternoon one. The most valuable missing feature.
- **Localisation.** English only.
- **Reminders** to log a shift on a day you usually work.
- **A home screen widget** showing the month so far.

---

## License

Not yet chosen — all rights reserved for now.
