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

  testWidgets('fits compact phone viewport without page scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 667);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    });

    await tester.pumpWidget(const ZhuchuanApp());
    await _pumpLoaded(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('瀏覽模式'), findsNothing);
    expect(find.byTooltip('專案操作'), findsOneWidget);
    expect(find.byTooltip('儲存專案'), findsOneWidget);
    expect(find.byTooltip('匯出圖片'), findsOneWidget);
    expect(find.text('素材'), findsOneWidget);
    expect(find.text('專案'), findsOneWidget);
    expect(find.text('白水晶'), findsOneWidget);
    expect(find.text('加入'), findsOneWidget);
    expect(find.text('清除選取'), findsOneWidget);
    expect(find.text('快速選珠'), findsNothing);

    await tester.tap(find.text('專案'));
    await tester.pumpAndSettle();

    expect(find.text('尚未建立專案'), findsOneWidget);
    expect(find.text('編好手鍊後點右上角儲存'), findsOneWidget);
  });
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
