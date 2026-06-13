import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/data/catalog_repository.dart';
import 'src/models/bracelet_capacity.dart';
import 'src/models/bracelet_design.dart';
import 'src/models/catalog_data.dart';
import 'src/models/catalog_item.dart';
import 'src/services/design_storage.dart';
import 'src/services/export_service.dart';
import 'src/services/fullscreen_service.dart';
import 'src/ui/bead_painter.dart';
import 'src/ui/bracelet_canvas.dart';
import 'src/ui/drag_payload.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ZhuchuanApp());
}

class ZhuchuanApp extends StatelessWidget {
  const ZhuchuanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '珠串',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamilyFallback: const [
          'PingFang TC',
          'Noto Sans CJK TC',
          'Microsoft JhengHei',
          'Heiti TC',
          'Arial Unicode MS',
          'sans-serif',
        ],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF52A8FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF17181B),
        ),
        scaffoldBackgroundColor: Colors.black,
        cardTheme: CardThemeData(
          color: const Color(0xFF1D1F23),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: Color(0xFF343840)),
          selectedColor: Color(0xFF2B4058),
          backgroundColor: Color(0xFF1B1D20),
          labelStyle: TextStyle(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1F2125),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const BraceletHomePage(),
    );
  }
}

class BraceletHomePage extends StatefulWidget {
  const BraceletHomePage({super.key});

  @override
  State<BraceletHomePage> createState() => _BraceletHomePageState();
}

class _SlotEditResult {
  const _SlotEditResult({
    required this.slots,
    required this.selectedSlotIndex,
  });

  final List<BraceletSlot> slots;
  final int? selectedSlotIndex;
}

enum _ProjectMenuAction {
  newProject,
  saveAsCopy,
  clearAll,
}

class _BraceletHomePageState extends State<BraceletHomePage>
    with WidgetsBindingObserver {
  final _catalogRepository = const CatalogRepository();
  final _storage = DesignStorage();
  final _exportService = ExportService();
  final _fullscreenService = const FullscreenService();
  final _exportKey = GlobalKey();
  final _shareButtonKey = GlobalKey();

  CatalogData? _catalog;
  BraceletDesign _design = BraceletDesign.empty();
  List<BraceletDesign> _projects = const [];
  int? _selectedSlotIndex;
  bool _showProjectPanel = false;
  CatalogCategory _activeCategory = CatalogCategory.bead;
  String? _activeColorTag;
  final List<String> _selectedCatalogItemIds = [];
  bool _loading = true;
  bool _exporting = false;
  Timer? _autosaveDebounce;

  static const _defaultAddSizeMm = 6;
  static const _supportedSizes = [6, 8, 10, 12];
  static const _materialCategories = [
    CatalogCategory.bead,
    CatalogCategory.spacer,
  ];
  static const _colorFilterOrder = [
    '白',
    '透明',
    '粉',
    '紅',
    '橘',
    '黃',
    '金',
    '綠',
    '藍',
    '紫',
    '茶',
    '棕',
    '灰',
    '黑',
    '銀',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveLatestImmediately();
    _autosaveDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_saveLatestImmediately());
      case AppLifecycleState.resumed:
        break;
    }
  }

  Future<void> _bootstrap() async {
    final catalog = await _catalogRepository.load();
    final saved = await _storage.loadLatest();
    final projects = await _loadSanitizedProjects(catalog);
    final initial = _sanitizeDesign(
      saved ?? BraceletDesign.empty(),
      catalog,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _catalog = catalog;
      _design = initial;
      _projects = projects;
      _loading = false;
    });
  }

  Future<List<BraceletDesign>> _loadSanitizedProjects(
    CatalogData catalog,
  ) async {
    final projects = await _storage.loadProjects();
    return projects
        .map((design) => _sanitizeDesign(design, catalog))
        .toList(growable: false);
  }

  BraceletDesign _sanitizeDesign(
    BraceletDesign design,
    CatalogData catalog,
  ) {
    final slots = design.slots.where((slot) {
      final item = catalog.itemById[slot.itemId];
      return item != null &&
          item.category != CatalogCategory.pendant &&
          !slot.isPendant;
    }).toList();
    return design.copyWith(
      selectedSizeMm: _defaultAddSizeMm,
      slots: slots,
      updatedAt: design.updatedAt,
    );
  }

  bool get _hasUnsavedProjectChanges {
    if (_design.id == BraceletDesign.latestId) {
      return true;
    }
    return !_projects.any(_isSameProjectContent);
  }

  bool get _hasUnsavedDraftContent {
    if (!_hasUnsavedProjectChanges) {
      return false;
    }
    final empty = BraceletDesign.empty();
    return _design.id != BraceletDesign.latestId ||
        _design.title != empty.title ||
        _design.wristCm != empty.wristCm ||
        _design.selectedSizeMm != empty.selectedSizeMm ||
        _design.slots.isNotEmpty;
  }

  bool _isSameProjectContent(BraceletDesign project) {
    if (project.id != _design.id ||
        project.title != _design.title ||
        project.wristCm != _design.wristCm ||
        project.selectedSizeMm != _design.selectedSizeMm ||
        project.slots.length != _design.slots.length) {
      return false;
    }
    for (var i = 0; i < project.slots.length; i += 1) {
      final a = project.slots[i];
      final b = _design.slots[i];
      if (a.itemId != b.itemId ||
          a.sizeMm != b.sizeMm ||
          a.isPendant != b.isPendant) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _catalog == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final catalog = _catalog!;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        title: const Text('水晶'),
        actions: [
          _ProjectSaveStatusBadge(unsaved: _hasUnsavedProjectChanges),
          IconButton(
            tooltip: '儲存專案',
            onPressed: _saveProject,
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            key: _shareButtonKey,
            tooltip: '匯出圖片',
            onPressed: _exporting ? null : _exportImage,
            icon: const Icon(Icons.ios_share_outlined),
          ),
          if (_fullscreenService.isSupported)
            IconButton(
              tooltip: '全螢幕',
              onPressed: _toggleFullscreen,
              icon: const Icon(Icons.fullscreen),
            ),
          PopupMenuButton<_ProjectMenuAction>(
            tooltip: '專案操作',
            icon: const Icon(Icons.more_horiz),
            onSelected: _handleProjectMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ProjectMenuAction.newProject,
                child: _ProjectMenuItem(
                  icon: Icons.note_add_outlined,
                  label: '新增專案',
                ),
              ),
              const PopupMenuItem(
                value: _ProjectMenuAction.saveAsCopy,
                child: _ProjectMenuItem(
                  icon: Icons.file_copy_outlined,
                  label: '另存專案',
                ),
              ),
              PopupMenuItem(
                value: _ProjectMenuAction.clearAll,
                enabled: _design.slots.isNotEmpty,
                child: const _ProjectMenuItem(
                  icon: Icons.delete_sweep_outlined,
                  label: '全部清除',
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBraceletPage(catalog),
      ),
    );
  }

  Widget _buildBraceletPage(CatalogData catalog) {
    final previewSizeMm = _previewSizeMm;
    final fitText = _fitText(catalog, selectedSizeMm: previewSizeMm);
    final hasSelectedSlot = _hasSelectedSlot;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final compactLayout = shortestSide < 700;
        final shortViewport = constraints.maxHeight < 720;
        final compactViewport = constraints.maxWidth < 430;
        final tinyViewport = constraints.maxWidth < 370;
        final horizontalPadding = tinyViewport
            ? 10.0
            : compactViewport
                ? 14.0
                : 20.0;
        final bottomPadding = compactLayout
            ? (shortViewport ? 12.0 : 16.0)
            : (shortViewport ? 10.0 : 16.0);
        final gap = shortViewport ? 8.0 : 10.0;
        final panelMinHeight = compactLayout
            ? (shortViewport ? 276.0 : 332.0)
            : (shortViewport ? 220.0 : 270.0);
        final panelMaxHeight = compactLayout
            ? (shortViewport ? 330.0 : 390.0)
            : (shortViewport ? 300.0 : 360.0);
        final desiredPanelHeight =
            (constraints.maxHeight *
                    (compactLayout
                        ? (shortViewport ? 0.43 : 0.45)
                        : (shortViewport ? 0.34 : 0.37)))
                .clamp(panelMinHeight, panelMaxHeight)
                .toDouble();
        final reservedPreviewHeight = shortViewport ? 245.0 : 315.0;
        final availablePanelHeight = math.max(
          220.0,
          constraints.maxHeight -
              8 -
              bottomPadding -
              gap -
              reservedPreviewHeight,
        );
        final panelHeight = math
            .min(desiredPanelHeight, availablePanelHeight)
            .clamp(220.0, panelMaxHeight)
            .toDouble();
        final wideLayout =
            constraints.maxWidth >= 900 && constraints.maxHeight >= 650;
        final contentMaxWidth = wideLayout
            ? math.min(1120.0, constraints.maxWidth - horizontalPadding * 2)
            : constraints.maxWidth >= 700
                ? 560.0
                : 520.0;
        final widePanelWidth = math.min(460.0, contentMaxWidth * 0.42);

        Widget previewCard() {
          return _ExportCard(
            design: _design,
            readOnly: false,
            onEditTitle: _showTitleEditor,
            onEditWrist: _showWristEditor,
            canvas: BraceletCanvas(
              design: _design,
              catalogById: catalog.itemById,
              targetSlotCount: BraceletDesign.estimateSlotCount(
                _design.wristCm,
                _defaultAddSizeMm,
              ),
              selectedSlotIndex: _selectedSlotIndex,
              onSelectSlot: (index) => setState(
                () => _selectedSlotIndex = index,
              ),
              onRemoveSlot: _removeSlotAtIndex,
              onMoveSlot: _moveSlotToRingPosition,
              onDropPayload: _dropPayload,
            ),
          );
        }

        Widget catalogPanel() {
          return _InlineCatalogPanel(
            catalog: catalog,
            showProjects: _showProjectPanel,
            projects: _projects,
            activeCategory: _activeCategory,
            activeColorTag: _activeColorTag,
            fitText: fitText,
            selectionLabel: _selectionLabel(catalog),
            supportedSizes: _supportedSizes,
            previewSizeMm: previewSizeMm,
            sizeControlsEnabled: hasSelectedSlot,
            selectedSizeMm: _defaultAddSizeMm,
            selectedItemIds: _selectedCatalogItemIds,
            readOnly: false,
            onModeChanged: _setPanelMode,
            onCategoryChanged: _setActiveCategory,
            onColorChanged: _setActiveColorTag,
            onSizeChanged: (size) => _setPreviewSize(size, catalog),
            onToggleItem: _toggleCatalogItem,
            onClearSelected: _clearCatalogSelection,
            onAddSelected: () => _addSelectedCatalogItems(catalog),
            onProjectTap: (project) => unawaited(_loadProject(project, catalog)),
            onProjectDelete: _deleteProject,
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                8,
                horizontalPadding,
                bottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: wideLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: previewCard()),
                            SizedBox(width: gap),
                            SizedBox(
                              width: widePanelWidth,
                              child: catalogPanel(),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: previewCard()),
                            SizedBox(height: gap),
                            SizedBox(
                              height: panelHeight,
                              child: catalogPanel(),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            Positioned(
              left: -10000,
              top: 0,
              child: SizedBox(
                width: 900,
                height: 1200,
                child: RepaintBoundary(
                  key: _exportKey,
                  child: _ExportPoster(
                    key: const ValueKey('export-poster'),
                    design: _design,
                    catalog: catalog,
                    fitText: fitText,
                    materialSummary: _exportMaterialSummary(catalog),
                    sizeSummary: _exportSizeSummary(),
                    generatedAt: DateTime.now(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _hasSelectedSlot {
    final selected = _selectedSlotIndex;
    return selected != null && selected >= 0 && selected < _design.slots.length;
  }

  int get _previewSizeMm {
    final selected = _selectedSlotIndex;
    if (selected != null && selected >= 0 && selected < _design.slots.length) {
      return _design.slots[selected].sizeMm;
    }
    return _defaultAddSizeMm;
  }

  void _setPreviewSize(int sizeMm, CatalogData catalog) {
    final selected = _selectedSlotIndex;
    if (selected == null || selected < 0 || selected >= _design.slots.length) {
      return;
    }

    final slots = [..._design.slots];
    final nextSlot = slots[selected].copyWith(sizeMm: sizeMm);
    slots[selected] = nextSlot;
    if (!nextSlot.isPendant &&
        !_fitsCapacity(
          catalog,
          slots,
          selectedSizeMm: sizeMm,
        )) {
      _showSnack(
        _capacityBlockedMessage(
          catalog,
          slots,
          selectedSizeMm: sizeMm,
        ),
      );
      return;
    }

    setState(() {
      _design = _design.copyWith(slots: slots);
    });
    _scheduleAutosave();
  }

  void _updateWristFromInput(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) {
      _showSnack('請輸入有效手圍');
      return;
    }
    final safe = parsed.clamp(12.0, 30.0).toDouble();
    setState(() {
      _design = _design.copyWith(wristCm: safe);
    });
    _scheduleAutosave();
  }

  Future<void> _showWristEditor() async {
    var draftValue = _formatCm(_design.wristCm);
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('手圍'),
          content: TextFormField(
            initialValue: draftValue,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '手圍 (cm)',
              prefixIcon: Icon(Icons.straighten),
            ),
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draftValue),
              child: const Text('套用'),
            ),
          ],
        );
      },
    );
    if (value == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateWristFromInput(value);
    });
  }

  Future<void> _showTitleEditor() async {
    var draftValue = _design.title;
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('手鍊標題'),
          content: TextFormField(
            initialValue: draftValue,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '標題',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
            onChanged: (value) => draftValue = value,
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(draftValue),
              child: const Text('套用'),
            ),
          ],
        );
      },
    );
    final title = value?.trim();
    if (title == null || title.isEmpty) {
      return;
    }
    setState(() {
      _design = _design.copyWith(title: title);
    });
    _scheduleAutosave();
  }

  void _setPanelMode(bool showProjects) {
    setState(() {
      _showProjectPanel = showProjects;
      if (showProjects) {
        _selectedCatalogItemIds.clear();
      }
    });
  }

  void _setActiveCategory(CatalogCategory category) {
    setState(() {
      _activeCategory = category;
      _activeColorTag = null;
    });
  }

  void _setActiveColorTag(String? colorTag) {
    setState(() => _activeColorTag = colorTag);
  }

  void _toggleCatalogItem(CatalogItem item) {
    setState(() {
      if (_selectedCatalogItemIds.contains(item.id)) {
        _selectedCatalogItemIds.remove(item.id);
      } else {
        _selectedCatalogItemIds.add(item.id);
      }
    });
  }

  void _clearCatalogSelection() {
    if (_selectedCatalogItemIds.isEmpty) {
      return;
    }
    setState(_selectedCatalogItemIds.clear);
  }

  Future<void> _clearAllSlots() async {
    if (_design.slots.isEmpty) {
      return;
    }
    final confirmed = await _confirmDestructiveAction(
      title: '全部清除',
      message: '確定清除目前手鍊上的所有珠子？這個動作無法復原。',
      confirmLabel: '清除',
    );
    if (!confirmed) {
      return;
    }
    setState(() {
      _design = _design.copyWith(slots: const []);
      _selectedSlotIndex = null;
      _selectedCatalogItemIds.clear();
    });
    _scheduleAutosave();
    _showSnack('已全部清除');
  }

  void _handleProjectMenuAction(_ProjectMenuAction action) {
    switch (action) {
      case _ProjectMenuAction.newProject:
        unawaited(_newProject());
      case _ProjectMenuAction.saveAsCopy:
        unawaited(_saveProjectAsCopy());
      case _ProjectMenuAction.clearAll:
        unawaited(_clearAllSlots());
    }
  }

  void _addSelectedCatalogItems(CatalogData catalog) {
    final selectedItems = _selectedCatalogItemIds
        .map((id) => catalog.itemById[id])
        .whereType<CatalogItem>()
        .toList();
    if (selectedItems.isEmpty) {
      return;
    }

    final edit = _buildAddSelectedEdit(selectedItems);
    final needsCapacity = selectedItems.any(
      (item) => item.category != CatalogCategory.pendant,
    );
    if (needsCapacity && !_fitsCapacity(catalog, edit.slots)) {
      _showSnack(_capacityBlockedMessage(catalog, edit.slots));
      return;
    }

    setState(() {
      _design = _design.copyWith(slots: edit.slots);
      _selectedSlotIndex = edit.selectedSlotIndex;
      _selectedCatalogItemIds.clear();
    });
    _scheduleAutosave();
  }

  _SlotEditResult _buildAddSelectedEdit(List<CatalogItem> selectedItems) {
    final slots = [..._design.slots];
    var selectedSlotIndex = _selectedSlotIndex;
    var replacedSelectedSlot = false;
    final selected = _selectedSlotIndex;

    for (final item in selectedItems) {
      final nextSlot = BraceletSlot(
        itemId: item.id,
        sizeMm: _defaultAddSizeMm,
        isPendant: item.category == CatalogCategory.pendant,
      );

      if (!replacedSelectedSlot &&
          selected != null &&
          selected >= 0 &&
          selected < slots.length) {
        slots[selected] = nextSlot;
        selectedSlotIndex = selected;
        replacedSelectedSlot = true;
        continue;
      }

      if (nextSlot.isPendant) {
        slots.add(nextSlot);
        selectedSlotIndex = slots.length - 1;
      } else {
        final insertAt = _insertIndexBeforePendants(slots);
        slots.insert(insertAt, nextSlot);
        selectedSlotIndex = insertAt;
      }
    }

    return _SlotEditResult(
      slots: slots,
      selectedSlotIndex: selectedSlotIndex,
    );
  }

  _SlotEditResult _buildDropEdit(BraceletSlot nextSlot, int? ringSlot) {
    final slots = [..._design.slots];
    var selectedSlotIndex = _selectedSlotIndex;
    if (nextSlot.isPendant) {
      slots.add(nextSlot);
      selectedSlotIndex = slots.length - 1;
    } else {
      final originalIndex = ringSlot == null
          ? null
          : _originalIndexForRegularPosition(slots, ringSlot);
      if (originalIndex == null) {
        final insertAt = _insertIndexForRegularPosition(slots, ringSlot);
        slots.insert(insertAt, nextSlot);
        selectedSlotIndex = insertAt;
      } else {
        slots[originalIndex] = nextSlot;
        selectedSlotIndex = originalIndex;
      }
    }
    return _SlotEditResult(
      slots: slots,
      selectedSlotIndex: selectedSlotIndex,
    );
  }

  bool _fitsCapacity(
    CatalogData catalog,
    List<BraceletSlot> slots, {
    int? selectedSizeMm,
  }) {
    return !_capacityForSlots(
      catalog,
      slots,
      selectedSizeMm: selectedSizeMm,
    ).isOverfilled;
  }

  BraceletCapacity _capacityForSlots(
    CatalogData catalog,
    List<BraceletSlot> slots, {
    int? selectedSizeMm,
  }) {
    return BraceletCapacity.fromSlots(
      wristCm: _design.wristCm,
      selectedSizeMm: selectedSizeMm ?? _design.selectedSizeMm,
      slots: slots,
      itemById: catalog.itemById,
    );
  }

  String _capacityBlockedMessage(
    CatalogData catalog,
    List<BraceletSlot> slots, {
    int? selectedSizeMm,
  }) {
    final activeSizeMm = selectedSizeMm ?? _design.selectedSizeMm;
    final capacity = _capacityForSlots(
      catalog,
      slots,
      selectedSizeMm: activeSizeMm,
    );
    return '空間不足，請先移除約 ${capacity.overCount} 顆 ${activeSizeMm}mm 空間';
  }

  void _dropPayload(CatalogDragPayload payload, int? ringSlot) {
    final item = payload.item;
    final size = payload.sizeMm;
    final nextSlot = BraceletSlot(
      itemId: item.id,
      sizeMm: size,
      isPendant: item.category == CatalogCategory.pendant,
    );

    final edit = _buildDropEdit(nextSlot, ringSlot);
    if (!nextSlot.isPendant && !_fitsCapacity(_catalog!, edit.slots)) {
      _showSnack(_capacityBlockedMessage(_catalog!, edit.slots));
      return;
    }

    setState(() {
      _design = _design.copyWith(slots: edit.slots);
      _selectedSlotIndex = edit.selectedSlotIndex;
    });
    _scheduleAutosave();
  }

  void _removeSlotAtIndex(int index) {
    if (index < 0 || index >= _design.slots.length) {
      return;
    }
    setState(() {
      final slots = [..._design.slots]..removeAt(index);
      _selectedSlotIndex = slots.isEmpty
          ? null
          : (index < slots.length ? index : slots.length - 1);
      _design = _design.copyWith(slots: slots);
    });
    _scheduleAutosave();
  }

  void _moveSlotToRingPosition(int fromIndex, int targetRingPosition) {
    if (fromIndex < 0 || fromIndex >= _design.slots.length) {
      return;
    }
    final movingSlot = _design.slots[fromIndex];
    if (movingSlot.isPendant) {
      return;
    }

    final sourceRingPosition =
        _regularPositionForOriginalIndex(_design.slots, fromIndex);
    if (sourceRingPosition == null) {
      return;
    }

    var insertRingPosition = targetRingPosition;
    if (sourceRingPosition < targetRingPosition) {
      insertRingPosition -= 1;
    }
    if (insertRingPosition == sourceRingPosition) {
      return;
    }

    final slots = [..._design.slots]..removeAt(fromIndex);
    final insertAt = _insertIndexForRegularPosition(slots, insertRingPosition);
    setState(() {
      slots.insert(insertAt, movingSlot);
      _design = _design.copyWith(slots: slots);
      _selectedSlotIndex = insertAt;
    });
    _scheduleAutosave();
  }

  Future<void> _loadProject(BraceletDesign project, CatalogData catalog) async {
    if (_hasUnsavedDraftContent) {
      final confirmed = await _confirmDestructiveAction(
        title: '切換專案',
        message: '目前內容尚未儲存為專案。切換後會覆蓋本機草稿，確定載入「${project.title}」？',
        confirmLabel: '載入',
      );
      if (!confirmed) {
        return;
      }
    }

    setState(() {
      _design = _sanitizeDesign(project, catalog);
      _selectedSlotIndex = null;
      _selectedCatalogItemIds.clear();
      _showProjectPanel = false;
    });
    _scheduleAutosave();
  }

  Future<void> _newProject() async {
    if (_hasUnsavedDraftContent) {
      final confirmed = await _confirmDestructiveAction(
        title: '新增專案',
        message: '目前內容尚未儲存為專案。新增空白專案後會覆蓋本機草稿，確定新增？',
        confirmLabel: '新增',
      );
      if (!confirmed) {
        return;
      }
    }

    final next = BraceletDesign.empty();
    _autosaveDebounce?.cancel();
    await _storage.saveLatest(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _design = next;
      _selectedSlotIndex = null;
      _selectedCatalogItemIds.clear();
      _showProjectPanel = false;
    });
    _showSnack('已新增空白專案');
  }

  Future<bool> _confirmDestructiveAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteProject(BraceletDesign project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除專案'),
        content: Text('確定刪除「${project.title}」？這個動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final catalog = _catalog;
    if (catalog == null) {
      return;
    }

    await _storage.deleteProject(project.id);
    final projects = await _loadSanitizedProjects(catalog);
    if (!mounted) {
      return;
    }

    setState(() {
      _projects = projects;
      _selectedCatalogItemIds.clear();
      if (_design.id == project.id) {
        _design = _design.copyWith(id: BraceletDesign.latestId);
      }
    });
    _scheduleAutosave();
    _showSnack('已刪除專案');
  }

  int _insertIndexBeforePendants(List<BraceletSlot> slots) {
    final index = slots.indexWhere((slot) => slot.isPendant);
    return index == -1 ? slots.length : index;
  }

  int _insertIndexForRegularPosition(List<BraceletSlot> slots, int? position) {
    if (position == null) {
      return _insertIndexBeforePendants(slots);
    }
    var regularPosition = 0;
    for (var i = 0; i < slots.length; i += 1) {
      if (slots[i].isPendant) {
        return i;
      }
      if (regularPosition >= position) {
        return i;
      }
      regularPosition += 1;
    }
    return slots.length;
  }

  int? _originalIndexForRegularPosition(
    List<BraceletSlot> slots,
    int position,
  ) {
    var regularPosition = 0;
    for (var i = 0; i < slots.length; i += 1) {
      if (slots[i].isPendant) {
        continue;
      }
      if (regularPosition == position) {
        return i;
      }
      regularPosition += 1;
    }
    return null;
  }

  int? _regularPositionForOriginalIndex(List<BraceletSlot> slots, int index) {
    if (index < 0 || index >= slots.length || slots[index].isPendant) {
      return null;
    }
    var regularPosition = 0;
    for (var i = 0; i < slots.length; i += 1) {
      if (slots[i].isPendant) {
        continue;
      }
      if (i == index) {
        return regularPosition;
      }
      regularPosition += 1;
    }
    return null;
  }

  String _selectionLabel(CatalogData catalog) {
    final selected = _selectedSlotIndex;
    if (selected == null || selected < 0 || selected >= _design.slots.length) {
      return '未選取珠子 · 預設加入 ${_defaultAddSizeMm}mm · ${_activeColorTag ?? '全部顏色'}';
    }

    final slot = _design.slots[selected];
    final item = catalog.itemById[slot.itemId];
    final colorText = item == null || item.colorTags.isEmpty
        ? '未標色'
        : item.colorTags.take(2).join('/');
    return '已選 ${item?.name ?? '素材'} · ${slot.sizeMm}mm · $colorText';
  }

  String _exportMaterialSummary(CatalogData catalog) {
    final counts = <String, int>{};
    for (final slot in _design.slots.where((slot) => !slot.isPendant)) {
      final item = catalog.itemById[slot.itemId];
      if (item == null) {
        continue;
      }
      counts[item.name] = (counts[item.name] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return '尚未加入珠子';
    }
    return counts.entries
        .take(6)
        .map((entry) => '${entry.key} x${entry.value}')
        .join(' · ');
  }

  String _exportSizeSummary() {
    final counts = <int, int>{};
    for (final slot in _design.slots.where((slot) => !slot.isPendant)) {
      counts[slot.sizeMm] = (counts[slot.sizeMm] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return '尚未加入珠子';
    }
    final sizes = counts.keys.toList()..sort();
    return sizes.map((size) => '${size}mm x${counts[size]}').join(' · ');
  }

  String _fitText(CatalogData catalog, {required int selectedSizeMm}) {
    final capacity = _capacityForSlots(
      catalog,
      _design.slots,
      selectedSizeMm: selectedSizeMm,
    );
    if (capacity.isOverfilled) {
      return '已超出約 ${capacity.overCount} 顆 ${selectedSizeMm}mm 空間 · 請移除或調整手圍';
    }
    if (capacity.isFull) {
      return '已剛好塞滿';
    }
    return '剩餘約 ${capacity.remainingMm} mm · 可再塞 ${capacity.remainingCount} 顆 ${selectedSizeMm}mm';
  }

  Future<void> _saveProject() => _saveProjectWithMode(asCopy: false);

  Future<void> _saveProjectAsCopy() => _saveProjectWithMode(asCopy: true);

  Future<void> _saveProjectWithMode({required bool asCopy}) async {
    final catalog = _catalog;
    if (catalog == null) {
      return;
    }
    final shouldCreateProject = asCopy || _design.id == BraceletDesign.latestId;
    final copiedFromSavedProject =
        asCopy && _design.id != BraceletDesign.latestId;
    final designToSave = shouldCreateProject
        ? _design.copyWith(
            id: _newProjectId(),
            title: copiedFromSavedProject
                ? _copyProjectTitle(_design.title)
                : _design.title,
          )
        : _design.copyWith();
    await _storage.saveProject(designToSave);
    final projects = await _loadSanitizedProjects(catalog);
    if (!mounted) {
      return;
    }
    setState(() {
      _design = designToSave;
      _projects = projects;
      _showProjectPanel = true;
      _selectedCatalogItemIds.clear();
    });
    _showSnack(asCopy ? '已另存專案' : '已儲存專案');
  }

  String _newProjectId() {
    return 'project-${DateTime.now().microsecondsSinceEpoch}';
  }

  String _copyProjectTitle(String title) {
    final trimmed = title.trim();
    final base = trimmed.isEmpty ? '未命名專案' : trimmed;
    return '$base 副本';
  }

  void _scheduleAutosave() {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_saveLatestImmediately());
    });
  }

  Future<void> _saveLatestImmediately() async {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = null;
    await _storage.saveLatest(_design);
  }

  Future<void> _exportImage() async {
    setState(() => _exporting = true);
    try {
      final result = await _exportService.capturePng(
        _exportKey,
        fileName: 'zhuchuan-${DateTime.now().millisecondsSinceEpoch}',
        pixelRatio: 2,
      );
      await _exportService.sharePng(
        result,
        sharePositionOrigin: _sharePositionOrigin(),
      );
      if (!mounted) {
        return;
      }
      _showSnack('已儲存影像');
    } catch (error) {
      _showSnack('匯出失敗：$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _toggleFullscreen() async {
    try {
      await _fullscreenService.toggle();
    } catch (_) {
      _showSnack('此瀏覽器不支援全螢幕');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Rect _sharePositionOrigin() {
    final buttonContext = _shareButtonKey.currentContext;
    final buttonBox = buttonContext?.findRenderObject() as RenderBox?;
    if (buttonBox != null && buttonBox.hasSize && !buttonBox.size.isEmpty) {
      return buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    }

    final media = MediaQuery.maybeOf(context);
    final screenSize = media?.size ?? const Size(430, 932);
    final safeTop = media?.padding.top ?? 0;
    return Rect.fromLTWH(
      screenSize.width - 64,
      safeTop + 8,
      44,
      44,
    );
  }

  String _formatCm(double value) {
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _ProjectSaveStatusBadge extends StatelessWidget {
  const _ProjectSaveStatusBadge({
    required this.unsaved,
  });

  final bool unsaved;

  @override
  Widget build(BuildContext context) {
    final color = unsaved
        ? const Color(0xFF52A8FF)
        : Colors.white.withValues(alpha: 0.58);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: unsaved ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              unsaved ? '未儲存' : '已儲存',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineCatalogPanel extends StatelessWidget {
  const _InlineCatalogPanel({
    required this.catalog,
    required this.showProjects,
    required this.projects,
    required this.activeCategory,
    required this.activeColorTag,
    required this.fitText,
    required this.selectionLabel,
    required this.supportedSizes,
    required this.previewSizeMm,
    required this.sizeControlsEnabled,
    required this.selectedSizeMm,
    required this.selectedItemIds,
    required this.readOnly,
    required this.onModeChanged,
    required this.onCategoryChanged,
    required this.onColorChanged,
    required this.onSizeChanged,
    required this.onToggleItem,
    required this.onClearSelected,
    required this.onAddSelected,
    required this.onProjectTap,
    required this.onProjectDelete,
  });

  final CatalogData catalog;
  final bool showProjects;
  final List<BraceletDesign> projects;
  final CatalogCategory activeCategory;
  final String? activeColorTag;
  final String fitText;
  final String selectionLabel;
  final List<int> supportedSizes;
  final int previewSizeMm;
  final bool sizeControlsEnabled;
  final int selectedSizeMm;
  final List<String> selectedItemIds;
  final bool readOnly;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<CatalogCategory> onCategoryChanged;
  final ValueChanged<String?> onColorChanged;
  final ValueChanged<int> onSizeChanged;
  final ValueChanged<CatalogItem> onToggleItem;
  final VoidCallback onClearSelected;
  final VoidCallback onAddSelected;
  final ValueChanged<BraceletDesign> onProjectTap;
  final ValueChanged<BraceletDesign> onProjectDelete;

  @override
  Widget build(BuildContext context) {
    final categoryItems = catalog.items
        .where((item) => item.category == activeCategory)
        .toList(growable: false);
    final colorTags = _colorTagsFor(categoryItems);
    final items = categoryItems
        .where(
          (item) =>
              activeColorTag == null || item.colorTags.contains(activeColorTag),
        )
        .toList(growable: false);
    final selectedCount = selectedItemIds.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111215),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: false, label: Text('素材')),
                      ButtonSegment(value: true, label: Text('專案')),
                    ],
                    selected: {showProjects},
                    onSelectionChanged: (value) => onModeChanged(value.first),
                  ),
                ),
                if (!readOnly) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: !showProjects && selectedCount > 0
                        ? onClearSelected
                        : null,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: Colors.white.withValues(alpha: 0.82),
                    ),
                    child: const Text('清除選取'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: !showProjects && selectedCount > 0
                        ? onAddSelected
                        : null,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Text(selectedCount > 0 ? '加入 $selectedCount' : '加入'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            _PanelStatusStrip(
              fitText: fitText,
              selectionLabel: selectionLabel,
              supportedSizes: supportedSizes,
              previewSizeMm: previewSizeMm,
              sizeControlsEnabled: !readOnly && sizeControlsEnabled,
              onSizeChanged: onSizeChanged,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: showProjects
                    ? _ProjectList(
                        key: const ValueKey('inline-projects'),
                        projects: projects,
                        itemById: catalog.itemById,
                        onTap: onProjectTap,
                        onDelete: readOnly ? null : onProjectDelete,
                      )
                    : Column(
                        key: const ValueKey('inline-catalog'),
                        children: [
                          _InlineChoiceRow<CatalogCategory>(
                            values: _BraceletHomePageState._materialCategories,
                            selectedValue: activeCategory,
                            labelBuilder: (category) => category.label,
                            onChanged: onCategoryChanged,
                          ),
                          const SizedBox(height: 6),
                          _InlineChoiceRow<String?>(
                            values: [null, ...colorTags],
                            selectedValue: activeColorTag,
                            labelBuilder: (tag) => tag ?? '全部',
                            onChanged: onColorChanged,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final compactGrid = constraints.maxWidth < 430;
                                final tightGrid = constraints.maxWidth < 370;
                                return GridView.builder(
                                  key: PageStorageKey(
                                    'inline-catalog-${activeCategory.id}',
                                  ),
                                  padding: EdgeInsets.zero,
                                  itemCount: items.length,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 5,
                                    mainAxisSpacing: 4,
                                    crossAxisSpacing: 4,
                                    childAspectRatio: tightGrid
                                        ? 0.96
                                        : compactGrid
                                            ? 0.9
                                            : 0.7,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    return _CatalogGridTile(
                                      item: item,
                                      selectedSizeMm: selectedSizeMm,
                                      selected: !readOnly &&
                                          selectedItemIds.contains(item.id),
                                      readOnly: readOnly,
                                      onTap: readOnly
                                          ? null
                                          : () => onToggleItem(item),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _colorTagsFor(List<CatalogItem> items) {
    final available = items.expand((item) => item.colorTags).toSet();
    final ordered = _BraceletHomePageState._colorFilterOrder
        .where(available.contains)
        .toList(growable: false);
    if (ordered.isNotEmpty) {
      return ordered;
    }
    return available.toList()..sort();
  }
}

class _PanelStatusStrip extends StatelessWidget {
  const _PanelStatusStrip({
    required this.fitText,
    required this.selectionLabel,
    required this.supportedSizes,
    required this.previewSizeMm,
    required this.sizeControlsEnabled,
    required this.onSizeChanged,
  });

  final String fitText;
  final String selectionLabel;
  final List<int> supportedSizes;
  final int previewSizeMm;
  final bool sizeControlsEnabled;
  final ValueChanged<int> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    final fitColor = fitText.startsWith('已超出')
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF52A8FF);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fitText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fitColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 204,
                  child: _InlineChoiceRow<int>(
                    values: supportedSizes,
                    selectedValue: previewSizeMm,
                    labelBuilder: (size) => '${size}mm',
                    onChanged: sizeControlsEnabled ? onSizeChanged : null,
                    height: 28,
                    minItemWidth: 40,
                    horizontalPadding: 5,
                    fontSize: 10,
                    scrollable: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMenuItem extends StatelessWidget {
  const _ProjectMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _InlineChoiceRow<T> extends StatelessWidget {
  const _InlineChoiceRow({
    required this.values,
    required this.selectedValue,
    required this.labelBuilder,
    required this.onChanged,
    this.height = 28,
    this.minItemWidth = 38,
    this.horizontalPadding = 10,
    this.fontSize = 11,
    this.scrollable = true,
  });

  final List<T> values;
  final T selectedValue;
  final String Function(T value) labelBuilder;
  final ValueChanged<T>? onChanged;
  final double height;
  final double minItemWidth;
  final double horizontalPadding;
  final double fontSize;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (!scrollable) {
      return SizedBox(
        height: height,
        child: Row(
          children: [
            for (var index = 0; index < values.length; index += 1) ...[
              if (index > 0) const SizedBox(width: 4),
              Expanded(child: _choice(context, values[index])),
            ],
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          return _choice(context, values[index]);
        },
      ),
    );
  }

  Widget _choice(BuildContext context, T value) {
    final selected = value == selectedValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: minItemWidth),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF31445B) : const Color(0xFF15171B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF65AFFF)
                  : Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Text(
            labelBuilder(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? const Color(0xFFF1F6FF)
                  : Colors.white.withValues(alpha: 0.82),
              fontSize: fontSize,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogGridTile extends StatelessWidget {
  const _CatalogGridTile({
    required this.item,
    required this.selectedSizeMm,
    required this.selected,
    required this.readOnly,
    required this.onTap,
  });

  final CatalogItem item;
  final int selectedSizeMm;
  final bool selected;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = selectedSizeMm;
    final child = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            width: selected ? 2 : 1,
            color: selected
                ? const Color(0xFF52A8FF)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 4),
              child: Column(
                children: [
                  Expanded(
                    child: BeadSwatch(item: item, sizeMm: size),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                right: 3,
                top: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF52A8FF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.check,
                      color: Colors.black,
                      size: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (readOnly) {
      return child;
    }

    return Draggable<CatalogDragPayload>(
      data: CatalogDragPayload(item: item, sizeMm: size),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      rootOverlay: true,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 58,
          height: 58,
          child: BeadSwatch(item: item, sizeMm: size),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList({
    super.key,
    required this.projects,
    required this.itemById,
    required this.onTap,
    required this.onDelete,
  });

  final List<BraceletDesign> projects;
  final Map<String, CatalogItem> itemById;
  final ValueChanged<BraceletDesign> onTap;
  final ValueChanged<BraceletDesign>? onDelete;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return _ProjectEmptyState(readOnly: onDelete == null);
    }

    return ListView.separated(
      key: const PageStorageKey('project-list'),
      padding: EdgeInsets.zero,
      itemCount: projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final project = projects[index];
        final previewItems = project.slots
            .where((slot) => !slot.isPendant)
            .map((slot) => itemById[slot.itemId])
            .whereType<CatalogItem>()
            .take(5)
            .toList();
        return _ProjectTile(
          project: project,
          previewItems: previewItems,
          onTap: () => onTap(project),
          onDelete: onDelete == null ? null : () => onDelete!(project),
        );
      },
    );
  }
}

class _ProjectEmptyState extends StatelessWidget {
  const _ProjectEmptyState({required this.readOnly});

  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 34,
              color: Colors.white.withValues(alpha: 0.34),
            ),
            const SizedBox(height: 10),
            Text(
              readOnly ? '尚未有可瀏覽專案' : '尚未建立專案',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              readOnly ? '可先瀏覽素材清單' : '編好手鍊後點右上角儲存',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.previewItems,
    required this.onTap,
    required this.onDelete,
  });

  final BraceletDesign project;
  final List<CatalogItem> previewItems;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: 42,
                child: previewItems.isEmpty
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.radio_button_unchecked,
                            color: Colors.white.withValues(alpha: 0.36),
                          ),
                        ),
                      )
                    : Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (var i = 0; i < previewItems.length; i += 1)
                            Positioned(
                              left: i * 18,
                              top: 1,
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: BeadSwatch(
                                  item: previewItems[i],
                                  sizeMm: 6,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${project.regularSlotCount} 顆 · 手圍 ${project.wristCm.toStringAsFixed(1)} cm · ${_formatUpdatedAt(project.updatedAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.64),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (onDelete != null)
                IconButton(
                  tooltip: '刪除專案',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.white.withValues(alpha: 0.66),
                  visualDensity: VisualDensity.compact,
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _formatUpdatedAt(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _ExportPoster extends StatelessWidget {
  const _ExportPoster({
    super.key,
    required this.design,
    required this.catalog,
    required this.fitText,
    required this.materialSummary,
    required this.sizeSummary,
    required this.generatedAt,
  });

  final BraceletDesign design;
  final CatalogData catalog;
  final String fitText;
  final String materialSummary;
  final String sizeSummary;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final fitColor = fitText.startsWith('已超出')
        ? const Color(0xFFFF7A7A)
        : const Color(0xFF64B5FF);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF111316),
      ),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF202228),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white24, width: 1.4),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(42, 40, 42, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF64B5FF).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color:
                              const Color(0xFF64B5FF).withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        child: Text(
                          '珠串',
                          style: TextStyle(
                            color: Color(0xFF64B5FF),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(generatedAt),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'CRYSTAL BRACELET DESIGN',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  design.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF1F3F7),
                    fontSize: 60,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF111316),
                          borderRadius: BorderRadius.circular(360),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: IgnorePointer(
                            child: BraceletCanvas(
                              design: design,
                              catalogById: catalog.itemById,
                              targetSlotCount: BraceletDesign.estimateSlotCount(
                                design.wristCm,
                                6,
                              ),
                              onDropPayload: (_, __) {},
                              onSelectSlot: (_) {},
                              onRemoveSlot: (_) {},
                              onMoveSlot: (_, __) {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _ExportInfoTile(
                        label: '手圍',
                        value: '${design.wristCm.toStringAsFixed(1)} cm',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ExportInfoTile(
                        label: '珠數',
                        value: '${design.regularSlotCount} 顆',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ExportInfoTile(
                  label: '尺寸組成',
                  value: sizeSummary,
                  compact: true,
                ),
                const SizedBox(height: 14),
                _ExportInfoTile(
                  label: '剩餘空間',
                  value: fitText,
                  valueColor: fitColor,
                  compact: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 132,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF171A1F),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '素材摘要',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              materialSummary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 23,
                                height: 1.28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      'Designed with 珠串',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString();
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year.$month.$day';
  }
}

class _ExportInfoTile extends StatelessWidget {
  const _ExportInfoTile({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFFF1F3F7),
    this.compact = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171A1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: compact ? 14 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor,
                fontSize: compact ? 21 : 30,
                height: 1.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.design,
    required this.readOnly,
    required this.onEditTitle,
    required this.onEditWrist,
    required this.canvas,
  });

  final BraceletDesign design;
  final bool readOnly;
  final VoidCallback onEditTitle;
  final VoidCallback onEditWrist;
  final Widget canvas;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1D1F23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _EditableLabel(
                    enabled: !readOnly,
                    tooltip: '編輯手鍊標題',
                    onTap: onEditTitle,
                    child: Text(
                      design.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                _EditableLabel(
                  enabled: !readOnly,
                  tooltip: '編輯手圍',
                  onTap: onEditWrist,
                  child: Text(
                    '手圍 ${design.wristCm.toStringAsFixed(1)} cm',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: canvas,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableLabel extends StatelessWidget {
  const _EditableLabel({
    required this.enabled,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: child),
          if (enabled) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: Colors.white.withValues(alpha: 0.48),
            ),
          ],
        ],
      ),
    );
    if (!enabled) {
      return content;
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
