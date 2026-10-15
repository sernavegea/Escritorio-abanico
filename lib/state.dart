import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';
import 'ui.dart';

const kRoot = '/storage/emulated/0';

class AppEntry {
  const AppEntry(this.label, this.pkg);
  final String label;
  final String pkg;
}

/// Un acceso directo dentro de un abanico elegido por el usuario.
class Acceso {
  Acceso(this.kind, this.label, this.value, {this.icon = 'star', this.color = 3});
  String kind; // app | link | folder | ai
  String label;
  String value; // paquete, dirección web, ruta o modo de IA
  String icon;
  int color;
  Map<String, dynamic> toJson() => {'kind': kind, 'label': label, 'value': value, 'icon': icon, 'color': color};
  static Acceso fromJson(Map<String, dynamic> j) => Acceso(j['kind'] as String, j['label'] as String, j['value'] as String,
      icon: (j['icon'] ?? 'star') as String, color: ((j['color'] ?? 3) as num).toInt());
}

const builtinTypes = ['fotos', 'apps', 'docs', 'files', 'net', 'ia'];

/// Un icono del escritorio: un cajón de serie, un cajón propio o un acceso a una app.
class DrawerCfg {
  DrawerCfg(this.id, this.name, this.color, this.icon, {String? type, this.mode = 'auto', List<Acceso>? items, this.pkg = ''})
      : type = type ?? id,
        items = items ?? [];
  final String id;
  final String type; // fotos | apps | docs | files | net | ia | custom | app
  String name;
  int color;
  String icon;
  String mode; // auto | custom
  List<Acceso> items;
  String pkg; // solo para type == app

  bool get builtin => builtinTypes.contains(type);
  bool get customFan => type == 'custom' || mode == 'custom';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'color': color,
        'icon': icon,
        'mode': mode,
        'items': items.map((e) => e.toJson()).toList(),
        'pkg': pkg,
      };
  static DrawerCfg fromJson(Map<String, dynamic> j) => DrawerCfg(
        j['id'] as String,
        j['name'] as String,
        (j['color'] as num).toInt(),
        j['icon'] as String,
        type: (j['type'] ?? j['id']) as String,
        mode: (j['mode'] ?? 'auto') as String,
        items: (j['items'] is List)
            ? (j['items'] as List).map((e) => Acceso.fromJson(Map<String, dynamic>.from(e as Map))).toList()
            : <Acceso>[],
        pkg: (j['pkg'] ?? '') as String,
      );
}

/// Un widget de Android colocado en el escritorio.
class WidgetCfg {
  WidgetCfg(this.id, this.label, this.pkg, this.height);
  final int id;
  String label;
  final String pkg;
  double height;
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'pkg': pkg, 'height': height};
  static WidgetCfg fromJson(Map<String, dynamic> j) =>
      WidgetCfg((j['id'] as num).toInt(), (j['label'] ?? '') as String, (j['pkg'] ?? '') as String, ((j['height'] ?? 180) as num).toDouble());
}

class LinkItem {
  LinkItem(this.name, this.url, {this.icon = 'globe', this.color = 3, this.used = 0});
  String name;
  String url;
  String icon;
  int color;
  int used;
  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'icon': icon, 'color': color, 'used': used};
  static LinkItem fromJson(Map<String, dynamic> j) => LinkItem(j['name'] as String, j['url'] as String,
      icon: (j['icon'] ?? 'globe') as String, color: ((j['color'] ?? 3) as num).toInt(), used: ((j['used'] ?? 0) as num).toInt());
}

class PinItem {
  PinItem(this.name, this.path, {this.icon = 'folder', this.used = 0});
  String name;
  String path;
  String icon;
  int used;
  Map<String, dynamic> toJson() => {'name': name, 'path': path, 'icon': icon, 'used': used};
  static PinItem fromJson(Map<String, dynamic> j) => PinItem(j['name'] as String, j['path'] as String,
      icon: (j['icon'] ?? 'folder') as String, used: ((j['used'] ?? 0) as num).toInt());
}

List<DrawerCfg> defaultDrawers() => [
      DrawerCfg('fotos', 'Fotos', 0, 'photo'),
      DrawerCfg('apps', 'Apps', 1, 'apps'),
      DrawerCfg('docs', 'Documentos', 2, 'doc'),
      DrawerCfg('files', 'Archivos', 3, 'folder'),
      DrawerCfg('net', 'Internet', 4, 'globe'),
      DrawerCfg('ia', 'IA', 5, 'ai'),
    ];

List<LinkItem> defaultLinks() => [
      LinkItem('Google', 'https://www.google.com', icon: 'search', color: 7),
      LinkItem('Gmail', 'https://mail.google.com', icon: 'mail', color: 2),
      LinkItem('YouTube', 'https://www.youtube.com', icon: 'video', color: 2),
      LinkItem('El tiempo', 'https://www.aemet.es', icon: 'sun', color: 0),
      LinkItem('Noticias', 'https://news.google.com', icon: 'news', color: 8),
      LinkItem('Mapas', 'https://maps.google.com', icon: 'map', color: 1),
    ];

List<PinItem> defaultPins() => [
      PinItem('Descargas', '$kRoot/Download', icon: 'down'),
      PinItem('Documentos', '$kRoot/Documents', icon: 'doc'),
      PinItem('Cámara', '$kRoot/DCIM/Camera', icon: 'cam'),
      PinItem('Imágenes', '$kRoot/Pictures', icon: 'image'),
      PinItem('Música', '$kRoot/Music', icon: 'music'),
      PinItem('Vídeos', '$kRoot/Movies', icon: 'video'),
      PinItem('Raíz', kRoot, icon: 'drive'),
    ];

/// Modos del asistente: nombre -> (icono, color, instrucción de sistema).
const aiModes = <String, (String, int, String)>{
  'Chat': ('chat', 5, 'Eres un asistente útil dentro de un escritorio de Android. Responde en español, claro y breve.'),
  'Traducir': ('lang', 1,
      'Traduce el texto del usuario. Si está en español, tradúcelo al inglés; si está en otro idioma, al español. Devuelve solo la traducción.'),
  'Resumir': ('note', 8, 'Resume en español el texto del usuario en pocas frases, con los puntos clave.'),
  'Corregir': ('edit', 6, 'Corrige la ortografía y la gramática del texto del usuario en su mismo idioma. Devuelve solo el texto corregido.'),
  'Ideas': ('idea', 0, 'Propón ideas concretas y prácticas sobre lo que pida el usuario. Responde en español con una lista breve.'),
};

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;

  List<DrawerCfg> drawers = defaultDrawers();
  List<LinkItem> links = defaultLinks();
  List<PinItem> pins = defaultPins();
  Map<String, int> appUse = {};
  String wallpaper = 'laguna';
  String? wallpaperFile;
  double iconSize = 72;
  double radius = .28;
  String apiKey = '';
  String model = 'claude-sonnet-5-5';
  bool dual = true;
  bool listView = true;
  bool showHidden = false;
  String browserPkg = '';
  List<WidgetCfg> widgets = [];

  // Datos del dispositivo (no se guardan).
  List<AppEntry> apps = [];
  bool appsLoaded = false;
  final Map<String, Uint8List?> iconCache = {};
  final Map<String, Uint8List?> thumbCache = {};
  List<AssetEntity> recentPhotos = [];
  bool photosAllowed = false;
  List<File> recentDocs = [];
  Map<String, DateTime> docDates = {};
  bool filesAllowed = false;
  bool _loadingDocs = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final s = _prefs!.getString('cfg');
    if (s != null) {
      try {
        _fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    notifyListeners();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await loadApps();
    if (_prefs?.getBool('photosOk') == true) await loadPhotos();
    await loadDocs();
  }

  DrawerCfg drawer(String id) => drawers.firstWhere((d) => d.id == id,
      orElse: () => defaultDrawers().firstWhere((d) => d.id == id, orElse: () => DrawerCfg(id, '?', 7, 'star', type: 'custom')));

  // ---------- Escritorio ----------
  void moveDrawerTo(String id, int index) {
    final from = drawers.indexWhere((d) => d.id == id);
    if (from < 0) return;
    final d = drawers.removeAt(from);
    drawers.insert(index.clamp(0, drawers.length), d);
    changed();
  }

  List<DrawerCfg> hiddenBuiltins() =>
      defaultDrawers().where((b) => !drawers.any((d) => d.type == b.type)).toList();

  DrawerCfg addDrawer(DrawerCfg d) {
    drawers.add(d);
    changed();
    return d;
  }

  String newId() => 'c${DateTime.now().microsecondsSinceEpoch}';

  void removeDrawer(DrawerCfg d) {
    drawers.remove(d);
    changed();
  }

  void insertDrawer(int index, DrawerCfg d) {
    drawers.insert(index.clamp(0, drawers.length), d);
    changed();
  }

  // ---------- Widgets ----------
  void addWidget(WidgetCfg w) {
    widgets.add(w);
    changed();
  }

  void removeWidget(WidgetCfg w) {
    widgets.remove(w);
    Native.removeWidget(w.id);
    changed();
  }

  void moveWidget(WidgetCfg w, int delta) {
    final i = widgets.indexOf(w);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= widgets.length) return;
    widgets.removeAt(i);
    widgets.insert(j, w);
    changed();
  }

  // ---------- Navegador ----------
  Future<void> openUrl(String url) => Native.openUrl(url, pkg: browserPkg.isEmpty ? null : browserPkg);

  // ---------- Persistencia ----------
  Map<String, dynamic> _toJson() => {
        'drawers': drawers.map((d) => d.toJson()).toList(),
        'links': links.map((l) => l.toJson()).toList(),
        'pins': pins.map((p) => p.toJson()).toList(),
        'appUse': appUse,
        'wallpaper': wallpaper,
        'wallpaperFile': wallpaperFile,
        'iconSize': iconSize,
        'radius': radius,
        'apiKey': apiKey,
        'model': model,
        'dual': dual,
        'listView': listView,
        'showHidden': showHidden,
        'browserPkg': browserPkg,
        'widgets': widgets.map((w) => w.toJson()).toList(),
      };

  void _fromJson(Map<String, dynamic> j) {
    if (j['drawers'] is List) {
      drawers = (j['drawers'] as List).map((e) => DrawerCfg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    browserPkg = (j['browserPkg'] ?? '') as String;
    if (j['widgets'] is List) {
      widgets = (j['widgets'] as List).map((e) => WidgetCfg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    if (j['links'] is List) links = (j['links'] as List).map((e) => LinkItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    if (j['pins'] is List) pins = (j['pins'] as List).map((e) => PinItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    if (j['appUse'] is Map) appUse = (j['appUse'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    wallpaper = (j['wallpaper'] ?? wallpaper) as String;
    wallpaperFile = j['wallpaperFile'] as String?;
    iconSize = ((j['iconSize'] ?? iconSize) as num).toDouble();
    radius = ((j['radius'] ?? radius) as num).toDouble();
    apiKey = (j['apiKey'] ?? '') as String;
    model = (j['model'] ?? model) as String;
    dual = (j['dual'] ?? true) as bool;
    listView = (j['listView'] ?? true) as bool;
    showHidden = (j['showHidden'] ?? false) as bool;
  }

  void save() => _prefs?.setString('cfg', jsonEncode(_toJson()));

  void changed() {
    save();
    notifyListeners();
  }

  Future<void> resetLook() async {
    drawers = defaultDrawers();
    wallpaper = 'laguna';
    wallpaperFile = null;
    iconSize = 72;
    radius = .28;
    changed();
  }

  // ---------- Apps ----------
  Future<void> loadApps() async {
    apps = await Native.apps();
    appsLoaded = true;
    notifyListeners();
  }

  /// Apps ordenadas: primero las usadas más recientemente, luego el resto por nombre.
  List<AppEntry> recentApps() {
    final used = apps.where((a) => appUse.containsKey(a.pkg)).toList()..sort((a, b) => appUse[b.pkg]!.compareTo(appUse[a.pkg]!));
    final rest = apps.where((a) => !appUse.containsKey(a.pkg));
    return [...used, ...rest];
  }

  Future<bool> launchApp(String pkg) async {
    appUse[pkg] = DateTime.now().millisecondsSinceEpoch;
    save();
    final ok = await Native.launch(pkg);
    notifyListeners();
    return ok;
  }

  // ---------- Enlaces ----------
  List<LinkItem> recentLinks() {
    if (links.length <= 10) return links;
    final l = [...links]..sort((a, b) => b.used.compareTo(a.used));
    return l;
  }

  Future<void> openLink(LinkItem l) async {
    l.used = DateTime.now().millisecondsSinceEpoch;
    save();
    await openUrl(l.url);
  }

  // ---------- Carpetas ancladas ----------
  List<PinItem> recentPins() {
    if (pins.length <= 10) return pins;
    final l = [...pins]..sort((a, b) => b.used.compareTo(a.used));
    return l;
  }

  void usePin(String path) {
    var touched = false;
    for (final p in pins) {
      if (p.path == path) {
        p.used = DateTime.now().millisecondsSinceEpoch;
        touched = true;
      }
    }
    if (touched) save();
  }

  bool isPinned(String path) => pins.any((p) => p.path == path);

  void togglePin(String name, String path) {
    if (isPinned(path)) {
      pins.removeWhere((p) => p.path == path);
    } else {
      pins.add(PinItem(name, path, used: DateTime.now().millisecondsSinceEpoch));
    }
    changed();
  }

  // ---------- Fotos ----------
  Future<bool> loadPhotos() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      photosAllowed = ps.isAuth || ps == PermissionState.limited;
      await _prefs?.setBool('photosOk', photosAllowed);
      if (!photosAllowed) {
        notifyListeners();
        return false;
      }
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
      );
      recentPhotos = paths.isEmpty ? [] : await paths.first.getAssetListPaged(page: 0, size: 400);
    } catch (_) {
      recentPhotos = [];
    }
    notifyListeners();
    return photosAllowed;
  }

  // ---------- Documentos recientes ----------
  Future<void> loadDocs() async {
    if (_loadingDocs) return;
    _loadingDocs = true;
    try {
      filesAllowed = await Native.hasAllFiles();
      if (!filesAllowed) {
        recentDocs = [];
        return;
      }
      final found = <File>[];
      Future<void> walk(Directory d, int depth) async {
        if (depth > 5 || found.length > 3000) return;
        try {
          await for (final e in d.list(followLinks: false)) {
            final n = baseName(e.path);
            if (n.startsWith('.')) continue;
            if (e is Directory) {
              if (n == 'Android') continue;
              await walk(e, depth + 1);
            } else if (e is File && recentDocExt.contains(extOf(n))) {
              found.add(e);
            }
          }
        } catch (_) {}
      }

      for (final sub in ['Download', 'Documents', 'Desktop']) {
        final d = Directory('$kRoot/$sub');
        if (await d.exists()) await walk(d, 0);
      }
      final dates = <String, DateTime>{};
      for (final f in found) {
        try {
          dates[f.path] = (await f.stat()).modified;
        } catch (_) {
          dates[f.path] = DateTime(2000);
        }
      }
      found.sort((a, b) => dates[b.path]!.compareTo(dates[a.path]!));
      recentDocs = found.take(300).toList();
      docDates = dates;
    } finally {
      _loadingDocs = false;
      notifyListeners();
    }
  }

  // ---------- Fondo ----------
  void setPreset(String name) {
    _dropWallpaperFile();
    wallpaper = name;
    changed();
  }

  Future<void> setWallpaperFile(File src) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = '${dir.path}/fondo_${DateTime.now().millisecondsSinceEpoch}.${extOf(src.path).isEmpty ? 'jpg' : extOf(src.path)}';
    await src.copy(target);
    _dropWallpaperFile();
    wallpaperFile = target;
    changed();
  }

  void _dropWallpaperFile() {
    final old = wallpaperFile;
    wallpaperFile = null;
    if (old != null) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
  }
}

final app = AppState();
