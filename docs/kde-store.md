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

    1.3.0

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
- Week and Day: an hour grid you can scroll through the whole day; drag events to move or resize them; the Day view has a weather panel for the day shown
- Agenda: upcoming days as event tiles
- Drag events between days (Ctrl + drag copies), calendar toggles, work week, a second time zone, keyboard navigation

Google Calendar
- Several accounts; choose calendars and task lists per account
- Create, edit, duplicate and delete events: color, guests, Google Meet, reminders, recurring events (ends on a date / after N times, custom repeats; one occurrence or the whole series)
- Quick add ("Lunch with Anna tomorrow 13:00"), search, answer invitations (Yes / Maybe / No), undo after a delete or move
- Move events between calendars, busy / free, visibility, time zones, out of office, focus time, working locations
- Find a time (free slots for you and the guests), attachments, Email Guests, import .ics files
- Rename and recolor calendars
- Tokens are kept in the system keyring

Meetings
- Join buttons for Google Meet, Zoom, Teams and other links; Google Meet links can open in a Meet web app with a chosen Google account
- The panel clock shows the next meeting ("in 5 min" / "12 min left"); a meeting that ended early can be marked as ended
- Optional Do Not Disturb during meetings and auto-join; overlapping meetings are marked

Notifications (KDE's notification system)
- Reminders before events (with Snooze, optionally hidden after N seconds) and when an event starts (optionally critical / persistent)
- New invitations for today (Yes / Maybe / No) and a daily agenda

Weather from Open-Meteo (free, no API key), OpenWeatherMap or Weather Canada.

Starts instantly and works offline: the last loaded events are shown right away.

Translated into 20 languages.

Requirements: Plasma 6, python3, the KNotifications QML module, Kirigami Addons; secret-tool (libsecret) or KWallet for Google sign-in. Optional: the Python packages icalendar and recurring-ical-events for .ics files.

Source, issues and install from source: https://github.com/divinae/plasma-applet-eventcalendar

Support the development: https://ko-fi.com/divinae4535
```

**Changelog (1.3.0)**

```
- Notifications for new invitations to today's meetings, with Yes / Maybe / No
- Do Not Disturb during meetings, auto-join, a daily agenda notification
- Overlapping meetings are marked; Find a time in the event editor
- Move events between calendars; busy / free and visibility; the event's time zone
- Out of office, focus time and working locations
- Import .ics files into Google Calendar; attachments; Email Guests
- Calendar toggles in the popup; hide declined events
- Week view: work week, a second time zone; drag events in the Month view and all-day bars in the Week view (Ctrl copies)
- Keyboard navigation; the Month view uses the configured popup size
- Fixes: no hang when Google sign-in fails, failed moves put the event back, series time zone, settings combos
```

## Files

- **Product file:** `eventcalendar-v1.3.0-plasma6.0.plasmoid` from the
  [v1.3.0 release](https://github.com/divinae/plasma-applet-eventcalendar/releases/tag/v1.3.0),
  or `./build`.
- **Screenshots** (`docs/screenshots/`, mock data), in this order:
  1. `month.png`
  2. `week.png`
  3. `today.png` (Day view)
  4. `agenda.png`
  5. `event-details.png`
  6. `settings-google.png`
- **Logo:** the Breeze `office-calendar` app icon as a 256×256 PNG:
  `rsvg-convert -w 256 -h 256 /usr/share/icons/breeze/apps/48/office-calendar.svg -o logo.png`
  (the widget itself uses the theme icon `view-calendar`).
