> Version 7 of Zren's i18n scripts.

With KDE Frameworks v5.37 and above, translations are bundled with the `*.plasmoid` file downloaded from the store.

## Install Translations

Go to `~/.local/share/plasma/plasmoids/org.kde.plasma.eventcalendar/translate/` and run `sh ./build --restartplasma`.

## New Translations

1. Fill out [`template.pot`](template.pot) with your translations then open a [new issue](https://github.com/divinae/plasma-applet-eventcalendar/issues/new), name the file `spanish.txt`, attach the txt file to the issue (drag and drop).

Or if you know how to make a pull request

1. Copy the `template.pot` file and name it your locale's code (Eg: `en`/`de`/`fr`) with the extension `.po`. Then fill out all the `msgstr ""`.

## Scripts

* `sh ./merge` will parse the `i18n()` calls in the `*.qml` files and write it to the `template.pot` file. Then it will merge any changes into the `*.po` language files.
* `sh ./build` will convert the `*.po` files to it's binary `*.mo` version and move it to `contents/locale/...` which will bundle the translations in the `*.plasmoid` without needing the user to manually install them.
* `sh ./plasmoidlocaletest` will run `./build` then `plasmoidviewer` (part of `plasma-sdk`).

## Links

* https://zren.github.io/kde/docs/widget/#translations-i18n
* https://techbase.kde.org/Development/Tutorials/Localization/i18n_Build_Systems
* https://api.kde.org/frameworks/ki18n/html/prg_guide.html

## Examples

* https://l10n.kde.org/stats/gui/trunk-kf5/team/fr/plasma-desktop/
* https://github.com/psifidotos/nowdock-plasmoid/tree/master/po
* https://github.com/kotelnik/plasma-applet-redshift-control/tree/master/translations

## Status
|  Locale  |  Lines  | % Done|
|----------|---------|-------|
| Template |     730 |       |
| da       | 729/730 |   99% |
| de       | 729/730 |   99% |
| el       | 729/730 |   99% |
| es       | 729/730 |   99% |
| fi       | 729/730 |   99% |
| fr       | 729/730 |   99% |
| he       | 729/730 |   99% |
| it       | 729/730 |   99% |
| ja       | 729/730 |   99% |
| ko       | 729/730 |   99% |
| nl       | 729/730 |   99% |
| pl       | 729/730 |   99% |
| pt_BR    | 729/730 |   99% |
| pt_PT    | 729/730 |   99% |
| ru       | 729/730 |   99% |
| sl       | 729/730 |   99% |
| sv       | 729/730 |   99% |
| tr       | 729/730 |   99% |
| uk       | 729/730 |   99% |
| zh_CN    | 729/730 |   99% |
