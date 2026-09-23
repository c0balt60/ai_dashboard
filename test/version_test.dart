import 'dart:io';

import 'package:ai_dashboard/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app_version.dart matches the pubspec version', () {
    final match = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());

    expect(match, isNotNull, reason: 'pubspec.yaml needs "version: X.Y.Z+N"');
    expect(
      '$appVersion+$appBuildNumber',
      '${match!.group(1)}+${match.group(2)}',
      reason: 'Bump with tool/bump_version.dart instead of editing by hand',
    );
  });
}
