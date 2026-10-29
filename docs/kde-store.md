# KDE Store listing

Text and files for the [KDE Store](https://store.kde.org) page, ready to paste. Update the
version, the changelog and the file for each release.

## Before uploading

- **Same widget id as the original.** The original Event Calendar by Zren is on the store as
  [p/998901](https://store.kde.org/p/998901/) (Plasma 5), with the same id
  `org.kde.plasma.eventcalendar`. That's intended, since this fork replaces it and keeps its
  settings. But installing either one replaces the other, so the page must say clearly that this
  is a fork, and link the original.
- **Google sign-in.** The built-in Google OAuth client is in the package. Google's consent screen
  links a privacy policy and terms (`docs/privacy.html`, `docs/terms.html`). GitHub Pages isn't
  enabled for the fork, so those pages aren't online yet. Turn on Pages (from `docs/` on
  `master`), or link the files on GitHub, before the listing points people to Google sign-in.

## Fields

**Title**

    Event Calendar (Plasma 6)

**Category**

    Plasma 6 Extensions > Plasma 6 Widgets

**Version**

    1.8.3

**License**

    GPL-2.0-or-later

**Tags**

    calendar, agenda, google calendar, clock, weather, events, meetings, plasma6

**Donation link** (the store's donation / "Support" field)

    https://ko-fi.com/divinae4535

**Source / homepage**

    https://github.com/divinae/plasma-applet-eventcalendar

**Summary (one line)**

    Calendar, agenda, week and day views for the panel, with Google Calendar, meeting Join buttons, notifications and weather.

**Description**

```
A calendar, agenda and weather widget for the Plasma 6 panel that syncs with Google Calendar, Plasma (Akonadi / holiday) calendars and iCalendar (.ics) files.

This is a maintained Plasma 6 fork of Event Calendar by Chris Holland (Zren), via ALikesToCode's Plasma 6 port. It keeps the same widget id, so it replaces an existing Event Calendar and keeps its settings. For Plasma 5 use the original: https://store.kde.org/p/998901/

Views (switch from the popup's header)
- Month: event titles in the days, multi-day events as bars across them
- Week and Day: an hour grid you can scroll through the whole day; drag events to move or resize them
- Day: beside the hours a small month (dots on busy days), Up next, the day's tasks and its weather; each panel can be turned off
- Agenda: upcoming days as event tiles
- Tasks: your Google Tasks and TickTick lists
- Islands style (rounded cards, the default) or flat
- Drag events between days (Ctrl + drag copies), calendar toggles, work week, a second time zone, keyboard navigation

Google Calendar
- Several accounts; choose calendars and task lists per account
- Create, edit, duplicate and delete events: color, guests, Google Meet, reminders, recurring events (ends on a date / after N times, custom repeats; one occurrence or the whole series)
- Quick add ("Lunch with Anna tomorrow 13:00"), search, answer invitations (Yes / Maybe / No), undo after a delete or move
- Move events between calendars, busy / free, visibility, time zones, out of office, focus time, working locations
- Find a time (free slots for you and the guests), attachments, Email Guests, import .ics files
- Rename and recolor calendars
- Tokens are kept in the system keyring

Tasks
- Google Tasks and TickTick (or Dida365, with an API token kept in the system keyring) in their own tab: smart filters (All, Today, Tomorrow, Next 7 days, Overdue, No date, each list), grouped by date or by list, sorted by due date, title, list or priority
- Add a task with smart recognition: "tomorrow 17:00 !high #Work every week" sets the day, time, priority, list and repeat
- Priorities, due times, repeats, reminders, checklists (TickTick) and subtasks (Google); mark tasks in progress; drag between days, lists and accounts; undo, keyboard, search
- Manage lists: rename, color, clear completed, delete, hide from the smart lists
- Task reminders, a morning summary, and the day's tasks in the Day view

Meetings
- Join buttons for Google Meet, Zoom, Teams and other links; Google Meet links can open in a Meet web app with a chosen Google account
- The panel clock shows the next meeting ("in 5 min" / "12 min left"); a meeting that ended early can be marked as ended
- Music and videos pause when you join; optional Do Not Disturb during meetings and auto-join; overlapping meetings are marked

Notifications (KDE's notification system)
- Reminders before events (with Snooze, optionally hidden after N seconds) and when an event starts (optionally critical / persistent)
- New invitations for today (Yes / Maybe / No) and a daily agenda

Weather from Open-Meteo (free, no API key), OpenWeatherMap or Weather Canada.

Starts instantly and works offline: the last loaded events and tasks are shown right away.

Translated into 20 languages.

Requirements: Plasma 6, python3, the KNotifications QML module, Kirigami Addons; secret-tool (libsecret) or KWallet for Google and TickTick sign-in. Optional: the Python packages icalendar and recurring-ical-events for .ics files.

Bug reports and ideas: https://github.com/divinae/plasma-applet-eventcalendar/issues
Source and install from source: https://github.com/divinae/plasma-applet-eventcalendar

Support the development: https://ko-fi.com/divinae4535
```

**Changelog (1.8.3)**

```
Popup
- Right click on the header: the views offered, tabs or a drop-down menu, and which buttons show (the others in a menu)
```

## Files

- **Product file:** `eventcalendar-v1.8.3-plasma6.0.plasmoid` from the
  [v1.8.3 release](https://github.com/divinae/plasma-applet-eventcalendar/releases/tag/v1.8.3),
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