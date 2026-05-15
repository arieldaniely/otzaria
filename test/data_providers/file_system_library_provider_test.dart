import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/file_system_library_provider.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSystemLibraryProvider bundled talmud bavli', () {
    late Directory tempDir;

    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('otzaria_fs_provider_');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        tempDir.path,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        DatabaseConstants.otzariaFolderName,
      );
      await Settings.setValue<String>(SettingsRepository.keyCustomFolders, '');
      FileSystemLibraryProvider.instance.resetForTesting();
    });

    tearDown(() async {
      FileSystemLibraryProvider.instance.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('loads Brakhot PDF from bundled talmud bavli folder at library root',
        () async {
      final talmudDir = Directory(path.join(
        tempDir.path,
        DatabaseConstants.talmudBavliFolderName,
      ));
      await talmudDir.create(recursive: true);

      final pdfPath = path.join(talmudDir.path, 'ברכות.pdf');
      await File(pdfPath).writeAsBytes(const [37, 80, 68, 70]);

      final provider = FileSystemLibraryProvider.instance;
      await provider.initialize();

      final booksByCategory = await provider.loadBooks({});
      final talmudBooks =
          booksByCategory[DatabaseConstants.talmudBavliFolderName];

      expect(talmudBooks, isNotNull);
      expect(talmudBooks, hasLength(1));
      expect(talmudBooks!.single, isA<PdfBook>());
      expect(talmudBooks.single.title, 'ברכות');

      final keyToPath = await provider.keyToPath;
      final storageKey = BookCompositeKey.create(
        title: 'ברכות',
        categoryId: DatabaseConstants.talmudBavliFolderName.hashCode,
        fileType: 'pdf',
      ).toStorageKey();

      expect(keyToPath[storageKey], pdfPath);
    });

    test('מציג תיקיות מותאמות שלא הוכנסו ל-DB לפי אופן התצוגה', () async {
      final personalDir = Directory(path.join(tempDir.path, 'אישי'));
      final separateDir = Directory(path.join(tempDir.path, 'נפרד'));
      final tanakhDir = Directory(path.join(tempDir.path, 'תנך'));
      await Directory(path.join(personalDir.path, 'מדף'))
          .create(recursive: true);
      await separateDir.create(recursive: true);
      await Directory(path.join(tanakhDir.path, 'ראשונים'))
          .create(recursive: true);

      await File(path.join(personalDir.path, 'מדף', 'ספר אישי.txt'))
          .writeAsString('א');
      await File(path.join(separateDir.path, 'ספר נפרד.txt'))
          .writeAsString('ב');
      await File(path.join(tanakhDir.path, 'ראשונים', 'רשבם.txt'))
          .writeAsString('ג');

      await Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(path: personalDir.path, addedAt: DateTime(2026, 5, 15)),
          CustomFolder(
            path: separateDir.path,
            addedAt: DateTime(2026, 5, 15),
            displayMode: CustomFolderDisplayMode.separate,
          ),
          CustomFolder(
            path: tanakhDir.path,
            addedAt: DateTime(2026, 5, 15),
            displayMode: CustomFolderDisplayMode.libraryRoot,
          ),
        ]),
      );

      final provider = FileSystemLibraryProvider.instance;
      await provider.initialize();

      final library = Library(categories: [
        Category(
          title: 'תנך',
          description: '',
          shortDescription: '',
          order: 1,
          subCategories: [],
          books: [],
          parent: null,
        ),
      ]);
      library.subCategories.single.parent = library;

      await provider.appendCustomFoldersToLibrary(library, {});

      final personalCategory =
          library.subCategories.where((c) => c.title == 'ספרים אישיים').single;
      expect(personalCategory.subCategories.single.title, 'אישי');

      final separateCategory =
          library.subCategories.where((c) => c.title == 'נפרד').single;
      expect(separateCategory.books.single.title, 'ספר נפרד');

      final tanakhCategory =
          library.subCategories.where((c) => c.title == 'תנך').single;
      final rishonimCategory = tanakhCategory.subCategories
          .where((c) => c.title == 'ראשונים')
          .single;
      expect(rishonimCategory.books.single.title, 'רשבם');

      final keyToPath = await provider.keyToPath;
      expect(
        keyToPath.values,
        contains(path.join(tanakhDir.path, 'ראשונים', 'רשבם.txt')),
      );
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
