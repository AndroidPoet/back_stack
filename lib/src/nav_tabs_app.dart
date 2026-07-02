import 'dart:async';
import 'dart:convert';

import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_entries.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_links.dart';
import 'package:back_stack/src/nav_multi.dart';
import 'package:back_stack/src/nav_restoration.dart';
import 'package:back_stack/src/nav_router.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The one-widget **tabbed** app: bottom navigation with a persistent back
/// stack per tab — the most common app shape there is, wired internally.
///
/// ```dart
/// void main() => runApp(
///   BackStackTabsApp<AppKey>(
///     tabs: [
///       NavStack<AppKey>.of(const Feed()),
///       NavStack<AppKey>.of(const Search()),
///       NavStack<AppKey>.of(const Profile()),
///     ],
///     entries: entries,
///     destinations: const [
///       NavigationDestination(icon: Icon(Icons.home), label: 'Feed'),
///       NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
///       NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
///     ],
///   ),
/// );
/// ```
///
/// That's a complete tabbed app: each tab keeps its own history alive across
/// switches, system back pops the active tab first (then falls back to the
/// first tab, then leaves the app), and re-tapping the active tab pops it to
/// its root. Handled for you: the `MaterialApp.router` + delegate + parser
/// wiring, the `NavigationBar` and its selection state, tab ownership and
/// disposal.
///
/// Add capabilities the same way as [BackStackApp] — one parameter each:
/// [links] (deep links + web URLs + automatic full restoration; the target tab
/// is inferred from the decoded stack's root destination), [onLinkAsync],
/// [initialLink]/[linkStream], [restoreWith]. Want your own bar or scaffold?
/// Pass [shell] instead of [destinations] and drive it from the host
/// (`host.index` / `host.select`).
class BackStackTabsApp<K extends NavKey> extends StatefulWidget {
  /// Creates a tabbed app over [tabs] (one [NavStack] per tab, owned and
  /// disposed by this widget). Provide exactly one of [builder]/[entries],
  /// and at most one of [destinations]/[shell].
  const BackStackTabsApp({
    required this.tabs,
    this.builder,
    this.entries,
    this.destinations,
    this.shell,
    this.links,
    this.onLink,
    this.onLinkAsync,
    this.toLink,
    this.onLinkFallback,
    this.linkStream,
    this.initialLink,
    this.restoreWith,
    this.restoreStack = true,
    this.initialIndex = 0,
    this.popToRootOnReselect = true,
    this.lazy = false,
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
         destinations == null || shell == null,
         'Provide destinations (the built-in NavigationBar) or shell (your '
         'own chrome), not both.',
       ),
       assert(
         links == null ||
             (onLink == null && toLink == null && onLinkFallback == null),
         'links already defines both directions — do not also pass '
         'onLink/toLink/onLinkFallback.',
       );

  /// One back stack per tab. This widget takes ownership: they're wrapped in a
  /// [MultiNavStack] and disposed with it.
  final List<NavStack<K>> tabs;

  /// Maps a destination to its screen. Alternative to [entries].
  final NavWidgetBuilder<K>? builder;

  /// The destination registry — the modular alternative to [builder]. See
  /// [NavDisplay.entries].
  final NavEntries<K>? entries;

  /// The easy chrome: the built-in `Scaffold` + `NavigationBar` uses these,
  /// with selection and re-tap-to-pop-to-root wired for you. Must match
  /// [tabs] in length. For custom chrome, pass [shell] instead.
  final List<NavigationDestination>? destinations;

  /// Full-control chrome around the tabbed display. Receives the
  /// [MultiNavStack] host — drive your bar from `host.index` / `host.select`,
  /// and reach it anywhere below via `MultiBackStack.of`.
  final Widget Function(
    BuildContext context,
    MultiNavStack<K> host,
    Widget child,
  )?
  shell;

  /// The URL table — deep links, web URLs and automatic restoration from one
  /// declarative source. The tab a link lands in is inferred from the decoded
  /// stack's **root** destination (matched against each tab's initial root);
  /// no match keeps the current tab. See [NavLinks].
  final NavLinks<K>? links;

  /// Hand-written link mapping (full control, including the tab): a `Uri` →
  /// which tab plus the stack to show in it. Alternative to [links].
  final MultiNavLocation<K> Function(Uri uri)? onLink;

  /// Optional **async** link resolution — awaited first for every incoming
  /// link; return the location to show, or `null` to fall through to the sync
  /// mapping. Race-safe: a newer link supersedes an in-flight one.
  final Future<MultiNavLocation<K>?> Function(Uri uri)? onLinkAsync;

  /// The active tab + its stack → the URL to show. Alternative to [links].
  /// Omit to keep the URL at `/`.
  final Uri Function(int tab, List<K> stack)? toLink;

  /// The location shown when a link can't be parsed.
  final MultiNavLocation<K>? onLinkFallback;

  /// Runtime deep links from a native plugin. See [BackStackApp.linkStream].
  final Stream<Uri>? linkStream;

  /// The cold-start link, if any. See [BackStackApp.initialLink].
  final Future<Uri?>? initialLink;

  /// Custom per-key serialization for full restoration (every tab's stack plus
  /// the active tab). Usually unnecessary — with [links] set, restoration
  /// derives from the table automatically. See [BackStackApp.restoreWith].
  final NavKeyCodec<K>? restoreWith;

  /// Whether full restoration is active when [links]/[restoreWith] provide a
  /// way to serialize keys. Defaults to true.
  final bool restoreStack;

  /// The tab selected at launch.
  final int initialIndex;

  /// Whether re-selecting the active tab pops it to its root (the familiar
  /// bottom-nav gesture). Applies to the built-in bar; a custom [shell] passes
  /// its own choice to `host.select`.
  final bool popToRootOnReselect;

  /// Build tabs lazily (first build on first visit). See [MultiNavDisplay.lazy].
  final bool lazy;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Attached to every tab's [Navigator]. See [MultiNavDisplay.observers].
  final List<NavigatorObserver> observers;

  /// Applied to every tab's screens. See [NavEntryDecorator].
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

  /// Forwarded to `MaterialApp.builder` (named to avoid clashing with the
  /// destination [builder]).
  final TransitionBuilder? appBuilder;

  /// Forwarded to `MaterialApp.scrollBehavior`.
  final ScrollBehavior? scrollBehavior;

  /// Forwarded to `MaterialApp.shortcuts`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Forwarded to `MaterialApp.actions`.
  final Map<Type, Action<Intent>>? actions;

  /// Forwarded to `MaterialApp.debugShowCheckedModeBanner`.
  final bool debugShowCheckedModeBanner;

  /// Forwarded to `MaterialApp.restorationScopeId` — set by default so
  /// restoration works without extra wiring.
  final String? restorationScopeId;

  @override
  State<BackStackTabsApp<K>> createState() => _BackStackTabsAppState<K>();
}

class _BackStackTabsAppState<K extends NavKey>
    extends State<BackStackTabsApp<K>> {
  /// Each tab's keys before anything touched them — the tab-inference roots
  /// for [BackStackTabsApp.links] and the restorer's "untouched" baseline.
  /// Captured eagerly in [initState] (and again on a tabs swap), before the
  /// Router can apply anything.
  late List<List<K>> _initialTabKeys;

  late MultiNavStack<K> _host = MultiNavStack<K>(
    widget.tabs,
    initialIndex: widget.initialIndex,
  );

  late MultiNavStackRouterDelegate<K> _delegate = _buildDelegate();

  StreamSubscription<Uri>? _linkSub;

  MultiNavStackRouterDelegate<K> _buildDelegate() {
    return MultiNavStackRouterDelegate<K>(
      host: _host,
      codec: MultiNavStackCodec<K>.of(
        encode: (tab, stack) => widget.links != null
            ? widget.links!.encode(stack)
            : (widget.toLink ?? (_, _) => Uri(path: '/'))(tab, stack),
        decode: _decodeLocation,
        fallback: widget.onLinkFallback,
      ),
      builder: widget.entries == null ? _buildScreen : null,
      entries: widget.entries,
      asyncDecode: _resolveLink,
      shell: _shell,
      pageBuilder: widget.pageBuilder,
      observers: widget.observers,
      decorators: widget.decorators,
      lazy: widget.lazy,
    );
  }

  Widget _buildScreen(BuildContext context, K key) =>
      (widget.builder ?? widget.entries!.call)(context, key);

  Future<MultiNavLocation<K>?> _resolveLink(Uri uri) async =>
      widget.onLinkAsync?.call(uri);

  MultiNavLocation<K> _decodeLocation(Uri uri) {
    final links = widget.links;
    if (links != null) {
      final stack = links.decode(uri);
      return MultiNavLocation(_tabFor(stack), stack);
    }
    final onLink = widget.onLink;
    if (onLink != null) return onLink(uri);
    // No mapping: links keep the app exactly where it is.
    return MultiNavLocation(_host.index, const []);
  }

  /// Which tab a decoded stack belongs in: the tab whose initial root equals
  /// the stack's root (by value first, then by runtime type). No match keeps
  /// the current tab, so a partial table still behaves sensibly.
  int _tabFor(List<K> stack) {
    if (stack.isEmpty) return _host.index;
    final root = stack.first;
    for (var i = 0; i < _initialTabKeys.length; i++) {
      if (_initialTabKeys[i].first == root) return i;
    }
    for (var i = 0; i < _initialTabKeys.length; i++) {
      if (_initialTabKeys[i].first.runtimeType == root.runtimeType) return i;
    }
    return _host.index;
  }

  Widget _shell(BuildContext context, MultiNavStack<K> host, Widget child) {
    var content = child;
    final restore = _restoreCodec();
    if (restore != null) {
      content = _TabsRestorationScope<K>(
        restorationId: 'back_stack_tabs',
        host: host,
        initialIndex: widget.initialIndex,
        initialTabKeys: _initialTabKeys,
        encodeKey: restore.encode,
        decodeKey: restore.decode,
        child: content,
      );
    }
    final shell = widget.shell;
    if (shell != null) return shell(context, host, content);
    final destinations = widget.destinations;
    if (destinations == null) return content;
    assert(
      destinations.length == host.length,
      'destinations (${destinations.length}) must match tabs (${host.length}).',
    );
    return Scaffold(
      body: content,
      bottomNavigationBar: ListenableBuilder(
        listenable: host,
        builder: (context, _) => NavigationBar(
          selectedIndex: host.index,
          onDestinationSelected: (i) => host.select(
            i,
            popToRootOnReselect: widget.popToRootOnReselect,
          ),
          destinations: destinations,
        ),
      ),
    );
  }

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
    _initialTabKeys = [for (final tab in widget.tabs) tab.keys];
    _linkSub = widget.linkStream?.listen(_handleStreamLink);
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
  void didUpdateWidget(BackStackTabsApp<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.linkStream != oldWidget.linkStream) {
      unawaited(_linkSub?.cancel());
      _linkSub = widget.linkStream?.listen(_handleStreamLink);
    }
    // The delegate reads the link mapping and screen builder live. Swapped
    // tab stacks or a swapped registry are a different app: rebuild both, and
    // dispose the old pair once the Router has let go of the old delegate.
    final tabsSwapped =
        widget.tabs.length != oldWidget.tabs.length ||
        [
          for (var i = 0; i < widget.tabs.length; i++)
            identical(widget.tabs[i], oldWidget.tabs[i]),
        ].contains(false);
    if (tabsSwapped || !identical(widget.entries, oldWidget.entries)) {
      final oldDelegate = _delegate;
      final oldHost = _host;
      if (tabsSwapped) {
        _host = MultiNavStack<K>(widget.tabs, initialIndex: widget.initialIndex);
        _initialTabKeys = [for (final tab in widget.tabs) tab.keys];
      }
      _delegate = _buildDelegate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldDelegate.dispose();
        if (tabsSwapped) oldHost.dispose();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
    _delegate.dispose();
    _host.dispose(); // owns the tab stacks
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

/// Persists a [MultiNavStack] (every tab's stack + the active tab) across
/// process death. Internal to [BackStackTabsApp].
class _TabsRestorationScope<K extends NavKey> extends StatefulWidget {
  const _TabsRestorationScope({
    required this.restorationId,
    required this.host,
    required this.initialIndex,
    required this.initialTabKeys,
    required this.encodeKey,
    required this.decodeKey,
    required this.child,
    super.key,
  });

  final String restorationId;
  final MultiNavStack<K> host;
  final int initialIndex;
  final List<List<K>> initialTabKeys;
  final String? Function(K key) encodeKey;
  final K? Function(String data) decodeKey;
  final Widget child;

  @override
  State<_TabsRestorationScope<K>> createState() =>
      _TabsRestorationScopeState<K>();
}

class _TabsRestorationScopeState<K extends NavKey>
    extends State<_TabsRestorationScope<K>>
    with RestorationMixin {
  final RestorableString _encoded = RestorableString('');

  @override
  String? get restorationId => widget.restorationId;

  @override
  void initState() {
    super.initState();
    widget.host.addListener(_persist);
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_encoded, 'tabs');
    final data = _encoded.value;
    if (data.isEmpty) {
      _persist();
      return;
    }
    // restoreState fires during the first build; mutating the host here would
    // mark the Router (an ancestor) dirty mid-build. Apply after the frame —
    // which also lets a cold-start deep link land first and win below.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyRestored(data);
      });
    } else {
      _applyRestored(data);
    }
  }

  void _applyRestored(String data) {
    // A cold-start deep link (or anything else) may have navigated already —
    // that intent wins over the snapshot.
    final host = widget.host;
    final untouched =
        host.index == widget.initialIndex &&
        [
          for (var t = 0; t < host.length; t++)
            listEquals(host.tabs[t].keys, widget.initialTabKeys[t]),
        ].every((same) => same);
    if (!untouched) {
      _persist();
      return;
    }
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final tabs = (decoded['tabs'] as List).cast<dynamic>();
      // Only restore when the saved shape matches this run's bottom bar.
      if (tabs.length != host.length) {
        _persist();
        return;
      }
      for (var t = 0; t < tabs.length; t++) {
        final keys = [
          for (final item in tabs[t] as List)
            if (widget.decodeKey(item as String) case final K key) key,
        ];
        if (keys.isNotEmpty) host.tabs[t].replaceAll(keys);
      }
      final i = decoded['i'] as int;
      if (i >= 0 && i < host.length) {
        host.select(i, popToRootOnReselect: false);
      }
    } on Object catch (_) {
      // Corrupt or incompatible snapshot — keep the initial host, overwrite it.
      _persist();
    }
  }

  void _persist() {
    _encoded.value = jsonEncode({
      'i': widget.host.index,
      'tabs': [
        for (final tab in widget.host.tabs)
          [
            for (final k in tab.keys)
              if (widget.encodeKey(k) case final String data) data,
          ],
      ],
    });
  }

  @override
  void didUpdateWidget(_TabsRestorationScope<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.host, oldWidget.host)) {
      oldWidget.host.removeListener(_persist);
      widget.host.addListener(_persist);
    }
  }

  @override
  void dispose() {
    widget.host.removeListener(_persist);
    _encoded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
