import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Navigation helpers shared by the pages.
extension SafeNavigation on BuildContext {
  /// Pops the current page with [result] or, when it is the only page on
  /// the stack (opened directly by a deep link), goes to [fallback].
  void popOrGo<T extends Object?>(String fallback, [T? result]) {
    if (canPop()) {
      pop<T>(result);
    } else {
      go(fallback);
    }
  }
}
