import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import '../database/repository/seforim_repository.dart';
import 'link_processor.dart';

/// מייבא קובצי קישורים מתיקיות ספרים אישיים אל `user_books.db`.
///
/// הקישורים נשמרים לפי כותרות ואינדקסים ולא לפי foreign keys, כדי לאפשר
/// קישור בין ספר אישי לבין ספר מובנה שנמצא ב-DB אחר.
class ImportedLinkProcessor {
  static final _log = Logger('ImportedLinkProcessor');

  final SeforimRepository _repository;

  ImportedLinkProcessor(this._repository);

  /// סורק רקורסיבית תיקייה אישית ומייבא קובצי JSON שנראים כקובצי קישורים.
  Future<LinkDirectoryResult> processCustomFolderLinks({
    required String folderPath,
    void Function(double progress, String message)? onProgress,
  }) async {
    final root = Directory(folderPath);
    if (!await root.exists()) {
      return const LinkDirectoryResult();
    }

    final linkFiles = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final fileName = path.basename(entity.path);
      if (path.extension(entity.path).toLowerCase() != '.json') continue;
      if (fileName.endsWith('_headings.json')) continue;
      linkFiles.add(entity);
    }

    if (linkFiles.isEmpty) {
      return const LinkDirectoryResult();
    }

    var processedFiles = 0;
    var processedLinks = 0;
    var skippedLinks = 0;
    final errors = <String>[];

    final db = await _repository.database.database;
    db.execute('BEGIN TRANSACTION');
    try {
      for (final file in linkFiles) {
        try {
          final result = await _processLinkFile(file, folderPath);
          processedLinks += result.processedLinks;
          skippedLinks += result.skippedLinks;
          if (result.success) {
            processedFiles++;
          }
        } catch (e, stackTrace) {
          _log.warning(
              'Failed to import personal links: ${file.path}', e, stackTrace);
          errors.add('${path.basename(file.path)}: $e');
        }

        final progress =
            linkFiles.isEmpty ? 1.0 : processedFiles / linkFiles.length;
        onProgress?.call(progress,
            'מייבא קישורים אישיים: $processedFiles/${linkFiles.length}');
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }

    return LinkDirectoryResult(
      processedLinks: processedLinks,
      skippedLinks: skippedLinks,
      totalFiles: linkFiles.length,
      errors: errors,
    );
  }

  Future<LinkProcessResult> _processLinkFile(
    File file,
    String folderPath,
  ) async {
    final content = await file.readAsString();
    final jsonData = jsonDecode(content);
    final rawLinks = _extractLinksList(jsonData);
    if (rawLinks == null) {
      return const LinkProcessResult(success: false);
    }

    final sourceTitle = _sourceTitleFromLinkFile(file.path);
    if (sourceTitle.isEmpty) {
      return LinkProcessResult(
        skippedLinks: rawLinks.length,
        totalLinks: rawLinks.length,
        success: false,
      );
    }

    final importedAt = DateTime.now().millisecondsSinceEpoch;
    var processed = 0;
    var skipped = 0;

    final db = await _repository.database.database;
    db.execute('DELETE FROM imported_link WHERE linkFilePath = ?', [file.path]);

    for (final raw in rawLinks) {
      if (raw is! Map<String, dynamic>) {
        skipped++;
        continue;
      }

      final linkData = _parseLinkData(raw);
      if (linkData == null) {
        skipped++;
        continue;
      }

      final targetTitle = _targetTitleFromPath(linkData.path2);
      final sourceLineIndex = linkData.lineIndex1.toInt();
      final targetLineIndex = linkData.lineIndex2.toInt();
      if (targetTitle.isEmpty || sourceLineIndex <= 0 || targetLineIndex <= 0) {
        skipped++;
        continue;
      }

      db.execute('''
        INSERT OR IGNORE INTO imported_link (
          sourceTitle,
          sourceLineIndex,
          targetTitle,
          targetPath,
          targetLineIndex,
          targetHeRef,
          connectionType,
          linkFilePath,
          sourceFolderPath,
          importedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        sourceTitle,
        sourceLineIndex,
        targetTitle,
        linkData.path2,
        targetLineIndex,
        linkData.heRef2,
        linkData.connectionType.trim().isEmpty
            ? 'reference'
            : linkData.connectionType,
        file.path,
        folderPath,
        importedAt,
      ]);
      processed++;
    }

    return LinkProcessResult(
      processedLinks: processed,
      skippedLinks: skipped,
      totalLinks: rawLinks.length,
      success: true,
    );
  }

  List<dynamic>? _extractLinksList(dynamic jsonData) {
    if (jsonData is List<dynamic>) return jsonData;
    if (jsonData is Map<String, dynamic>) {
      final links = jsonData['links'];
      if (links is List<dynamic>) return links;
      final data = jsonData['data'];
      if (data is List<dynamic>) return data;
      if (_looksLikeLinkJson(jsonData)) return [jsonData];
    }
    return null;
  }

  bool _looksLikeLinkJson(Map<String, dynamic> json) {
    return json.containsKey('line_index_1') &&
        json.containsKey('path_2') &&
        json.containsKey('line_index_2');
  }

  LinkData? _parseLinkData(Map<String, dynamic> json) {
    final lineIndex1 = _toDouble(json['line_index_1']);
    final lineIndex2 = _toDouble(json['line_index_2']);
    final path2 = json['path_2']?.toString() ?? '';
    if (lineIndex1 == null || lineIndex2 == null || path2.trim().isEmpty) {
      return null;
    }

    return LinkData(
      heRef2: json['heRef_2']?.toString() ?? '',
      lineIndex1: lineIndex1,
      path2: path2,
      lineIndex2: lineIndex2,
      connectionType: json['Conection Type']?.toString() ?? '',
    );
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _sourceTitleFromLinkFile(String filePath) {
    return path
        .basenameWithoutExtension(path.basename(filePath))
        .replaceAll('_links', '')
        .replaceAll(' links', '')
        .trim();
  }

  String _targetTitleFromPath(String targetPath) {
    final normalized = targetPath.replaceAll('\\', '/');
    return path.posix.basenameWithoutExtension(normalized).trim();
  }
}
