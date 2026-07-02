import 'dart:async';
import 'dart:convert';

import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_entries.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_links.dart';
import 'package:back_stack/src/nav_restoration.dart';
import 'package:back_stack/src/nav_router.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The one-widget app: hand it your stack and your screens, done.
///
/// ```dart
/// void main() => runApp(
///   BackStackApp<AppKey>(
///     stack: NavStack.of(const Home()),
///     entries: entries,
///   ),
/// );
/// ```
///
/// That's a complete app. Everything else is optional and added by passing one
/// more parameter, with the wiring handled internally:
///
/// - **Deep links + web URLs**: pass [links] (a [NavLinks] table — one entry
///   per destination, both directions declared at once). The address bar, deep
///   links, browser back/forward, and state restoration all derive from it.
///   Prefer full control? Pass [onLink]/[toLink] closures instead.
/// - **State restoration**: with [links] set it's already on — the *entire*
///   typed stack survives process death, not just the URL. Or pass a
///   [restoreWith] codec. Turn off with `restoreStack: false`.
/// - **Async link resolution**: pass [onLinkAsync] to await a lookup before
///   deciding what a link shows ("does this doc exist? may they see it?").
///   Newer links supersede in-flight ones; errors fall back to the sync
///   mapping. Nothing to wire.
/// - **Links from native plugins**: pass [initialLink] (cold start) and
///   [linkStream] (while running) from your plugin (e.g. `app_links`); every
///   `Uri` flows through the same mapping with the same never-crash hardening.
/// - **App chrome**: pass [shell] to wrap persistent UI (a side rail, a debug
///   overlay) around the navigating area, under `MaterialApp`.
///
/// It bundles `MaterialApp.router` + [NavStackRouterDelegate] +
/// [NavStackRouteInformationParser] so you never see a `RouterDelegate`. The
/// stack stays the single source of truth throughout. For a bottom-nav app
/// with per-tab back stacks, use `BackStackTabsApp`.
class BackStackApp<K extends NavKey> extends StatefulWidget {
  /// Creates an app that renders [stack]. Provide exactly one of
  /// [builder]/[entries]; everything else is optional.
  const BackStackApp({
    required this.stack,
    this.builder,
    this.entries,
    this.links,
    this.onLink,
    this.onLinkAsync,
    this.toLink,
    this.onLinkFallback,
    this.linkStream,
    this.initialLink,
    this.restoreWith,
    this.restoreStack = true,
    this.shell,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
    this.title = '',
    this.onGenerateTitle,
    this.color,
    this.theme,
    this.darkTheme,
    this.highContrastTheme,
    this.highContrastDarkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.localeListResolutionCallback,
    this.localeResolutionCallback,
    this.supportedLocales = const [Locale('en', 'US')],
    this.scaffoldMessengerKey,
    this.appBuilder,
    this.scrollBehavior,
    this.shortcuts,
    this.actions,
    this.debugShowCheckedModeBanner = true,
    this.restorationScopeId = 'back_stack',
    super.key,
  }) : assert(
         (builder != null) ^ (entries != null),
         'Provide exactly one of builder / entries.',
       ),
       assert(
         links == null ||
             (onLink == null && toLink == null && onLinkFallback == null),
         'links already defines both directions — do not also pass '
         'onLink/toLink/onLinkFallback.',
       );

  /// The back stack to render — the single source of truth. You own it.
  final NavStack<K> stack;

  /// Maps a destination to its screen — a `switch` over your keys.
  /// Alternative to [entries].
  final NavWidgetBuilder<K>? builder;

  /// The destination registry ([NavEntries]) — the modular alternative to
  /// [builder] that can also carry per-destination presentation
  /// (`entries.on<T>(page: …)` for dialogs/sheets/transitions).
  final NavEntries<K>? entries;

  /// The URL table: deep links, web URLs, shareable links and restoration all
  /// derived from one declarative source. See [NavLinks]. Replaces
  /// [onLink]/[toLink]/[onLinkFallback].
  final NavLinks<K>? links;

  /// A `Uri` → the stack to show — the hand-written alternative to [links].
  /// Return every destination you want on the stack for the URL (this is
  /// where you choose layer-vs-replace). Parse optimistically: a throw or an
  /// empty result falls back to [onLinkFallback]. Omit it (and [links]) and
  /// deep links simply keep the app where it is.
  final List<K> Function(Uri uri)? onLink;

  /// Optional **async** link resolution, awaited before the sync mapping for
  /// every incoming link. Return the stack to show, or `null` to fall through
  /// to [links]/[onLink]. Race-safe: a newer link supersedes an in-flight one.
  final Future<List<K>?> Function(Uri uri)? onLinkAsync;

  /// The stack → the URL to show, for web address-bar sync — the hand-written
  /// alternative to [links]. Omit to keep the URL at `/` (fine on mobile).
  final Uri Function(List<K> stack)? toLink;

  /// The stack shown when a link can't be parsed (i.e. [onLink] threw or was
  /// empty). Defaults to `onLink(Uri(path: '/'))`.
  final List<K>? onLinkFallback;

  /// A stream of deep links arriving **asynchronously from native** while the app
  /// runs (custom-scheme links, Firebase Dynamic Links, warm `app_links` links).
  /// Each `Uri` is routed through the same mapping with the same fallback safety
  /// as a platform link. Bring it from your deep-link plugin (e.g.
  /// `AppLinks().uriLinkStream`); back_stack owns the subscription and cancels it
  /// on dispose.
  ///
  /// Construct the plugin (e.g. `AppLinks()`) **early** — a top-level singleton or
  /// in `main()` — so the cold-start URI isn't lost, or skip that concern
  /// entirely by also passing [initialLink].
  final Stream<Uri>? linkStream;

  /// The one-shot link that **cold-started** the app, if any — hand it
  /// `AppLinks().getInitialLink()`. back_stack awaits it once on startup and, if
  /// non-null, runs it through the same mapping, so the launch deep link lands
  /// even when [linkStream] doesn't replay it. Safe to use alongside
  /// [linkStream]: re-applying the same link is a no-op.
  final Future<Uri?>? initialLink;

  /// Serializes each destination for **full-stack state restoration** (the
  /// whole typed stack survives process death). Usually unnecessary: when
  /// [links] is set, restoration derives from the same table automatically
  /// (destinations not in the table are skipped). Pass this to restore
  /// destinations that have no URL, or when not using [links].
  final NavKeyCodec<K>? restoreWith;

  /// Whether full-stack restoration is active when [links]/[restoreWith]
  /// provide a way to serialize keys. Defaults to true. (Restoration also
  /// needs [restorationScopeId], which is set by default.)
  final bool restoreStack;

  /// Persistent chrome around the navigating area — it lives under
  /// `MaterialApp` (themes, localization available) and receives the stack:
  /// `shell: (context, stack, child) => Row(children: [SideRail(stack), child])`.
  final Widget Function(BuildContext context, NavStack<K> stack, Widget child)?
  shell;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder]. For a
  /// per-destination transition, prefer `entries.on<T>(page: …)`.
  final NavPageBuilder<K>? pageBuilder;

  /// Forwarded to the display's [Navigator] — a `screen_view` analytics seam.
  final List<NavigatorObserver> observers;

  /// Cross-cutting wrappers/cleanup for every screen. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  /// Forwarded to `MaterialApp.title`.
  final String title;

  /// Forwarded to `MaterialApp.onGenerateTitle`.
  final GenerateAppTitle? onGenerateTitle;

  /// Forwarded to `MaterialApp.color`.
  final Color? color;

  /// Forwarded to `MaterialApp.theme`.
  final ThemeData? theme;

  /// Forwarded to `MaterialApp.darkTheme`.
  final ThemeData? darkTheme;

  /// Forwarded to `MaterialApp.highContrastTheme`.
  final ThemeData? highContrastTheme;

  /// Forwarded to `MaterialApp.highContrastDarkTheme`.
  final ThemeData? highContrastDarkTheme;

  /// Forwarded to `MaterialApp.themeMode`.
  final ThemeMode themeMode;

  /// Forwarded to `MaterialApp.locale`.
  final Locale? locale;

  /// Forwarded to `MaterialApp.localizationsDelegates`.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Forwarded to `MaterialApp.localeListResolutionCallback`.
  final LocaleListResolutionCallback? localeListResolutionCallback;

  /// Forwarded to `MaterialApp.localeResolutionCallback`.
  final LocaleResolutionCallback? localeResolutionCallback;

  /// Forwarded to `MaterialApp.supportedLocales`.
  final Iterable<Locale> supportedLocales;

  /// Forwarded to `MaterialApp.scaffoldMessengerKey`.
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  /// Forwarded to `MaterialApp.builder` (named [appBuilder] here because
  /// [builder] is the destination builder). Wraps *everything*, including
  /// `MaterialApp`'s own overlays — for chrome inside the navigating area,
  /// prefer [shell].
  final TransitionBuilder? appBuilder;

  /// Forwarded to `MaterialApp.scrollBehavior`.
  final ScrollBehavior? scrollBehavior;

  /// Forwarded to `MaterialApp.shortcuts`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Forwarded to `MaterialApp.actions`.
  final Map<Type, Action<Intent>>? actions;

  /// Forwarded to `MaterialApp.debugShowCheckedModeBanner`.
  final bool debugShowCheckedModeBanner;

  /// Forwarded to `MaterialApp.restorationScopeId` — set (default `back_stack`)
  /// so restoration works without any extra wiring.
  final String? restorationScopeId;

  @override
  State<BackStackApp<K>> createState() => _BackStackAppState<K>();
}

class _BackStackAppState<K extends NavKey> extends State<BackStackApp<K>> {
  /// The stack's keys before any link or restoration touched it — the default
  /// deep-link mapping ("keep the app where it starts") and the baseline the
  /// restorer uses to tell "untouched" from "a link already landed". Captured
  /// eagerly in [initState] (and again on a stack swap), before the Router can
  /// apply anything.
  late List<K> _initialKeys;

  /// Created once. Its codec/builder read through [widget] on every call, so
  /// hot-reloading or rebuilding with new functions takes effect without
  /// recreating the delegate (which would remount the Navigator and lose all
  /// screen state). Recreated only when [BackStackApp.stack] or
  /// [BackStackApp.entries] is swapped — genuinely a different app.
  late NavStackRouterDelegate<K> _delegate = _buildDelegate();

  StreamSubscription<Uri>? _linkSub;

  NavStackRouterDelegate<K> _buildDelegate() {
    return NavStackRouterDelegate<K>(
      stack: widget.stack,
      codec: NavStackCodec<K>.of(
        encode: (keys) => widget.links != null
            ? widget.links!.encode(keys)
            : (widget.toLink ?? (_) => Uri(path: '/'))(keys),
        decode: (uri) => widget.links != null
            ? widget.links!.decode(uri)
            : (widget.onLink ?? (_) => _initialKeys)(uri),
        fallback: widget.onLinkFallback,
      ),
      builder: widget.entries == null ? _buildScreen : null,
      entries: widget.entries,
      // Always routed through the async path so a BackStackApp rebuilt with a
      // new onLinkAsync picks it up live; with none set it resolves to null
      // and immediately falls through to the sync mapping.
      asyncDecode: _resolveLink,
      shell: _shell,
      pageBuilder: widget.pageBuilder,
      observers: widget.observers,
      decorators: widget.decorators,
    );
  }

  // Stable tear-offs handed to the delegate once; they read the *current*
  // widget so config updates apply without a delegate rebuild.
  Widget _buildScreen(BuildContext context, K key) =>
      (widget.builder ?? widget.entries!.call)(context, key);

  Future<List<K>?> _resolveLink(Uri uri) async =>
      widget.onLinkAsync?.call(uri);

  Widget _shell(BuildContext context, NavStack<K> stack, Widget child) {
    var content = child;
    final restore = _restoreCodec();
    if (restore != null) {
      content = StackRestorationScope<K>(
        restorationId: 'back_stack_stack',
        stack: stack,
        initialKeys: _initialKeys,
        encodeKey: restore.encode,
        decodeKey: restore.decode,
        locationOf: (keys) => _delegate.codec.encode(keys).toString(),
        child: content,
      );
    }
    return widget.shell?.call(context, stack, content) ?? content;
  }

  /// How to serialize one destination for restoration, or null when
  /// restoration is off ([BackStackApp.restoreStack] false, or nothing to
  /// derive it from). [restoreWith] wins; otherwise the [links] table is the
  /// codec (unregistered keys are skipped, not fatal).
  ({String? Function(K key) encode, K? Function(String data) decode})?
  _restoreCodec() {
    if (!widget.restoreStack) return null;
    final custom = widget.restoreWith;
    if (custom != null) {
      return (encode: custom.encode, decode: custom.decode);
    }
    final links = widget.links;
    if (links != null) {
      return (encode: links.encodeKey, decode: links.decodeKey);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initialKeys = widget.stack.keys;
    // Feed runtime links from the app's plugin through the same mapping.
    _linkSub = widget.linkStream?.listen(_handleStreamLink);
    // Apply the cold-start link (if any) once it resolves — through the same
    // mapping. Guarded on `mounted` in case we're disposed before it arrives.
    final initial = widget.initialLink;
    if (initial != null) {
      unawaited(
        initial.then((uri) {
          if (uri != null && mounted) {
            unawaited(_delegate.handleLinkAsync(uri));
          }
        }),
      );
    }
  }

  void _handleStreamLink(Uri uri) => unawaited(_delegate.handleLinkAsync(uri));

  @override
  void didUpdateWidget(BackStackApp<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-subscribe only if the stream instance actually changed.
    if (widget.linkStream != oldWidget.linkStream) {
      unawaited(_linkSub?.cancel());
      _linkSub = widget.linkStream?.listen(_handleStreamLink);
    }
    // The delegate reads onLink/toLink/builder/links live, so most updates need
    // nothing. A swapped stack or registry is a different app: rebuild the
    // delegate (the old one is disposed after the Router lets go of it).
    if (!identical(widget.stack, oldWidget.stack) ||
        !identical(widget.entries, oldWidget.entries)) {
      if (!identical(widget.stack, oldWidget.stack)) {
        _initialKeys = widget.stack.keys;
      }
      final old = _delegate;
      _delegate = _buildDelegate();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    // We created the delegate; the caller owns (and disposes) the stack.
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: _delegate,
      routeInformationParser: const NavStackRouteInformationParser(),
      title: widget.title,
      onGenerateTitle: widget.onGenerateTitle,
      color: widget.color,
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      highContrastTheme: widget.highContrastTheme,
      highContrastDarkTheme: widget.highContrastDarkTheme,
      themeMode: widget.themeMode,
      locale: widget.locale,
      localizationsDelegates: widget.localizationsDelegates,
      localeListResolutionCallback: widget.localeListResolutionCallback,
      localeResolutionCallback: widget.localeResolutionCallback,
      supportedLocales: widget.supportedLocales,
      scaffoldMessengerKey: widget.scaffoldMessengerKey,
      builder: widget.appBuilder,
      scrollBehavior: widget.scrollBehavior,
      shortcuts: widget.shortcuts,
      actions: widget.actions,
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
      restorationScopeId: widget.restorationScopeId,
    );
  }
}

/// Persists a [NavStack] across process death, key by key — the internal
/// engine behind `BackStackApp`'s automatic restoration (it does **not** own
/// the stack, unlike [RestorableBackStack]). Public so custom Router setups
/// can reuse it; most apps never touch it directly.
class StackRestorationScope<K extends NavKey> extends StatefulWidget {
  /// Creates a restoration host around [child] persisting [stack].
  const StackRestorationScope({
    required this.restorationId,
    required this.stack,
    required this.initialKeys,
    required this.encodeKey,
    required this.decodeKey,
    required this.child,
    this.locationOf,
    super.key,
  });

  /// Restoration id within the enclosing restoration scope.
  final String restorationId;

  /// The stack to persist and restore. Not owned.
  final NavStack<K> stack;

  /// The stack's keys before anything (a deep link, user navigation) touched
  /// it — how the restorer tells "fresh launch, safe to restore" from "a link
  /// already landed, don't clobber it".
  final List<K> initialKeys;

  /// One destination → a string, or null to skip it (it won't be restored —
  /// right for transient destinations like dialogs).
  final String? Function(K key) encodeKey;

  /// The inverse of [encodeKey]. Return null to skip an entry (e.g. its format
  /// changed across an app update); throw to discard the whole snapshot.
  final K? Function(String data) decodeKey;

  /// Optional location fingerprint (usually the encoded URL). When the stack
  /// was already changed before restore (a platform link applied first), the
  /// snapshot is still restored **if it points at the same location** — the
  /// snapshot is then just the richer (deeper) version of where the user
  /// already is. A different location means a genuinely new link: keep it.
  final Object? Function(List<K> keys)? locationOf;

  /// The subtree to wrap.
  final Widget child;

  @override
  State<StackRestorationScope<K>> createState() =>
      _StackRestorationScopeState<K>();
}

class _StackRestorationScopeState<K extends NavKey>
    extends State<StackRestorationScope<K>>
    with RestorationMixin {
  final RestorableString _encoded = RestorableString('');

  @override
  String? get restorationId => widget.restorationId;

  @override
  void initState() {
    super.initState();
    widget.stack.addListener(_persist);
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_encoded, 'keys');
    final data = _encoded.value;
    if (data.isEmpty) {
      _persist(); // seed storage with the current stack
      return;
    }
    List<K> keys;
    try {
      keys = [
        for (final item in jsonDecode(data) as List)
          if (widget.decodeKey(item as String) case final K key) key,
      ];
    } on Object catch (_) {
      // Corrupt or incompatible snapshot (e.g. a key's format changed across
      // an app update). Don't crash on cold start: keep the current stack and
      // overwrite the bad data.
      _persist();
      return;
    }
    if (keys.isEmpty) {
      _persist();
      return;
    }
    // restoreState fires during the first build; mutating the stack here would
    // mark the Router (an ancestor) dirty mid-build. Apply after the frame —
    // which also lets a cold-start deep link land first and win below.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyRestored(keys);
      });
    } else {
      _applyRestored(keys);
    }
  }

  void _applyRestored(List<K> keys) {
    final current = widget.stack.keys;
    final untouched = listEquals(current, widget.initialKeys);
    if (!untouched) {
      // Something (usually a cold-start deep link) already navigated. Only
      // restore over it when the snapshot points at the same location — then
      // it's just the deeper history of where the user already is.
      final locate = widget.locationOf;
      bool sameLocation;
      try {
        sameLocation = locate != null && locate(keys) == locate(current);
      } on Object catch (_) {
        sameLocation = false; // a throwing encode can't prove anything
      }
      if (!sameLocation) {
        _persist(); // the new location wins; snapshot follows it from now on
        return;
      }
    }
    widget.stack.replaceAll(keys);
  }

  void _persist() {
    _encoded.value = jsonEncode([
      for (final k in widget.stack.keys)
        if (widget.encodeKey(k) case final String data) data,
    ]);
  }

  @override
  void didUpdateWidget(StackRestorationScope<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.stack, oldWidget.stack)) {
      oldWidget.stack.removeListener(_persist);
      widget.stack.addListener(_persist);
    }
  }

  @override
  void dispose() {
    widget.stack.removeListener(_persist);
    _encoded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
