import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/local_sync_store.dart';

typedef SyncExecutor = Future<void> Function(LocalSyncItem item);

class SyncEngine {
  SyncEngine({
    required this.store,
    required this.executors,
    this.maxAttempts = 5,
  });

  final LocalSyncStore store;
  final Map<String, SyncExecutor> executors;
  final int maxAttempts;
  bool _draining = false;

  bool get isDraining => _draining;

  Future<int> drain({int limit = 25}) async {
    if (_draining) return 0;
    _draining = true;
    try {
      await store.recoverInterrupted();
      final items = await store.ready(limit: limit);
      var completed = 0;
      for (final item in items) {
        final executor = executors[item.provider];
        if (executor == null) {
          await store.markFailed(
            item.id,
            StateError('No sync executor for provider ${item.provider}'),
            maxAttempts: 1,
            retryAfter: Duration.zero,
          );
          continue;
        }
        await store.markRunning(item.id);
        try {
          await executor(item);
          await store.markDone(item.id);
          completed++;
        } catch (error) {
          final attempt = item.attempts + 1;
          await store.markFailed(
            item.id,
            error,
            maxAttempts: maxAttempts,
            retryAfter: retryDelay(attempt),
          );
        }
      }
      return completed;
    } finally {
      _draining = false;
    }
  }

  static Duration retryDelay(int attempt) {
    final seconds = switch (attempt) {
      <= 1 => 5,
      2 => 15,
      3 => 60,
      4 => 300,
      _ => 900,
    };
    return Duration(seconds: seconds);
  }

  static Future<String> sha256File(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  static String sha256Bytes(List<int> bytes) => sha256.convert(bytes).toString();

  static String canonicalJsonChecksum(Map<String, dynamic> value) {
    dynamic normalize(dynamic input) {
      if (input is Map) {
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return <String, dynamic>{
          for (final key in keys) key: normalize(input[key]),
        };
      }
      if (input is List) return input.map(normalize).toList(growable: false);
      return input;
    }

    return sha256.convert(utf8.encode(jsonEncode(normalize(value)))).toString();
  }
}
