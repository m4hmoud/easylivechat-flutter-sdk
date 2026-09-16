import 'package:flutter/material.dart';

import '../theme.dart';

/// The outline a message is drawn in, in one place.
///
/// A card from the team has to read as a message from the team — the same
/// surface, corners and tail as the bubble beside it, only with more in it. Two
/// copies of these numbers would drift the first time either was retuned, so
/// the bubble, the typing row and the card all take them from here.
abstract final class ElcBubbleShape {
  static const double _radius = 16;
  static const double _tail = 4;

  /// Rounded everywhere but the bottom corner on the sender's own side.
  ///
  /// Logical corners: the tail hugs the sender's side in RTL as well —
  /// bottomStart/bottomEnd flip with the layout, physical left/right did not.
  static BorderRadiusDirectional radius({required bool fromCustomer}) =>
      BorderRadiusDirectional.only(
        topStart: const Radius.circular(_radius),
        topEnd: const Radius.circular(_radius),
        bottomStart: Radius.circular(fromCustomer ? _radius : _tail),
        bottomEnd: Radius.circular(fromCustomer ? _tail : _radius),
      );

  /// The team's messages sit on the neutral surface, lifted off the thread by
  /// a hairline. (The visitor's own sit on the accent and need none.)
  static Border teamBorder(EasyLiveChatTheme theme) =>
      Border.all(color: theme.text.withValues(alpha: 0.08));
}
