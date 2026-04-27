import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';

class ForumCache {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'forum_cache.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            forum_id TEXT,
            data TEXT,
            type TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE forum_members (
            forum_id TEXT,
            user_id TEXT,
            role TEXT,
            capabilities TEXT,
            PRIMARY KEY (forum_id, user_id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE forum_members (
              forum_id TEXT,
              user_id TEXT,
              role TEXT,
              capabilities TEXT,
              PRIMARY KEY (forum_id, user_id)
            )
          ''');
        }
      },
    );
  }

  static Future<void> cacheMemberInfo({
    required String forumId,
    required String userId,
    required String role,
    required Map<String, dynamic> capabilities,
  }) async {
    final db = await database;
    await db.insert('forum_members', {
      'forum_id': forumId,
      'user_id': userId,
      'role': role,
      'capabilities': jsonEncode(capabilities),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getCachedMemberInfo(
    String forumId,
    String userId,
  ) async {
    final db = await database;
    final results = await db.query(
      'forum_members',
      where: 'forum_id = ? AND user_id = ?',
      whereArgs: [forumId, userId],
    );

    if (results.isEmpty) return null;

    final row = results.first;
    return {
      'role': row['role'],
      'capabilities': jsonDecode(row['capabilities'] as String),
    };
  }

  static Future<void> cacheMessages(
    List<ChatMessage> messages,
    String forumId,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var msg in messages) {
      batch.insert('messages', {
        'id': msg.id,
        'forum_id': forumId,
        'data': jsonEncode(msg.toMap()),
        'type': msg.type == MessageType.announcement ? 'announcement' : 'chat',
        'created_at': msg.createdAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  static Future<List<ChatMessage>> getCachedMessages(
    String forumId,
    String currentUserId, {
    String? type,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'forum_id = ? ${type != null ? 'AND type = ?' : ''}',
      whereArgs: [forumId, if (type != null) type],
      orderBy: 'created_at DESC',
      limit: 50,
    );

    return maps.map((map) {
      final data = jsonDecode(map['data'] as String) as Map<String, dynamic>;
      return ChatMessage.fromMap(data, currentUserId);
    }).toList();
  }

  static Future<void> clearCache(String forumId) async {
    final db = await database;
    await db.delete('messages', where: 'forum_id = ?', whereArgs: [forumId]);
  }
}
