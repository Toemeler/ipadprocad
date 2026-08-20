// M234 — the one door to every user-visible string, and the switch behind it.
//
// The app is written in GERMAN. `lib/l10n/app_de.arb` is the template gen-l10n
// reads its placeholders and plural rules from; `app_en.arb` is the
// translation. That order matters for more than tidiness — the template is
// where a plural form is *declared*, so a message whose German needs
// one/other must say so in the German file or English never gets the choice.
//
// Two ways in, on purpose:
//
//   L.of(context)  — inside a widget. Reads the Localizations scope, so a
//                    subtree can be pinned to another locale (the tests do
//                    exactly that) and Flutter's own rebuild machinery
//                    handles the switch.
//
//   L.current      — everywhere else. AppState raises perhaps a hundred and
//                    seventy toasts from business logic that has no
//                    BuildContext and should never grow one; a global that
//                    tracks the single app-wide locale is the honest model
//                    for an app with exactly one window.
//
// [L.of] falls back to [L.current] when there is no Localizations ancestor.
// That is deliberate and load-bearing: a hundred-odd existing widget tests
// pump a bare `MaterialApp(home: ...)` without our delegate, and a throw there
// would turn a localisation change into a hundred unrelated red tests.
import 'package:flutter/widgets.dart';

import 'gen/app_l10n.dart';
import 'locale_store.dart';

export 'gen/app_l10n.dart' show AppL10n;

/// German. The language the app is written in.
const Locale kDe = Locale('de');

/// English.
const Locale kEn = Locale('en');

/// Every locale the app ships, in menu order. German first because it is the
/// default, not because it sorts first.
const List<Locale> kLocales = <Locale>[kDe, kEn];

/// The app-wide language, and the strings that go with it.
///
/// Named for brevity at the call site, the same way [T] is: `L.of(c).cancel`
/// appears in this codebase several hundred times and `AppLocalizations.of(c)`
/// would have pushed most of those lines over the wrap column.
class L {
  L._();

  /// The current strings. Never null: it is German until something says
  /// otherwise, which is exactly the app's default.
  static AppL10n current = lookupAppL10n(kDe);

  /// Drives `MaterialApp.locale`. Listeners rebuild; nothing restarts.
  static final ValueNotifier<Locale> locale = ValueNotifier<Locale>(kDe);

  /// Where the choice is remembered. Null until [attachStore] runs, which is
  /// why a switch made before then still works — it just is not persisted,
  /// and there is no window in which the user can reach the menu that early.
  static LocaleStore? _store;

  /// The strings for [c]'s locale, or the app-wide ones if [c] is not under a
  /// [Localizations] that knows [AppL10n].
  static AppL10n of(BuildContext c) =>
      Localizations.of<AppL10n>(c, AppL10n) ?? current;

  /// True when [l] is one of the shipped languages.
  static bool supports(Locale l) =>
      kLocales.any((k) => k.languageCode == l.languageCode);

  /// Switches the app's language and remembers it.
  ///
  /// Applies on the next frame — [locale] is a notifier the app listens to, so
  /// the widget tree rebuilds where it must and nothing is torn down. An
  /// unsupported locale is ignored rather than throwing: this is reachable
  /// from a persisted file, and a hand-edited settings file must not be able
  /// to stop the app from starting.
  static void set(Locale l) {
    if (!supports(l) || l.languageCode == locale.value.languageCode) return;
    final next = kLocales.firstWhere((k) => k.languageCode == l.languageCode);
    current = lookupAppL10n(next);
    locale.value = next;
    _store?.save(next);
  }

  /// The other language — what the menu entry offers.
  static Locale get other => locale.value.languageCode == kDe.languageCode
      ? kEn
      : kDe;

  /// The strings of the OTHER language, for labelling the toggle in the
  /// language it switches to ("English" while German is on, "Deutsch" while
  /// English is). A menu entry that named the *current* language would read
  /// as a status line, and users tap it expecting an action.
  static AppL10n get otherStrings => lookupAppL10n(other);

  /// Point the switch at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], i.e. off the launch path — reading it in
  /// `main()` would put a platform channel and a file read in front of the
  /// first frame, which is a launch-time regression this repository measures.
  static void attachStore(LocaleStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) set(saved);
  }

  /// Tests only: back to a clean German app with nothing persisted.
  @visibleForTesting
  static void resetForTest() {
    _store = null;
    current = lookupAppL10n(kDe);
    locale.value = kDe;
  }
}
