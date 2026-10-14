import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'state.dart';

/// Puente con el código Kotlin de MainActivity.
class Native {
  static const ch = MethodChannel('abanico/native');

  static Future<List<AppEntry>> apps() async {
    try {
      final r = await ch.invokeMethod<List<dynamic>>('apps') ?? const [];
      return r.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return AppEntry((m['label'] ?? '') as String, (m['pkg'] ?? '') as String);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Uint8List?> icon(String pkg) async {
    try {
      return await ch.invokeMethod<Uint8List>('icon', {'pkg': pkg});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> launch(String pkg) async {
    try {
      return await ch.invokeMethod<bool>('launch', {'pkg': pkg}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<AppEntry>> browsers() async {
    try {
      final r = await ch.invokeMethod<List<dynamic>>('browsers') ?? const [];
      return r.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return AppEntry((m['label'] ?? '') as String, (m['pkg'] ?? '') as String);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> openUrl(String url, {String? pkg}) async {
    try {
      return await ch.invokeMethod<bool>('openUrl', {'url': url, 'pkg': pkg ?? ''}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> appInfo(String pkg) async {
    try {
      await ch.invokeMethod('appInfo', {'pkg': pkg});
    } catch (_) {}
  }

  static Future<void> homeSettings() async {
    try {
      await ch.invokeMethod('homeSettings');
    } catch (_) {}
  }

  static Future<bool> hasAllFiles() async {
    try {
      return await ch.invokeMethod<bool>('hasAllFiles') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFiles() async {
    try {
      await ch.invokeMethod('requestAllFiles');
    } catch (_) {}
  }
}
