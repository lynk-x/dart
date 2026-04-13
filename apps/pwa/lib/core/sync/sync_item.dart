import 'dart:convert';

enum SyncAction {
  insert,
  update,
  delete,
  rpc
}

class SyncItem {
  final String id;
  final String table;
  final SyncAction action;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int retryCount;

  SyncItem({
    required this.id,
    required this.table,
    required this.action,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table': table,
      'action': action.name,
      'payload': jsonEncode(payload),
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'],
      table: map['table'],
      action: SyncAction.values.byName(map['action']),
      payload: jsonDecode(map['payload']),
      createdAt: DateTime.parse(map['createdAt']),
      retryCount: map['retryCount'],
    );
  }
}
