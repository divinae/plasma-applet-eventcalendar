# Contributing

Thanks for helping keep Event Calendar alive.

Everything happens on `master` (Plasma 6 only). For bigger changes, open an
issue first.

## Quick start

1. Fork the repo.
2. Clone it:

```bash
git clone https://github.com/divinae/plasma-applet-eventcalendar.git
cd plasma-applet-eventcalendar
```

3. Install the widget locally:

```bash
./install
```

The install script restarts `plasmashell` so you do not have to log out.

## Reporting issues

Please include:

- Plasma version and distro.
- Steps to reproduce.
- Expected vs actual behavior.
- Logs. Two easy options:
  - Run `plasmashell --replace` in a terminal and capture the output.
  - Run `journalctl --user -b | rg eventcalendar`.

If you are reporting Google OAuth problems, do not post tokens, client secrets,
or full redirect URLs. Redact them before sharing.

## Code guidelines

- Keep the existing formatting style in each file.
- Use `i18n` / `i18nc` for user facing strings.
- If you add a new config key, update:
  - `package/contents/config/main.xml`
  - `package/contents/ui/lib/ConfigPage.qml`
- Avoid new runtime dependencies if possible.

## Testing

Run the automated checks that cover your change:

```bash
node --test tests/*.test.js
python3 -m unittest discover -s tests -p '*_test.py' -v
bash tests/qml_compile.sh   # loads every QML file with the installed Qt / KDE modules
shellcheck --severity=warning install update uninstall build package/translate/build package/translate/merge tests/qml_compile.sh
./build                     # also fails when the translation catalogs are stale
```

CI (`.github/workflows/ci.yml`) runs the same checks on every push and pull request to `master`;
the QML compile and `./build` run in an Arch Linux container with current Plasma 6 packages.
Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which builds the `.plasmoid` and
publishes a GitHub release with the matching `## vX.Y.Z` section of `Changelog.md` as notes.

Please also include manual test steps in your PR. At minimum:

- Open the widget settings.
- Toggle your change and verify it applies after clicking Apply/OK.
- If the change touches Google login, verify a login flow.

## Pull requests

Include:

- What changed and why.
- Screenshots for UI changes.
- Plasma version tested on.
