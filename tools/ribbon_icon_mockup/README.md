# Ribbon icon mockup

Builds `docs/ribbon_icons_mockup.html`: every ribbon icon placed in static ribbon mockups (named and compact; Ember, Chalk and unmapped palettes), with the overflow menus, flyouts, an icon atlas and computed audit notes. The output is one self-contained file.

To regenerate it (run from the repo root):

    dart run tools/ribbon_icon_mockup/dump.dart /tmp/icons.json     # evaluates frontend/lib/svg_icons.dart (plain Dart, no Flutter needed)
    python3 tools/ribbon_icon_mockup/build.py /tmp/icons.json frontend/lib/l10n/app_en.arb docs/ribbon_icons_mockup.html

`build.py` uses only the standard library. Any `{key: string}` JSON works as the labels file. Keys it lacks are filled from `app_en.arb` (`--arb` overrides the path). The ribbon layout and flyout lists are a hand transcription of `frontend/lib/widgets/ribbon.dart` (`RIBBONS` / `FLYOUTS` in build.py). Update them when the ribbon changes. The recolouring is a JS port of `frontend/lib/icon_theme.dart` and lives in the HTML template at the end of build.py.
