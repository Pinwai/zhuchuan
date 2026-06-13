import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhuchuan_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('saves current draft immediately when app is paused', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    await tester.pumpWidget(const ZhuchuanApp());
    await _pumpLoaded(tester);

    await tester.tap(find.byTooltip('編輯手鍊標題'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '背景保存測試');
    await tester.tap(find.text('套用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(await _latestTitle(), isNot('背景保存測試'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });

    expect(await _latestTitle(), '背景保存測試');
  });
}

Future<String?> _latestTitle() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('latest_design_json');
  if (raw == null) {
    return null;
  }
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded['title'] as String?;
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  for (var i = 0; i < 60; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}
