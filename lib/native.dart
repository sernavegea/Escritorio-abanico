import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'desktop.dart';
import 'state.dart';

/// Puente con el código Kotlin de MainActivity.
class Native {
  static const ch = MethodChannel('abanico/native');

  static Future<List<AppEntry>> apps() async {
    if (Platform.isWindows) return Desk.apps();
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
    if (Platform.isWindows) return Desk.icon(pkg);
    try {
      return await ch.invokeMethod<Uint8List>('icon', {'pkg': pkg});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> launch(String pkg) async {
    if (Platform.isWindows) return Desk.launch(pkg);
    try {
      return await ch.invokeMethod<bool>('launch', {'pkg': pkg}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<AppEntry>> browsers() async {
    if (Platform.isWindows) return Desk.browsers();
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
    if (Platform.isWindows) return Desk.openUrl(url, pkg);
    try {
      return await ch.invokeMethod<bool>('openUrl', {'url': url, 'pkg': pkg ?? ''}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAlarms() async {
    if (Platform.isWindows) return Desk.openUri('ms-clock:');
    try {
      return await ch.invokeMethod<bool>('alarms') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openCalendar() async {
    if (Platform.isWindows) return Desk.openUri('outlookcal:');
    try {
      return await ch.invokeMethod<bool>('calendar') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<WidgetProvider>> widgetProviders() async {
    if (!Platform.isAndroid) return [];
    try {
      final r = await ch.invokeMethod<List<dynamic>>('widgetProviders') ?? const [];
      return r.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return WidgetProvider(
          label: (m['label'] ?? '') as String,
          app: (m['app'] ?? '') as String,
          pkg: (m['pkg'] ?? '') as String,
          cls: (m['cls'] ?? '') as String,
          minW: ((m['minW'] ?? 0) as num).toDouble(),
          minH: ((m['minH'] ?? 0) as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Reserva y enlaza un widget. Devuelve su id, o -1 si se canceló.
  static Future<int> addWidget(String pkg, String cls) async {
    if (!Platform.isAndroid) return -1;
    try {
      return await ch.invokeMethod<int>('addWidget', {'pkg': pkg, 'cls': cls}) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  static Future<void> removeWidget(int id) async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('removeWidget', {'id': id});
    } catch (_) {}
  }

  static Future<List<dynamic>> notifs() async {
    if (!Platform.isAndroid) return const [];
    try {
      return await ch.invokeMethod<List<dynamic>>('notifs') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> notifAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      return await ch.invokeMethod<bool>('notifAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> notifStatus() async {
    if (!Platform.isAndroid) return {};
    try {
      final r = await ch.invokeMethod<Map<dynamic, dynamic>>('notifStatus');
      return r == null ? {} : Map<String, dynamic>.from(r);
    } catch (_) {
      return {};
    }
  }

  static Future<void> requestNotifAccess() async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('requestNotifAccess');
    } catch (_) {}
  }

  static Future<bool> openNotif(String key) async {
    if (!Platform.isAndroid) return false;
    try {
      return await ch.invokeMethod<bool>('openNotif', {'key': key}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismissNotif(String key) async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('dismissNotif', {'key': key});
    } catch (_) {}
  }

  static Future<bool> replyNotif(String key, String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await ch.invokeMethod<bool>('replyNotif', {'key': key, 'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> appInfo(String pkg) async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('appInfo', {'pkg': pkg});
    } catch (_) {}
  }

  static Future<void> homeSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('homeSettings');
    } catch (_) {}
  }

  static Future<bool> hasAllFiles() async {
    if (!Platform.isAndroid) return true;
    try {
      return await ch.invokeMethod<bool>('hasAllFiles') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestAllFiles() async {
    if (!Platform.isAndroid) return;
    try {
      await ch.invokeMethod('requestAllFiles');
    } catch (_) {}
  }
}

class WidgetProvider {
  const WidgetProvider({required this.label, required this.app, required this.pkg, required this.cls, required this.minW, required this.minH});
  final String label;
  final String app;
  final String pkg;
  final String cls;
  final double minW;
  final double minH;
}
