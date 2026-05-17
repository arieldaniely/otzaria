import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:otzaria/migration/generator/imported_link_processor.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('imported_links_test_');
    database = MyDatabase.withPath(path.join(tempDir.path, 'user_books.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    await tempDir.delete(recursive: true);
  });

  test('מייבא קובץ קישורים אישי תקין ומדלג על רשומות לא תקינות', () async {
    final linksFile = File(path.join(tempDir.path, 'ברכות_links.json'));
    await linksFile.writeAsString('''
[
  {
    "heRef_2": "ספר אישי א",
    "line_index_1": 3,
    "path_2": "ספר אישי.txt",
    "line_index_2": 7,
    "Conection Type": "REFERENCE"
  },
  {
    "heRef_2": "חסר יעד",
    "line_index_1": 4,
    "path_2": "",
    "line_index_2": 8,
    "Conection Type": "REFERENCE"
  }
]
''');

    final result = await ImportedLinkProcessor(repository)
        .processCustomFolderLinks(folderPath: tempDir.path);

    expect(result.processedLinks, 1);
    expect(result.skippedLinks, 1);

    final db = await database.database;
    final rows = db.select('SELECT * FROM imported_link').toMapList();

    expect(rows, hasLength(1));
    expect(rows.first['sourceTitle'], 'ברכות');
    expect(rows.first['sourceLineIndex'], 3);
    expect(rows.first['targetTitle'], 'ספר אישי');
    expect(rows.first['targetLineIndex'], 7);
    expect(rows.first['connectionType'], 'REFERENCE');
  });

  test('הרצה חוזרת של אותו קובץ לא מכפילה קישורים', () async {
    final linksFile = File(path.join(tempDir.path, 'ספר אישי_links.json'));
    await linksFile.writeAsString('''
{
  "links": [
    {
      "heRef_2": "ברכות ב",
      "line_index_1": 1,
      "path_2": "ברכות.txt",
      "line_index_2": 2,
      "Conection Type": "COMMENTARY"
    }
  ]
}
''');

    final processor = ImportedLinkProcessor(repository);
    await processor.processCustomFolderLinks(folderPath: tempDir.path);
    await processor.processCustomFolderLinks(folderPath: tempDir.path);

    final db = await database.database;
    final count = db.select('SELECT COUNT(*) AS c FROM imported_link').first;

    expect(count['c'], 1);
  });
}
