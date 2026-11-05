# KDE Store listing

Text and files for the [KDE Store](https://store.kde.org) page, ready to paste. Update the
version, the changelog and the file for each release.

## Before uploading

- **Same widget id as the original.** The original Event Calendar by Zren is on the store as
  [p/998901](https://store.kde.org/p/998901/) (Plasma 5), with the same id
  `org.kde.plasma.eventcalendar`. That's intended, since this fork replaces it and keeps its
  settings. But installing either one replaces the other, so the page must say clearly what it
  is based on (a complete redesign of the original), and link the original.
- **Google sign-in.** The built-in Google OAuth client is in the package. Google's consent screen
  links a privacy policy and terms (`docs/privacy.html`, `docs/terms.html`), online through GitHub
  Pages (from `docs/` on `master`): https://divinae.github.io/plasma-applet-eventcalendar/privacy.html
  and https://divinae.github.io/plasma-applet-eventcalendar/terms.html. The widget's Google tab
  links the privacy policy under "Sign in with Google".

## Fields

**Title**

    Event Calendar NG

**Category**

    Plasma 6 Extensions > Plasma 6 Widgets

**Version**

    1.22.0

**License**

    GPL-2.0-or-later

**Tags**

    calendar, agenda, google calendar, clock, weather, events, meetings, plasma6

**Donation link** (the store's donation / "Support" field)

    https://ko-fi.com/divinae4535

**Source / homepage**

    https://github.com/divinae/plasma-applet-eventcalendar

**Summary (one line)**

    Your day, one click from the clock: calendar, agenda, tasks, meetings and weather in the Plasma panel.

**Description** (each line its own paragraph: the store joins lines that have only a single line break between them)

```
Your day, one click from the clock: calendar, agenda, tasks, meetings and weather in the Plasma panel. See what's next at a glance, join a call in one click, never miss a meeting.

Not just another fork: a complete redesign of the classic Event Calendar widget.

Website and screenshots: https://divinae.github.io/plasma-applet-eventcalendar/

🗓️ Month, Week, Day and Agenda views; drag events to move or resize them

⏰ The clock shows your next meeting ("in 5 min"), with an optional full-screen alert and a big Join button

🎥 One-click Join for Google Meet, Zoom, Teams, Webex, Slack and about 35 more; camera check before a call

✅ Google Tasks and TickTick: smart lists, priorities, subtasks, quick add ("Call mom tomorrow 17:00 !high")

✍️ Create, edit and answer events in the widget; quick add in plain sentences

☁️ Several Google accounts, CalDAV (Nextcloud, Fastmail, iCloud…), KDE PIM, holidays, .ics files

🔔 Reminders, invitations and a daily agenda in KDE's notifications

🌤️ Weather from Open-Meteo (no key), OpenWeatherMap or Weather Canada

⚡ Opens instantly and works offline with your last events and tasks

🎨 Rounded cards or flat, light and dark themes, 20 languages

🔒 Sign-ins stay in your system keyring; no tracking, no servers of ours

Based on Event Calendar by Chris Holland (Zren) and ALikesToCode's Plasma 6 port. Same widget id: it replaces an existing Event Calendar and keeps its settings. For Plasma 5: https://store.kde.org/p/998901/

Requires Plasma 6 and python3; secret-tool or KWallet for sign-ins. CalDAV and .ics need two Python modules (the widget offers to install them).

Bugs and ideas: https://github.com/divinae/plasma-applet-eventcalendar/issues

Support: https://ko-fi.com/divinae4535
```

**Changelog (1.22.0)**

```
- Tasks: new Google tasks no longer disappear after a restart or refresh
- Completed tasks: those of the last 30 days, as the list now says
- Faster login: Plasma no longer waits for the widget (KDE PIM and plugins load after it)
- The clock's seconds change with the system clock
- New events start in your primary calendar
- Google sign-in: what it allows, and the privacy policy; a new website
```

**Changelog (1.21.0)**

```
- Month view: an option to show all events, each week as tall as its busiest day (thanks to frispete)
- CalDAV and .ics events remind at their own alarms (Settings > Events)
- Glance sharing: the weather, opening events from Glance
- Settings: a General page (Glance, offline start, settings backup, troubleshooting)
```

**Changelog (1.20.0)**

```
- Fix: the Agenda no longer freezes Plasma (its event tiles fought their layout over their width; thanks to frispete)
- The Agenda opens at today; the mouse wheel no longer reaches the desktop through the widget
- Optional: share today's events with the Glance panel widget (Settings > Calendars > General)
```

**Changelog (1.19.0)**

```
- Fix: the Agenda no longer freezes Plasma with the weather not set up; the meteogram and timer above it are removed
- The Weather switch (Settings > Views) turns the forecast off in all the views
- Camera check: the camera's own zoom works (opened at 720p, as video calls)
- Settings: alike monochrome page icons
```

**Changelog (1.18.0)**

```
- Fix: Plasma no longer crashes on Refresh with the holidays / KDE PIM calendar plugins on
- Weather: sunrise and sunset; details under the mouse in the charts; nights by the sun
- Moon box in the Day view and Agenda (optional, Settings > Views; thanks to frispete)
- Style: islands with translucent cards
- Fixes from frispete: Day view all-day events after the Agenda, OpenWeatherMap texts in your language
```

**Changelog (1.17.0)**

```
- Pick a color for CalDAV and iCalendar calendars (Settings > Calendars)
- Export and import the widget's settings to a file (Settings > Views > Settings Backup), without passwords or sign-ins
- KDE PIM (Akonadi) calendars chosen in a new Akonadi tab of Settings > Calendars (thanks to frispete)
```

**Changelog (1.16.1)**

```
- CalDAV and .ics calendars: the Python modules they need are checked and installed from Settings > Calendars (no more "No module named 'icalendar'")
```

**Changelog (1.16.0)**

```
- Calendars show as they come (a slow CalDAV server or .ics link doesn't hold back the others), with a loading bar
- CalDAV: unchanged calendars aren't downloaded again
- Agenda: the header shows the day you scrolled to; the arrows go day by day
- Your own names for time zones (eg: "Boston" for New York)
- Notifications only for the clock's calendars (option; thanks to frispete)
- Fix: Refresh could crash Plasma 6.3 (plugins reloaded at most every 30 s)
```

**Changelog (1.15.0)**

```
- Camera check before a meeting: the camera as a mirror, the microphone's level and sensitivity, hear yourself, a speaker test, then Join (window on top; also in the full-screen alert)
- Month <-> Week / Day much faster
- Settings: .ics files and links as read-only calendars (Calendars > iCalendar); the import card installs its Python modules
- Settings > Events: full screen and notification options apart
- Fix: the header's title in the Agenda changed only the title
```

**Changelog (1.14.0)**

```
- Settings: Calendars in one page with tabs (General, Google Calendar, CalDAV); import from a file is under Calendars > General
- Calendar menu: CalDAV calendar names shown in full, under their account
```

**Changelog (1.13.0)**

```
- CalDAV: Nextcloud, Fastmail, iCloud, Radicale, Baïkal... (Settings > CalDAV): events shown, created, edited, deleted and imported
- Import events from an .ics file from Settings > Events
- Time zones can be put in order and are no longer forgotten
- Akonadi calendars named after their calendars; a warning for calendars Akonadi no longer has (thanks to frispete)
```

**Changelog (1.12.1)**

```
- Dark themes: the date and time pickers showed light text on a white background
```

**Changelog (1.12.0)**

```
- Faster: views open 2-3x faster; months seen stay in memory and the next ones load ahead
- Agenda: the Day view's layout (small month, today's tasks and weather beside the list), more months when scrolled to the end
- Small month: today a solid tile, the shown day a pale one, the Agenda's days in sight a band
- Gentle animations (month paging, cards, ticking off a task, the clock's chip), can be turned off
- Up next: choose how many days it covers
- Weather: high, low and rain beside the temperature, the location opens the full forecast
- Fixes: Day -> Week showed only the first column
```

## Files

- **Product file:** `eventcalendar-ng-v1.22.0.plasmoid` from the
  [v1.22.0 release](https://github.com/divinae/plasma-applet-eventcalendar/releases/tag/v1.22.0),
  or `./build`.
- **Screenshots** (`docs/screenshots/`, mock data; the store takes at most 5), in this order:
  1. `month.png` (the cover)
  2. `today.png` (Day view: small month, Up next, the hours, tasks and weather)
  3. `tasks.png`
  4. `week.png`
  5. `agenda.png`
- **Logo:** `docs/logo.png` (512×512, from `docs/logo.svg`: a calendar page with event bars, a
  task check and a sun, on the widget's blue). Another size:
  `rsvg-convert -w 256 -h 256 docs/logo.svg -o logo-256.png`