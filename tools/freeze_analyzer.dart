// tools/freeze_analyzer.dart
//
// Run using:
//    dart tools/freeze_analyzer.dart
//
// This script scans your Flutter project for performance issues that cause UI freezes.

import 'dart:io';

/// ----------------------------------------------
/// CONFIG: FILES TO SCAN
/// ----------------------------------------------
final List<String> includeFolders = ['lib'];

/// ----------------------------------------------
/// PATTERNS THAT CAUSE FREEZES
/// ----------------------------------------------
final List<FreezePattern> patterns = [

  // --------------- UI BUILD ISSUES ---------------
  FreezePattern(
    name: "UI doing heavy work in build()",
    regex: RegExp(r'Widget build\(.*?\{[\s\S]{800,}', multiLine: true),
    severity: Severity.high,
    suggestion: "Split this widget; build() must stay below 200–300 lines.",
  ),

  FreezePattern(
    name: "JSON parsing on UI thread",
    regex: RegExp(r'jsonDecode|jsonEncode'),
    severity: Severity.high,
    suggestion: "Move JSON parsing to compute() or a background isolate.",
  ),

  FreezePattern(
    name: "Network call inside build()",
    regex: RegExp(r'http\.get|http\.post|ApiClient|Dio'),
    severity: Severity.high,
    suggestion: "Never call network APIs in build(). Move to initState() or controller.",
  ),

  FreezePattern(
    name: "Heavy loops",
    regex: RegExp(r'for\s*\(.*\)\s*\{[\s\S]{250,}\}', multiLine: true),
    severity: Severity.high,
    suggestion: "Large loops freeze frames; move to isolate.",
  ),

  FreezePattern(
    name: "Creating controllers inside build()",
    regex: RegExp(r'Controller\(|TextEditingController|AnimationController'),
    severity: Severity.medium,
    suggestion: "Initialize controllers in initState() only.",
  ),

  FreezePattern(
    name: "Nested ListView / Column",
    regex: RegExp(r'Column\([\s\S]{0,200}ListView', multiLine: true),
    severity: Severity.high,
    suggestion: "Place everything inside a single ListView.",
  ),

  FreezePattern(
    name: "GoogleMap inside scrolling widget",
    regex: RegExp(r'GoogleMap'),
    severity: Severity.high,
    suggestion: "GoogleMap must be inside a fixed height + RepaintBoundary.",
  ),

  FreezePattern(
    name: "Image.network (uncached)",
    regex: RegExp(r'Image\.network'),
    severity: Severity.medium,
    suggestion: "Use CachedNetworkImage instead of Image.network.",
  ),

  FreezePattern(
    name: "Too many debug prints",
    regex: RegExp(r'debugPrint|print\('),
    severity: Severity.low,
    suggestion: "REMOVE prints — they freeze emulator during large loops.",
  ),

  FreezePattern(
    name: "Expensive widget in list without RepaintBoundary",
    regex: RegExp(r'ListView|ListView\.builder'),
    severity: Severity.medium,
    suggestion: "Wrap heavy children inside RepaintBoundary.",
  ),
];

/// ----------------------------------------------
/// MODEL
/// ----------------------------------------------
class FreezePattern {
  final String name;
  final RegExp regex;
  final Severity severity;
  final String suggestion;

  FreezePattern({
    required this.name,
    required this.regex,
    required this.severity,
    required this.suggestion,
  });
}

enum Severity { high, medium, low }

/// ----------------------------------------------
/// MAIN EXECUTION
/// ----------------------------------------------
void main() async {
  print("\n🔍 Flutter Freeze Analyzer\n");

  final files = await _collectFiles();
  final issues = <String, List<String>>{};

  for (final file in files) {
    final content = await File(file).readAsString();
    final fileIssues = <String>[];

    for (final pattern in patterns) {
      if (pattern.regex.hasMatch(content)) {
        fileIssues.add(
          "⚠️ ${_severityLabel(pattern.severity)} ${pattern.name}\n"
          "   👉 Fix: ${pattern.suggestion}\n",
        );
      }
    }

    if (fileIssues.isNotEmpty) {
      issues[file] = fileIssues;
    }
  }

  _printReport(issues);
}

/// ----------------------------------------------
/// FIND FILES
/// ----------------------------------------------
Future<List<String>> _collectFiles() async {
  final List<String> files = [];

  for (final folder in includeFolders) {
    final directory = Directory(folder);

    if (!directory.existsSync()) continue;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(".dart")) {
        files.add(entity.path);
      }
    }
  }

  return files;
}

/// ----------------------------------------------
/// PRINT REPORT
/// ----------------------------------------------
void _printReport(Map<String, List<String>> issues) {
  if (issues.isEmpty) {
    print("✔ No freeze risks detected. Your project is clean!\n");
    return;
  }

  print("❗ PERFORMANCE RISKS FOUND:\n");

  issues.forEach((file, problems) {
    print("--------------------------------------------------");
    print("📄 File: $file\n");

    for (final problem in problems) {
      print(problem);
    }
  });

  print("\n--------------------------------------------------");
  print("✔ Scan complete.");
}

/// ----------------------------------------------
/// LABEL
/// ----------------------------------------------
String _severityLabel(Severity s) {
  switch (s) {
    case Severity.high:
      return "[HIGH]";
    case Severity.medium:
      return "[MEDIUM]";
    case Severity.low:
      return "[LOW]";
  }
}

