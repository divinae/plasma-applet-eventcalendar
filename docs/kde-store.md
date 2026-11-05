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

**Description**

```
Your day, one click from the clock.

Calendar, agenda, tasks, meetings and weather in the Plasma panel: see what's next at a glance, join a call in one click, and never miss a meeting again.

Not just another fork: Event Calendar NG is a complete redesign of the classic Event Calendar widget, with a new look, new views, tasks, meetings, CalDAV and much more.

Website, screenshots and install guide: https://divinae.github.io/plasma-applet-eventcalendar/

Why you'll like it
🗓️ Every view you need: Month, Week, Day and Agenda. The Day view puts your hours, a small month, what's up next, today's tasks and the weather side by side.
⏰ Never late again: the clock shows your next meeting ("in 5 min") and its progress; when it starts, an optional full-screen alert with one big Join button.
🎥 One-click Join for Google Meet, Zoom, Teams, Webex, Slack huddles and about 35 more.
✅ Your tasks too: Google Tasks and TickTick with smart lists, priorities, subtasks and drag and drop. Type "Call mom tomorrow 17:00 !high" and it knows the day, time and priority.
✍️ Plan without leaving the panel: create, edit, move and answer events; quick add understands plain sentences, and Go to date takes "next friday" or "+2w".
☁️ All your calendars: several Google accounts, CalDAV (Nextcloud, Fastmail, iCloud…), KDE PIM (Akonadi), holidays and .ics files; an event in two calendars shows once.
⚡ Fast and offline-ready: opens instantly with your last events and tasks, even without a network.
🎨 At home in Plasma: rounded cards or flat, light and dark themes, 20 languages.
🔒 Private by design: sign-ins stay in your system keyring; no tracking, no servers of ours in between.

Based on Event Calendar by Chris Holland (Zren), started from ALikesToCode's Plasma 6 port and rebuilt since. It keeps the same widget id, so it replaces an existing Event Calendar and keeps its settings. For Plasma 5 use the original: https://store.kde.org/p/998901/

In detail

Views (switch from the popup's header)
- Month: event titles in the days, multi-day events as bars across them
- Week and Day: an hour grid you can scroll through the whole day; drag events to move or resize them
- Day: beside the hours a small month (dots on busy days), Up next, the day's tasks and its weather; each panel can be turned off
- Agenda: upcoming days as event tiles
- Tasks: your Google Tasks and TickTick lists
- Islands style (rounded cards, the default) or flat
- Drag events between days (Ctrl + drag copies), calendar toggles, work week, a second time zone, keyboard navigation
- Go to date: press G and type "next friday", "15 nov", "+2w"
- Opens in your default view or the last one used; tabs or a drop-down view switcher; right click the header to pick its views and buttons

Google Calendar
- Several accounts; choose calendars and task lists per account; new events start in your primary calendar
- Create, edit, duplicate and delete events: color, guests, Google Meet, reminders, recurring events (ends on a date / after N times, custom repeats; one occurrence or the whole series)
- Quick add ("Lunch with Anna tomorrow 13:00"), search, answer invitations (Yes / Maybe / No), undo after a delete or move
- Move events between calendars, busy / free, visibility, time zones, out of office, focus time, working locations
- Find a time (free slots for you and the guests), attachments, Email Guests, import .ics files
- Rename and recolor calendars
- An event in several calendars (yours and a shared one) shows once
- KDE PIM (Akonadi) calendars (Settings > Calendars) and holidays side by side with a direct Google sign-in
- Tokens are kept in the system keyring; what signing in allows: https://divinae.github.io/plasma-applet-eventcalendar/privacy.html

CalDAV
- Nextcloud, Fastmail, iCloud (with an app password), Radicale, Baïkal and others: choose the calendars of each account
- Create, edit, move and delete events there (repeating events are shown, edited in their own app for now); import .ics files into them
- The password is kept in the system keyring

Tasks
- Google Tasks and TickTick (or Dida365, with an API token kept in the system keyring) in their own tab: smart filters (All, Today, Tomorrow, Next 7 days, Overdue, No date, each list), grouped by date or by list, sorted by due date, title, list or priority
- Add a task with smart recognition: "tomorrow 17:00 !high #Work every week" sets the day, time, priority, list and repeat
- Priorities, due times, repeats, reminders, checklists (TickTick) and subtasks (Google); mark tasks in progress; drag between days, lists and accounts; undo, keyboard, search
- Manage lists: rename, color, clear completed, delete, hide from the smart lists
- Task reminders, a morning summary, and the day's tasks in the Day view
- Completed tasks of the last 30 days

Meetings
- Camera check before a meeting: the camera as a mirror, the microphone's level, hear yourself, a speaker test, then Join
- Join buttons for about 40 services (Google Meet, Zoom, Teams, Webex, Slack huddles, Discord, Chime, GoTo, Jitsi…); Google Meet links can open in a Meet web app with a chosen Google account
- Optional full-screen alert when a meeting starts: the desktop blurred behind, Join / Snooze / Dismiss
- The panel clock shows the next meeting ("in 5 min" / "12 min left"), with filters: skip all-day events, chosen calendars, only meetings with a link, only accepted
- Copy a meeting's link, mute one event's notifications, start a Meet or Zoom right away (hold +); a meeting that ended early can be marked as ended
- Music and videos pause when you join; optional Do Not Disturb during meetings and auto-join; overlapping meetings are marked

Notifications (KDE's notification system)
- Reminders before events (with Snooze, optionally hidden after N seconds) and when an event starts (optionally critical / persistent, or full screen)
- New invitations for today (Yes / Maybe / No) and a daily agenda

Weather from Open-Meteo (free, no API key), OpenWeatherMap or Weather Canada.

Starts instantly and works offline: the last loaded events and tasks are shown right away, and Plasma doesn't wait for the widget at login. The Agenda and the Tasks tab open fast even with busy calendars and long task lists.

Translated into 20 languages.

Requirements: Plasma 6, python3, the KNotifications QML module, Kirigami Addons; secret-tool (libsecret) or KWallet for Google, TickTick and CalDAV sign-in. Optional: the Python packages icalendar and recurring-ical-events for .ics files and CalDAV.

Website: https://divinae.github.io/plasma-applet-eventcalendar/
Bug reports and ideas: https://github.com/divinae/plasma-applet-eventcalendar/issues
Source and install from source: https://github.com/divinae/plasma-applet-eventcalendar

Support the development: https://ko-fi.com/divinae4535
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