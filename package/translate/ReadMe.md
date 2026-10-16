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
| Template |     429 |       |
| da       | 429/429 |  100% |
| de       | 429/429 |  100% |
| el       | 429/429 |  100% |
| es       | 429/429 |  100% |
| fi       | 429/429 |  100% |
| fr       | 429/429 |  100% |
| he       | 429/429 |  100% |
| it       | 429/429 |  100% |
| ja       | 429/429 |  100% |
| ko       | 429/429 |  100% |
| nl       | 429/429 |  100% |
| pl       | 429/429 |  100% |
| pt_BR    | 429/429 |  100% |
| pt_PT    | 429/429 |  100% |
| ru       | 429/429 |  100% |
| sl       | 429/429 |  100% |
| sv       | 429/429 |  100% |
| tr       | 429/429 |  100% |
| uk       | 429/429 |  100% |
| zh_CN    | 429/429 |  100% |
