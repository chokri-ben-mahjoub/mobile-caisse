import 'package:flutter/foundation.dart';

/// Bumped to ask the app shell to jump to the Caisse tab (e.g. after a quote is turned into a sale).
final ValueNotifier<int> cashierRequest = ValueNotifier<int>(0);
