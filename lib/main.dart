import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';

void main() {
  // Clean /dashboard style URLs on the web instead of /#/dashboard.
  usePathUrlStrategy();
  runApp(const ProviderScope(child: App()));
}
