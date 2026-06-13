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

  testWidgets('launches single page with inline material panel',
      (tester) async {
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

    expect(find.text('水晶'), findsWidgets);
    expect(find.text('素材'), findsOneWidget);
    expect(find.text('專案'), findsOneWidget);
    expect(find.text('未儲存'), findsOneWidget);
    expect(find.text('套裝'), findsNothing);
    expect(find.text('加入'), findsOneWidget);
    expect(find.text('清除選取'), findsOneWidget);
    expect(find.byTooltip('儲存專案'), findsOneWidget);
    expect(find.byTooltip('匯出圖片'), findsOneWidget);
    expect(find.byTooltip('專案操作'), findsOneWidget);
    expect(find.text('珠子'), findsOneWidget);
    expect(find.text('隔片/配飾'), findsOneWidget);
    expect(find.text('吊墜'), findsNothing);
    expect(find.text('白'), findsOneWidget);
    expect(find.text('8mm'), findsOneWidget);
    expect(find.text('未選取珠子 · 預設加入 6mm · 全部顏色'), findsOneWidget);
    expect(find.textContaining('剩餘約'), findsWidgets);
    expect(find.textContaining('估算'), findsNothing);
    expect(find.text('快速選珠'), findsNothing);
    expect(find.text('更多'), findsNothing);
    expect(find.text('類別'), findsNothing);
    expect(find.text('設定'), findsNothing);
    expect(find.text('CRYSTAL BRACELET DESIGN'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('export-poster'))),
      const Size(900, 1200),
    );

    await tester.tap(find.byTooltip('編輯手鍊標題'));
    await tester.pumpAndSettle();

    expect(find.text('手鍊標題'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '森林綠調');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(find.text('森林綠調'), findsWidgets);

    await tester.tap(find.textContaining('手圍').first);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '18');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('手圍 18.0 cm'), findsOneWidget);

    await tester.tap(find.text('12mm'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);
    expect(find.text('未選取珠子 · 預設加入 6mm · 全部顏色'), findsOneWidget);

    await tester.tap(find.text('白水晶').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('粉水晶').first);
    await tester.pumpAndSettle();

    expect(find.text('加入 2'), findsOneWidget);

    await tester.tap(find.text('加入 2'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(find.textContaining('空間不足'), findsNothing);
    expect(find.text('加入 2'), findsNothing);
    expect(find.text('加入'), findsOneWidget);
    expect(find.textContaining('已選'), findsOneWidget);
    await _expectSavedSlotSizes({6});

    await tester.tap(find.text('12mm'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(find.textContaining('已選'), findsOneWidget);
    expect(find.textContaining('12mm'), findsWidgets);
    await _expectSavedSlotSizes({6, 12});

    await tester.tap(find.byTooltip('儲存專案'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(find.text('已儲存專案'), findsOneWidget);
    expect(find.text('已儲存'), findsOneWidget);
    await _expectProject(title: '森林綠調', expectedSizes: {6, 12});
    await _expectProjectCount(1);

    await _tapProjectMenuAction(tester, '另存專案');
    await _flushAutosave(tester);

    expect(find.text('森林綠調 副本'), findsWidgets);
    await _expectProject(title: '森林綠調 副本', expectedSizes: {6, 12});
    await _expectProjectCount(2);

    expect(find.byTooltip('刪除專案'), findsWidgets);
    await tester.tap(find.byTooltip('刪除專案').first);
    await tester.pumpAndSettle();

    expect(find.text('確定刪除「森林綠調 副本」？這個動作無法復原。'), findsOneWidget);

    await tester.tap(find.text('刪除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _flushAutosave(tester);

    expect(find.text('未儲存'), findsOneWidget);
    await _expectProjectCount(1);

    await tester.tap(find.text('森林綠調').last);
    await tester.pumpAndSettle();

    expect(
      find.text('目前內容尚未儲存為專案。切換後會覆蓋本機草稿，確定載入「森林綠調」？'),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('森林綠調 副本'), findsWidgets);
    expect(find.text('未儲存'), findsOneWidget);

    await _tapProjectMenuAction(tester, '全部清除');

    expect(find.text('確定清除目前手鍊上的所有珠子？這個動作無法復原。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _expectSavedSlotSizes({6, 12});

    await _tapProjectMenuAction(tester, '全部清除');

    expect(find.text('確定清除目前手鍊上的所有珠子？這個動作無法復原。'), findsOneWidget);

    await tester.tap(find.text('清除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _flushAutosave(tester);

    await _expectSavedSlotSizes({});

    await _tapProjectMenuAction(tester, '新增專案');

    expect(find.text('目前內容尚未儲存為專案。新增空白專案後會覆蓋本機草稿，確定新增？'), findsOneWidget);

    await tester.tap(find.text('新增'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await _flushAutosave(tester);

    expect(find.text('未儲存'), findsOneWidget);
    await _expectSavedSlotSizes({});

    await tester.tap(find.byTooltip('編輯手鍊標題'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '森林綠調未存');
    await tester.tap(find.text('套用'));
    await tester.pumpAndSettle();
    await _flushAutosave(tester);

    expect(find.text('未儲存'), findsOneWidget);

    expect(find.text('加入 2'), findsNothing);
    expect(find.text('加入'), findsOneWidget);

    expect(find.textContaining('剩餘約'), findsWidgets);
    await tester.tap(find.text('專案'));
    await tester.pumpAndSettle();

    expect(find.text('素材'), findsOneWidget);
    expect(find.text('專案'), findsOneWidget);
    expect(find.text('尚未建立專案'), findsNothing);

    await _disposeApp(tester);
  });
}

Future<void> _expectSavedSlotSizes(Set<int> expectedSizes) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('latest_design_json');
  expect(raw, isNotNull);
  final decoded = jsonDecode(raw!) as Map<String, dynamic>;
  final slots = decoded['slots'] as List<dynamic>;
  final sizes = slots
      .map((slot) => (slot as Map<String, dynamic>)['sizeMm'] as int)
      .toSet();
  expect(sizes, expectedSizes);
}

Future<void> _expectProject({
  required String title,
  required Set<int> expectedSizes,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('project_designs_json');
  expect(raw, isNotNull);
  final decoded = jsonDecode(raw!) as List<dynamic>;
  expect(decoded, isNotEmpty);
  final first = decoded.first as Map<String, dynamic>;
  expect(first['title'], title);
  expect(first['id'], isNot('local-latest'));
  expect(first['id'], startsWith('project-'));
  final slots = first['slots'] as List<dynamic>;
  final sizes = slots
      .map((slot) => (slot as Map<String, dynamic>)['sizeMm'] as int)
      .toSet();
  expect(sizes, expectedSizes);
}

Future<void> _expectProjectCount(int expectedCount) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('project_designs_json');
  expect(raw, isNotNull);
  final decoded = jsonDecode(raw!) as List<dynamic>;
  expect(decoded.length, expectedCount);
}

Future<void> _tapProjectMenuAction(
  WidgetTester tester,
  String label,
) async {
  await tester.tap(find.byTooltip('專案操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _flushAutosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  for (var i = 0; i < 60; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.text('素材'), findsOneWidget);
  expect(find.textContaining('手圍'), findsWidgets);
}
