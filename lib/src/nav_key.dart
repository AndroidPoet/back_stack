import 'package:flutter/foundation.dart';

/// A single destination in your app.
///
/// This is the whole "type-safe routes" story: you describe each screen as a
/// plain Dart type, and the compiler checks every argument for you. There is no
/// `Object?` payload, no string path to mistype, no codegen.
///
/// ```dart
/// class Home extends NavKey {
///   const Home();
/// }
///
/// class ProductDetail extends NavKey {
///   const ProductDetail(this.id);
///   final int id; // a real, typed argument — checked at compile time
/// }
/// ```
///
/// Push one onto a [NavStack] and you've navigated. That's the model.
@immutable
abstract class NavKey {
  /// Const so destinations can be cheap, value-like objects.
  const NavKey();
}

/// Gives a [NavKey] value equality based on [props].
///
/// **Why it matters:** the stack preserves a screen's `State` only when it can
/// recognize the *same* destination across a change. Two `Product(5)` built at
/// different times (e.g. when a deep link re-decodes the URL into a fresh key)
/// are different objects, so without value equality the screen would needlessly
/// rebuild and lose its scroll/controllers. Mix this in and list the identifying
/// fields, and re-decoding an equal URL reuses the live screen.
///
/// ```dart
/// class Product extends NavKey with EquatableNavKey {
///   const Product(this.id);
///   final int id;
///   @override
///   List<Object?> get props => [id];
/// }
/// ```
///
/// (If you already use `freezed`/`equatable` for your keys, you don't need this
/// — any correct `==`/`hashCode` works.)
mixin EquatableNavKey on NavKey {
  /// The fields that define this destination's identity.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EquatableNavKey &&
          other.runtimeType == runtimeType &&
          listEquals(other.props, props);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(props));
}
