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

  /// Material **shared axis (X)** — the incoming screen slides in from the
  /// trailing edge as the outgoing one slides out, both cross-fading. The
  /// standard motion for a peer-to-peer step *forward* in a flow (e.g. an
  /// onboarding pager or a next/step button). Animates the outgoing route too.
  const TransitionPage.sharedAxisHorizontal({
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
  }) : transitionsBuilder = _sharedAxisHorizontal;

  /// Material **shared axis (Y)** — the vertical sibling of
  /// [TransitionPage.sharedAxisHorizontal]: incoming rises in from below,
  /// outgoing rises out above, both cross-fading.
  const TransitionPage.sharedAxisVertical({
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
  }) : transitionsBuilder = _sharedAxisVertical;

  /// Material **shared axis (Z)** — the incoming screen scales up from behind
  /// while the outgoing one scales away, both cross-fading. The motion for a
  /// step *into* a hierarchy (a list → its detail). Animates the outgoing route.
  const TransitionPage.sharedAxisScaled({
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
  }) : transitionsBuilder = _sharedAxisScaled;

  /// Material **fade through** — the outgoing screen fades out, then the incoming
  /// one fades in while scaling up slightly. The motion for switching between
  /// *unrelated* destinations (e.g. bottom-nav tabs) where there's no spatial
  /// relationship to imply.
  const TransitionPage.fadeThrough({
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
  }) : transitionsBuilder = _fadeThrough;

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

  static Widget _sharedAxisHorizontal(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SharedAxisTransition(
    kind: _SharedAxisKind.horizontal,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );

  static Widget _sharedAxisVertical(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SharedAxisTransition(
    kind: _SharedAxisKind.vertical,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );

  static Widget _sharedAxisScaled(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _SharedAxisTransition(
    kind: _SharedAxisKind.scaled,
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );

  static Widget _fadeThrough(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _FadeThroughTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

/// Which Material shared-axis motion [_SharedAxisTransition] renders.
enum _SharedAxisKind { horizontal, vertical, scaled }

/// A dependency-free implementation of Material's shared-axis motion. A single
/// route's transition covers both directions: [animation] drives it entering
/// (and, reversed, leaving via back), while [secondaryAnimation] drives it being
/// covered by — and revealed from under — a route pushed on top. That two-sided
/// coordination is what makes the outgoing and incoming screens move together.
class _SharedAxisTransition extends StatelessWidget {
  const _SharedAxisTransition({
    required this.kind,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final _SharedAxisKind kind;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  // Material spec: 30dp of travel, and the fades are offset so the two screens
  // never both sit at full opacity mid-transition.
  static const double _distance = 30;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, _) {
        final a = animation.value; // 0 → 1 as this route enters
        final s =
            secondaryAnimation.value; // 0 → 1 as it goes to the background
        // Fade in over the back 70% entering; fade out over the front 30% leaving.
        final enter = ((a - 0.3) / 0.7).clamp(0.0, 1.0);
        final exit = (1 - s / 0.3).clamp(0.0, 1.0);
        final opacity = (a < 1 ? enter : exit).clamp(0.0, 1.0);

        Widget moved;
        if (kind == _SharedAxisKind.scaled) {
          // Z axis: scale up from behind entering; scale away when covered.
          final scale = a < 1 ? 0.80 + 0.20 * a : 1.0 + 0.10 * s;
          moved = Transform.scale(scale: scale, child: child);
        } else {
          // X/Y axis: slide from +distance entering; to -distance when covered.
          final d = (1 - a) * _distance - s * _distance;
          final offset = kind == _SharedAxisKind.horizontal
              ? Offset(d, 0)
              : Offset(0, d);
          moved = Transform.translate(offset: offset, child: child);
        }
        return Opacity(opacity: opacity, child: moved);
      },
    );
  }
}

/// Dependency-free Material fade-through: the outgoing screen fades out first,
/// then the incoming one fades in while scaling up slightly — no spatial link,
/// for switching between unrelated destinations.
class _FadeThroughTransition extends StatelessWidget {
  const _FadeThroughTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, _) {
        final a = animation.value;
        final s = secondaryAnimation.value;
        final enter = ((a - 0.3) / 0.7).clamp(0.0, 1.0);
        final exit = (1 - s / 0.3).clamp(0.0, 1.0);
        final opacity = (a < 1 ? enter : exit).clamp(0.0, 1.0);
        final scale = a < 1 ? 0.92 + 0.08 * a : 1.0;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
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
