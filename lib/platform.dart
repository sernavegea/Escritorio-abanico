import 'dart:io';

/// Diferencias entre Android y Windows: carpetas, rutas y nombres.

bool get isWin => Platform.isWindows;
bool get isAndroid => Platform.isAndroid;

/// Normaliza una ruta para usar siempre '/' (Windows acepta ambas barras).
String np(String p) {
  final s = p.replaceAll('\\', '/');
  final lead = s.startsWith('//') ? '//' : '';
  return lead + s.substring(lead.length).replaceAll(RegExp('/{2,}'), '/');
}

/// Ruta en el formato de Windows, para pasarla a programas externos.
String winPath(String p) => p.replaceAll('/', '\\');

String computeRoot() {
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? 'C:/Users/Public';
    return np(home);
  }
  return '/storage/emulated/0';
}

/// Nombre que se muestra para la carpeta principal.
String get rootLabel => isWin ? 'Mi carpeta' : 'Almacenamiento';

/// Subcarpetas habituales con su nombre real en disco.
String folderName(String what) {
  if (isWin) {
    return const {
      'download': 'Downloads',
      'documents': 'Documents',
      'pictures': 'Pictures',
      'music': 'Music',
      'videos': 'Videos',
      'desktop': 'Desktop',
      'camera': 'Pictures/Camera Roll',
      'screenshots': 'Pictures/Screenshots',
    }[what]!;
  }
  return const {
    'download': 'Download',
    'documents': 'Documents',
    'pictures': 'Pictures',
    'music': 'Music',
    'videos': 'Movies',
    'desktop': 'Desktop',
    'camera': 'DCIM/Camera',
    'screenshots': 'Pictures/Screenshots',
  }[what]!;
}

/// Carpeta superior, o null si ya estamos arriba del todo (raíz de Android o raíz de una unidad).
String? parentOf(String path, String root) {
  final p = np(path);
  if (!isWin && (p == root || !p.startsWith(root))) return null;
  if (isWin && RegExp(r'^[A-Za-z]:/?$').hasMatch(p)) return null;
  final i = p.lastIndexOf('/');
  if (i < 0) return null;
  final parent = p.substring(0, i);
  if (isWin && RegExp(r'^[A-Za-z]:$').hasMatch(parent)) return '$parent/';
  return parent;
}

/// Trozos de la barra de ruta: (texto, ruta).
List<(String, String)> crumbsOf(String path, String root) {
  final p = np(path);
  if (p == root || p.startsWith('$root/')) {
    final out = <(String, String)>[(rootLabel, root)];
    if (p != root) {
      var acc = root;
      for (final s in p.substring(root.length + 1).split('/')) {
        if (s.isEmpty) continue;
        acc = '$acc/$s';
        out.add((s, acc));
      }
    }
    return out;
  }
  // Fuera de la carpeta principal (por ejemplo C:/ en Windows): ruta absoluta.
  final parts = p.split('/').where((s) => s.isNotEmpty).toList();
  final out = <(String, String)>[];
  var acc = '';
  for (var i = 0; i < parts.length; i++) {
    acc = i == 0 ? (isWin ? '${parts[0]}/' : '/${parts[0]}') : (acc.endsWith('/') ? '$acc${parts[i]}' : '$acc/${parts[i]}');
    out.add((i == 0 && isWin ? 'Disco ${parts[0]}' : parts[i], acc));
  }
  return out;
}
