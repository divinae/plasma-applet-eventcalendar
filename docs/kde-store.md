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

    1.2.0

**License**

    GPL-2.0-or-later

**Tags**

    calendar, agenda, google calendar, clock, weather, events, meetings, plasma6

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

Google Calendar
- Several accounts; choose calendars and task lists per account
- Create, edit, duplicate and delete events: color, guests, Google Meet, reminders, recurring events (ends on a date / after N times, custom repeats; one occurrence or the whole series)
- Quick add ("Lunch with Anna tomorrow 13:00"), search, answer invitations (Yes / Maybe / No), undo after a delete or move
- Rename and recolor calendars
- Tokens are kept in the system keyring

Meetings
- Join buttons for Google Meet, Zoom, Teams and other links; Google Meet links can open in a Meet web app with a chosen Google account
- The panel clock shows the next meeting ("in 5 min" / "12 min left"); a meeting that ended early can be marked as ended

Notifications (KDE's notification system)
- Reminders before events (with Snooze, optionally hidden after N seconds) and when an event starts (optionally critical / persistent)

Weather from Open-Meteo (free, no API key), OpenWeatherMap or Weather Canada.

Starts instantly and works offline: the last loaded events are shown right away.

Translated into 20 languages.

Requirements: Plasma 6, python3, the KNotifications QML module, Kirigami Addons; secret-tool (libsecret) or KWallet for Google sign-in. Optional: the Python packages icalendar and recurring-ical-events for .ics files.

Source, issues and install from source: https://github.com/divinae/plasma-applet-eventcalendar
```

**Changelog (1.2.0)**

```
- Duplicate an event (event menu, event details)
- Set an event's own reminders in the editor; notifications always use them
- Join opens Google Meet links in a chosen app (eg: a Meet web app) with a chosen Google account
- Mark a meeting in progress as ended
- Vertical panels: the next meeting above the time (time until it, then a progress bar)
- The next meeting shows from 15 minutes before by default
- Reminders can hide after a set number of seconds
- Notifications are no longer missed when the minute check comes late, and none is sent twice
- Weather is retried soon after a server error; the Day view shows the error with Retry Now
```

## Files

- **Product file:** `eventcalendar-v1.2.0-plasma6.0.plasmoid` from the
  [v1.2.0 release](https://github.com/divinae/plasma-applet-eventcalendar/releases/tag/v1.2.0),
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
