# Event Calendar for Plasma 6

A calendar, agenda and weather widget for the KDE Plasma 6 panel that syncs with Google Calendar,
Plasma (Akonadi / holiday) calendars and iCalendar (.ics) files.

This is a maintained fork of [Event Calendar](https://github.com/Zren/plasma-applet-eventcalendar)
by Chris Holland (Zren), via [ALikesToCode's Plasma 6 port](https://github.com/ALikesToCode/plasma-applet-eventcalendar).
It keeps the same widget id, so it replaces an existing Event Calendar and keeps its settings.

## Features

- **Views** in the popup, switchable from its header: **Month** (event titles in the days),
  **Week** (hour grid, all-day events, click an empty slot to add an event), **Today** (one day
  with a weather panel) and **Agenda** (a list of upcoming days).
- **Google Calendar**: several accounts at once, choose calendars and task lists per account,
  create / edit / delete events, **recurring events** (set how an event repeats, edit one
  occurrence or the whole series). Tokens are kept in the system keyring.
- **Meetings**: Join buttons for Google Meet, Zoom, Teams and other links, in the agenda, the
  Today view, the event details, notifications and the panel's right-click menu.
- **Notifications** through KDE's notification system: reminders before events (with Snooze),
  when an event starts (optionally critical / persistent), each configurable in System Settings >
  Notifications > Event Calendar. Clicking one opens the event in the widget.
- **Weather** from Open-Meteo (free, no API key; search your city in the settings), or
  OpenWeatherMap / Weather Canada.
- **Works offline**: the last loaded events stay visible, fetches are retried automatically, and
  a banner shows when it can't connect.
- Event locations open in Google Maps, dark theme friendly event colors, right-click menus on
  events, translated into 20 languages.

## Screenshots

All shots use mock data.

| | |
|---|---|
| ![Month view](docs/screenshots/month.png) **Month**: event titles in the days | ![Week view](docs/screenshots/week.png) **Week**: hour grid, all-day events, weather |
| ![Today view](docs/screenshots/today.png) **Today**: the day with a weather panel and Join buttons | ![Agenda](docs/screenshots/agenda.png) **Agenda**: upcoming days as event tiles |
| ![Event details](docs/screenshots/event-details.png) **Event details**: location, guests, Join | ![Google Calendar settings](docs/screenshots/settings-google.png) **Settings**: accounts, calendars and task lists |

## Install

### From a release

Download the `.plasmoid` file from the [latest release](https://github.com/divinae/plasma-applet-eventcalendar/releases),
then:

```
kpackagetool6 -t Plasma/Applet -i eventcalendar-v1.0.0-plasma6.0.plasmoid
# or, to upgrade an installed Event Calendar:
kpackagetool6 -t Plasma/Applet -u eventcalendar-v1.0.0-plasma6.0.plasmoid
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

## Branches

- `master`: releases.
- `plasma-6`: development.

Plasma 5 is not supported; use the original [Event Calendar](https://github.com/Zren/plasma-applet-eventcalendar) there.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests: `for t in tests/*.test.js; do node "$t"; done`
and `python3 tests/*_test.py`. Translations live in `package/translate/` (see its ReadMe).

## License

GPL-2.0-or-later, like the original widget.
