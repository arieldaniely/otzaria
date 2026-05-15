import 'dart:convert';

enum CustomFolderDisplayMode {
  separate,
  personalCategory,
  libraryRoot,
}

extension CustomFolderDisplayModeLabels on CustomFolderDisplayMode {
  String get label {
    switch (this) {
      case CustomFolderDisplayMode.separate:
        return 'הצג בנפרד';
      case CustomFolderDisplayMode.personalCategory:
        return 'ספרים אישיים';
      case CustomFolderDisplayMode.libraryRoot:
        return 'מזג לשורש';
    }
  }
}

/// מודל לתיקייה מותאמת אישית שהמשתמש הוסיף
class CustomFolder {
  /// נתיב התיקייה במערכת הקבצים
  final String path;

  /// האם להכניס את תוכן התיקייה ל-DB
  final bool addToDatabase;

  final CustomFolderDisplayMode displayMode;

  /// תאריך הוספה
  final DateTime addedAt;

  const CustomFolder({
    required this.path,
    this.addToDatabase = false,
    this.displayMode = CustomFolderDisplayMode.personalCategory,
    required this.addedAt,
  });

  /// שם התיקייה (ללא הנתיב המלא)
  String get name => path.split(RegExp(r'[/\\]')).last;

  CustomFolder copyWith({
    String? path,
    bool? addToDatabase,
    CustomFolderDisplayMode? displayMode,
    DateTime? addedAt,
  }) {
    return CustomFolder(
      path: path ?? this.path,
      addToDatabase: addToDatabase ?? this.addToDatabase,
      displayMode: displayMode ?? this.displayMode,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'addToDatabase': addToDatabase,
      'displayMode': displayMode.name,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CustomFolder.fromJson(Map<String, dynamic> json) {
    final displayModeName = json['displayMode'] as String?;
    return CustomFolder(
      path: json['path'] as String,
      addToDatabase: json['addToDatabase'] as bool? ?? false,
      displayMode: CustomFolderDisplayMode.values.firstWhere(
        (mode) => mode.name == displayModeName,
        orElse: () => CustomFolderDisplayMode.personalCategory,
      ),
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CustomFolder &&
        other.path == path &&
        other.addToDatabase == addToDatabase &&
        other.displayMode == displayMode &&
        other.addedAt == addedAt;
  }

  @override
  int get hashCode => Object.hash(path, addToDatabase, displayMode, addedAt);
}

/// מנהל תיקיות מותאמות אישית
class CustomFoldersManager {
  /// טעינת רשימת התיקיות מההגדרות
  static List<CustomFolder> loadFolders(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => CustomFolder.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// האם קיימות תיקיות מותאמות אישית פעילות
  static bool hasFolders(String? jsonString) {
    return loadFolders(jsonString).isNotEmpty;
  }

  /// שמירת רשימת התיקיות להגדרות
  static String saveFolders(List<CustomFolder> folders) {
    return jsonEncode(folders.map((f) => f.toJson()).toList());
  }

  /// הוספת תיקייה חדשה
  static List<CustomFolder> addFolder(List<CustomFolder> folders, String path) {
    if (folders.any((f) => f.path == path)) {
      return folders; // התיקייה כבר קיימת
    }
    return [
      ...folders,
      CustomFolder(path: path, addedAt: DateTime.now()),
    ];
  }

  /// הסרת תיקייה
  static List<CustomFolder> removeFolder(
      List<CustomFolder> folders, String path) {
    return folders.where((f) => f.path != path).toList();
  }

  /// עדכון הגדרת addToDatabase לתיקייה
  static List<CustomFolder> updateFolderDbSetting(
      List<CustomFolder> folders, String path, bool addToDatabase) {
    return folders.map((f) {
      if (f.path == path) {
        return f.copyWith(addToDatabase: addToDatabase);
      }
      return f;
    }).toList();
  }

  static List<CustomFolder> updateFolderDisplayMode(
    List<CustomFolder> folders,
    String path,
    CustomFolderDisplayMode displayMode,
  ) {
    return folders.map((f) {
      if (f.path == path) {
        return f.copyWith(displayMode: displayMode);
      }
      return f;
    }).toList();
  }
}
