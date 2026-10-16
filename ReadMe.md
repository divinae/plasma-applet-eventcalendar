# Event Calendar for Plasma 6

[![CI](https://github.com/divinae/plasma-applet-eventcalendar/actions/workflows/ci.yml/badge.svg)](https://github.com/divinae/plasma-applet-eventcalendar/actions/workflows/ci.yml)

A calendar, agenda and weather widget for the KDE Plasma 6 panel that syncs with Google Calendar,
Plasma (Akonadi / holiday) calendars and iCalendar (.ics) files.

This is a maintained fork of [Event Calendar](https://github.com/Zren/plasma-applet-eventcalendar)
by Chris Holland (Zren), via [ALikesToCode's Plasma 6 port](https://github.com/ALikesToCode/plasma-applet-eventcalendar).
It keeps the same widget id, so it replaces an existing Event Calendar and keeps its settings.

## Features

- **Views** in the popup, switchable from its header: **Month** (event titles in the days,
  multi-day events as bars across them), **Week** and **Day** (an hour grid you can scroll through
  the whole day; drag events to move or resize them; the Day view has a weather panel for the day
  shown) and **Agenda** (a list of upcoming days).
- **Google Calendar**: several accounts at once, choose calendars and task lists per account.
  Create, edit and delete events with color, guests, Google Meet and **recurring events** (ends on
  a date / after N times, custom repeats; edit one occurrence or the whole series). Quick add
  ("Lunch with Anna tomorrow 13:00"), search, answer invitations (Yes / Maybe / No), undo after a
  delete or move, rename and recolor calendars. Tokens are kept in the system keyring.
- **Meetings**: Join buttons for Google Meet, Zoom, Teams and other links, in the agenda, the
  Day view, the event details, notifications and the panel's right-click menu. The panel clock
  can show the next meeting ("in 5 min" / "12 min left").
- **Notifications** through KDE's notification system: reminders before events (with Snooze),
  when an event starts (optionally critical / persistent), each configurable in System Settings >
  Notifications > Event Calendar. Clicking one opens the event in the widget.
- **Weather** from Open-Meteo (free, no API key; search your city in the settings), or
  OpenWeatherMap / Weather Canada.
- **Starts instantly and works offline**: the last loaded events are shown right away and stay
  visible offline, fetches are retried automatically, and a banner shows when it can't connect.
- Invitations look like in Google Calendar (outlined / striped / struck through), icons for what
  an event has set, adjustable event text size, event locations open in Google Maps, dark theme
  friendly event colors, right-click menus on events, translated into 20 languages.

## Screenshots

All shots use mock data.

| | |
|---|---|
| ![Month view](docs/screenshots/month.png) **Month**: event titles in the days | ![Week view](docs/screenshots/week.png) **Week**: hour grid, all-day events, weather |
| ![Day view](docs/screenshots/today.png) **Day**: one day with a weather panel and Join buttons | ![Agenda](docs/screenshots/agenda.png) **Agenda**: upcoming days as event tiles |
| ![Event details](docs/screenshots/event-details.png) **Event details**: location, guests, Join | ![Google Calendar settings](docs/screenshots/settings-google.png) **Settings**: accounts, calendars and task lists |

## Install

### From a release

Download the `.plasmoid` file from the [latest release](https://github.com/divinae/plasma-applet-eventcalendar/releases),
then:

```
kpackagetool6 -t Plasma/Applet -i eventcalendar-v1.1.0-plasma6.0.plasmoid
# or, to upgrade an installed Event Calendar:
kpackagetool6 -t Plasma/Applet -u eventcalendar-v1.1.0-plasma6.0.plasmoid
```

Restart Plasma (`systemctl --user restart plasma-plasmashell`) and add **Event Calendar** to a
panel (right click the panel > Add or Manage Widgets), or replace the Digital Clock with it.

### From source

```
git clone https://github.com/divinae/plasma-applet-eventcalendar.git eventcalendar
cd eventcalendar
sh ./install
```

`sh ./update` pulls and reinstalls; `sh ./uninstall` removes the widget. The scripts install the
dependencies below on Debian/Ubuntu, Arch and Fedora.

## Dependencies

- Plasma 6 (Qt 6 and KDE Frameworks 6)
- `python3`
- KNotifications QML module (`org.kde.notification`; Debian/Ubuntu:
  `qml6-module-org-kde-notification`, Arch: `knotifications`, Fedora: `kf6-knotifications`)
- Kirigami Addons (settings pages)
- `secret-tool` (libsecret) or KWallet, for storing Google tokens in the keyring

Optional:

- `pw-play` (PipeWire), `paplay` (PulseAudio) or `canberra-gtk-play`, for custom notification sounds
- iCalendar (.ics) files: the Python packages `icalendar>=6.1,<8` and
  `recurring-ical-events>=3.8,<4` (RRULE / RDATE / EXDATE / RECURRENCE-ID expansion). The install
  script puts them under `~/.local/share/plasma_org.kde.plasma.eventcalendar/python`.
- Akonadi / KDE PIM calendars: `akonadi` + `kdepim-addons`; creating local events: `konsolekalendar`

## Setup

1. Right click the widget > Configure Event Calendar.
2. **Google Calendar**: Sign in with Google. Your browser opens; after you allow access, the
   widget picks it up. Then choose the calendars and task lists to show for each account.
3. **Weather**: search for your city (Open-Meteo).
4. **Views**: choose the default view, the popup size and the hours shown in the week view.

Plasma 5 is not supported; use the original [Event Calendar](https://github.com/Zren/plasma-applet-eventcalendar) there.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests: `for t in tests/*.test.js; do node "$t"; done`
and `python3 tests/*_test.py`. Translations live in `package/translate/` (see its ReadMe).

## License

GPL-2.0-or-later, like the original widget.
