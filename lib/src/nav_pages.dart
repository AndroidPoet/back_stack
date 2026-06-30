import 'package:back_stack/src/nav_key.dart';
import 'package:flutter/material.dart';

/// Lets a destination declare **its own** presentation — the composition answer
/// to "I don't want a `switch` in `pageBuilder` just to give one screen a
/// transition." Mix it into a [NavKey] and the destination carries how it
/// animates with it (zenrouter's `RouteTransition`, but the key owns it).
///
/// [NavDisplay] checks for this automatically: any key that is a [NavPage]
/// builds its own [Page]; everything else gets the platform default. An explicit
/// `NavDisplay.pageBuilder` still wins if you provide one.
///
/// ```dart
/// class Toast extends NavKey with NavPage {
///   const Toast(this.message);
///   final String message;
///   @override
///   Page<void> buildPage(BuildContext context, Widget child, LocalKey pageKey) =>
///       TransitionPage<void>.fade(key: pageKey, child: child);
/// }
/// ```
mixin NavPage on NavKey {
  /// Wrap [child] (the screen built for this destination) in the [Page] that
  /// presents it. Use the provided [pageKey] as the page's `key`.
  Page<dynamic> buildPage(BuildContext context, Widget child, LocalKey pageKey);
}

/// A [Page] with a custom transition — return it from `NavDisplay.pageBuilder`
/// to control how a destination animates in.
///
/// Named constructors cover the common cases; use the unnamed one for a fully
/// custom [transitionsBuilder]. (For the platform default, just use Flutter's
/// own `MaterialPage` / `CupertinoPage` — no wrapper needed.)
///
/// ```dart
/// NavDisplay<AppKey>(
///   stack: stack,
///   builder: (context, key) => screenFor(key),
///   pageBuilder: (context, key, pageKey) => switch (key) {
///     Toast() => TransitionPage.fade(key: pageKey, child: screenFor(key)),
///     _       => MaterialPage(key: pageKey, child: screenFor(key)),
///   },
/// )
/// ```
class TransitionPage<T> extends Page<T> {
  /// A page with a fully custom [transitionsBuilder].
  const TransitionPage({
    required this.child,
    this.transitionsBuilder,
    this.duration = const Duration(milliseconds: 300),
    this.reverseDuration,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Cross-fade.
  const TransitionPage.fade({
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.reverseDuration,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  }) : transitionsBuilder = _fade;

  /// Slide up from the bottom edge.
  const TransitionPage.slideUp({
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.reverseDuration,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  }) : transitionsBuilder = _slideUp;

  /// Scale + fade ("zoom").
  const TransitionPage.scale({
    required this.child,
    this.duration = const Duration(milliseconds: 250),
    this.reverseDuration,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  }) : transitionsBuilder = _scale;

  /// No animation at all (instant).
  const TransitionPage.none({
    required this.child,
    this.opaque = true,
    this.barrierDismissible = false,
    this.barrierColor,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  }) : transitionsBuilder = null,
       duration = Duration.zero,
       reverseDuration = Duration.zero;

  /// The screen.
  final Widget child;

  /// How the route animates. Null means no transition.
  final RouteTransitionsBuilder? transitionsBuilder;

  /// Forward animation length.
  final Duration duration;

  /// Reverse animation length (defaults to [duration]).
  final Duration? reverseDuration;

  /// See [PageRoute.opaque].
  final bool opaque;

  /// See [ModalRoute.barrierDismissible].
  final bool barrierDismissible;

  /// See [ModalRoute.barrierColor].
  final Color? barrierColor;

  /// See [ModalRoute.maintainState].
  final bool maintainState;

  /// See [PageRoute.fullscreenDialog].
  final bool fullscreenDialog;

  @override
  Route<T> createRoute(BuildContext context) => _TransitionPageRoute<T>(this);

  static Widget _fade(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);

  static Widget _slideUp(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.ease)),
    child: child,
  );

  static Widget _scale(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: 0.92,
        end: 1,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.ease)),
      child: child,
    ),
  );
}

class _TransitionPageRoute<T> extends PageRoute<T> {
  _TransitionPageRoute(TransitionPage<T> page) : super(settings: page);

  TransitionPage<T> get _page => settings as TransitionPage<T>;

  @override
  Duration get transitionDuration => _page.duration;

  @override
  Duration get reverseTransitionDuration =>
      _page.reverseDuration ?? _page.duration;

  @override
  bool get opaque => _page.opaque;

  @override
  bool get barrierDismissible => _page.barrierDismissible;

  @override
  Color? get barrierColor => _page.barrierColor;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final builder = _page.transitionsBuilder;
    if (builder == null) return child;
    return builder(context, animation, secondaryAnimation, child);
  }
}

/// A dialog as a stack entry. Push a [NavKey] rendered as this and the dialog
/// is a real route — back-dismissable and (under the Router) URL-tracked —
/// instead of an imperative `showDialog` floating outside the stack.
///
/// ```dart
/// pageBuilder: (context, key, pageKey) => switch (key) {
///   ConfirmDelete() => DialogPage(key: pageKey, builder: (_) => const ConfirmDialog()),
///   _ => MaterialPage(key: pageKey, child: screenFor(key)),
/// }
/// ```
class DialogPage<T> extends Page<T> {
  /// Creates a dialog page rendering [builder].
  const DialogPage({
    required this.builder,
    this.barrierDismissible = true,
    this.barrierColor = const Color(0x80000000),
    this.barrierLabel,
    this.useSafeArea = true,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Builds the dialog content (typically an `AlertDialog` / `Dialog`).
  final WidgetBuilder builder;

  /// Whether tapping the barrier dismisses (pops) the dialog.
  final bool barrierDismissible;

  /// The scrim color behind the dialog.
  final Color barrierColor;

  /// Semantic label for the barrier.
  final String? barrierLabel;

  /// Wrap the dialog in a `SafeArea`.
  final bool useSafeArea;

  @override
  Route<T> createRoute(BuildContext context) => DialogRoute<T>(
    context: context,
    settings: this,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
  );
}

/// A modal bottom sheet as a stack entry — the sheet equivalent of [DialogPage].
class SheetPage<T> extends Page<T> {
  /// Creates a bottom-sheet page rendering [builder].
  const SheetPage({
    required this.builder,
    this.isScrollControlled = false,
    this.backgroundColor,
    this.elevation,
    this.showDragHandle,
    this.useSafeArea = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// Builds the sheet content.
  final WidgetBuilder builder;

  /// See `ModalBottomSheetRoute.isScrollControlled` — set true for tall sheets.
  final bool isScrollControlled;

  /// Sheet background color.
  final Color? backgroundColor;

  /// Sheet elevation.
  final double? elevation;

  /// Show the grab handle.
  final bool? showDragHandle;

  /// Inset the sheet for system intrusions.
  final bool useSafeArea;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    builder: builder,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor,
    elevation: elevation,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
  );
}
