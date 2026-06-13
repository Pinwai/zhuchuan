import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bracelet_design.dart';

class DesignStorage {
  static const _latestDesignKey = 'latest_design_json';
  static const _projectDesignsKey = 'project_designs_json';
  static const _legacySavedDesignsKey = 'saved_designs_json';

  Future<BraceletDesign?> loadLatest() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_latestDesignKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return BraceletDesign.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<BraceletDesign>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectDesignsKey) ??
        prefs.getString(_legacySavedDesignsKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((value) => BraceletDesign.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLatest(BraceletDesign design) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_latestDesignKey, jsonEncode(design.toJson()));
  }

  Future<void> saveProject(BraceletDesign design) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadProjects();
    final next = [
      design,
      ...existing.where((saved) => saved.id != design.id),
    ].take(20).map((saved) => saved.toJson()).toList();
    await prefs.setString(_projectDesignsKey, jsonEncode(next));
    await saveLatest(design);
  }

  Future<void> deleteProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadProjects();
    final next = existing
        .where((project) => project.id != id)
        .map((project) => project.toJson())
        .toList();
    await prefs.setString(_projectDesignsKey, jsonEncode(next));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_latestDesignKey);
    await prefs.remove(_projectDesignsKey);
    await prefs.remove(_legacySavedDesignsKey);
  }
}
