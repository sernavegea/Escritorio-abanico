import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop.dart';
import 'native.dart';
import 'platform.dart';
import 'ui.dart';

export 'platform.dart';

/// Carpeta principal: el almacenamiento en Android, la carpeta del usuario en Windows.
final String kRoot = computeRoot();

/// Una foto: de la galería de Android o un archivo de imagen en Windows.
class PhotoItem {
  PhotoItem.asset(AssetEntity a)
      : asset = a,
        path = null;
  PhotoItem.file(String p)
      : asset = null,
        path = p;
  final AssetEntity? asset;
  final String? path;
  String get id => asset?.id ?? path!;
  String get title => asset?.title ?? baseName(path!);
  Future<File?> get file async => asset != null ? await asset!.file : File(path!);
}

class AppEntry {
  const AppEntry(this.label, this.pkg, {this.cat = -1, this.sys = false, this.game = false});
  final String label;
  final String pkg;
  final int cat; // categoría de Android (0 juego, 1 audio, 2 vídeo, 3 imagen, 4 social, 5 noticias, 6 mapas, 7 productividad)
  final bool sys; // viene con el móvil
  final bool game;
}

/// Cajones que se crean solos al organizar el escritorio: id -> (nombre, color).
const autoGroups = <String, (String, int)>{
  'google': ('Google', 7),
  'ent': ('Entretenimiento', 2),
  'bank': ('Bancos', 1),
  'util': ('Utilidades', 3),
  'games': ('Juegos', 5),
};

const _bankWords = [
  'banco', 'bank', 'bbva', 'santander', 'caixa', 'imagin', 'sabadell', 'openbank', 'unicaja', 'kutxa', 'cajamar',
  'abanca', 'ibercaja', 'ruralvia', 'cajarural', 'caja rural', 'revolut', 'number26', 'n26', 'myinvestor', 'traderepublic',
  'trade republic', 'paypal', 'bizum', 'transferwise', 'ingdirect', 'com.ing.', 'cajasur', 'wizink', 'cetelem', 'pibank',
  'bunq', 'selfbank', 'renta4', 'evo banco', 'evobanco', 'banca', 'coinbase', 'binance', 'bit2me',
];
const _entWords = [
  'netflix', 'spotify', 'primevideo', 'amazon.avod', 'disney', 'hbo', 'com.wbd', 'twitch', 'tiktok', 'musically', 'movistar',
  'dazn', 'filmin', 'atresplayer', 'rtve', 'mitele', 'skyshowtime', 'crunchyroll', 'plex', 'kodi', 'vlc', 'deezer', 'music',
  'música', 'musica', 'audible', 'ivoox', 'podcast', 'radio', 'video', 'vídeo', 'pluto', 'rakuten', 'soundcloud', 'shazam',
  'tidal', 'kindle', 'wattpad', 'comic', 'cine', 'tv',
];
const _utilWords = [
  'calcul', 'clock', 'reloj', 'notas', 'notes', 'recorder', 'grabadora', 'compass', 'brújula', 'brujula', 'weather', 'tiempo',
  'linterna', 'flashlight', 'torch', 'scanner', 'escáner', 'escaner', 'manager', 'optimiz', 'backup', 'copia de seg', 'themes',
  'temas', 'tips', 'consejos', 'mirror', 'espejo', 'herramient', 'tools', 'files', 'archivos', 'gestor', 'descargas', 'downloads',
  'lupa', 'magnifier', 'calendar', 'calendario', 'vpn', 'antivirus', 'cleaner', 'limpi', 'wifi', 'bluetooth', 'qr',
];

/// En qué cajón automático va una app (o null si se queda suelta en el escritorio).
String? groupOf(AppEntry a) {
  final p = a.pkg.toLowerCase();
  final t = '${a.label.toLowerCase()} $p';
  bool has(List<String> ks) => ks.any(t.contains);
  if (has(_bankWords)) return 'bank';
  if (a.game || a.cat == 0) return 'games';
  if (p.startsWith('com.google.') || p == 'com.android.chrome' || p == 'com.android.vending') return 'google';
  if (a.cat == 1 || a.cat == 2 || has(_entWords)) return 'ent';
  if (has(_utilWords)) return 'util';
  if (a.sys && a.cat != 4) return 'util';
  return null;
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
  int pos = -1; // casilla en el escritorio (página * casillasPorPágina + fila * columnas + columna); -1 = no está

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
        'pos': pos,
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
      )..pos = ((j['pos'] ?? -1) as num).toInt();
}

/// Una notificación que se muestra como bocadillo en el escritorio.
class Notif {
  Notif(this.key, this.pkg, this.app, this.title, this.text, this.time, this.reply);
  final String key;
  final String pkg;
  final String app;
  final String title;
  final String text;
  final DateTime time;
  final bool reply;
  static Notif fromMap(Map<String, dynamic> m) => Notif(
        (m['key'] ?? '') as String,
        (m['pkg'] ?? '') as String,
        (m['app'] ?? '') as String,
        (m['title'] ?? '') as String,
        (m['text'] ?? '') as String,
        DateTime.fromMillisecondsSinceEpoch(((m['time'] ?? 0) as num).toInt()),
        (m['reply'] ?? false) as bool,
      );
}

/// Un widget de Android colocado en el escritorio.
class WidgetCfg {
  WidgetCfg(this.id, this.label, this.pkg, this.height);
  final int id;
  String label;
  final String pkg;
  double height; // solo para pasar de versiones antiguas
  int page = 0;
  int row = 0;
  int rows = 2;
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'pkg': pkg, 'height': height, 'page': page, 'row': row, 'rows': rows};
  static WidgetCfg fromJson(Map<String, dynamic> j) =>
      WidgetCfg((j['id'] as num).toInt(), (j['label'] ?? '') as String, (j['pkg'] ?? '') as String, ((j['height'] ?? 180) as num).toDouble())
        ..page = ((j['page'] ?? 0) as num).toInt()
        ..row = ((j['row'] ?? 0) as num).toInt()
        ..rows = ((j['rows'] ?? 2) as num).toInt();
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
      if (isWin) PinItem('Escritorio', '$kRoot/${folderName('desktop')}', icon: 'screen'),
      PinItem('Descargas', '$kRoot/${folderName('download')}', icon: 'down'),
      PinItem('Documentos', '$kRoot/${folderName('documents')}', icon: 'doc'),
      if (!isWin) PinItem('Cámara', '$kRoot/${folderName('camera')}', icon: 'cam'),
      PinItem('Imágenes', '$kRoot/${folderName('pictures')}', icon: 'image'),
      PinItem('Música', '$kRoot/${folderName('music')}', icon: 'music'),
      PinItem('Vídeos', '$kRoot/${folderName('videos')}', icon: 'video'),
      if (isWin) PinItem('Disco C:', 'C:/', icon: 'drive') else PinItem('Raíz', kRoot, icon: 'drive'),
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
  List<String> dock = [];
  int gridCols = isWin ? 8 : 4;
  int gridRows = isWin ? 5 : 6;
  String dockSide = 'left'; // left | bottom | none
  int layoutV = 0;
  Set<String> knownApps = {};
  bool showNotifs = true;
  List<Notif> notifs = [];
  bool notifAccess = false;

  // Datos del dispositivo (no se guardan).
  List<AppEntry> apps = [];
  bool appsLoaded = false;
  final Map<String, Uint8List?> iconCache = {};
  final Map<String, Uint8List?> thumbCache = {};
  List<PhotoItem> recentPhotos = [];
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
    _migrate();
    if (_compactPages()) save();
    notifyListeners();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await loadNotifs();
    await loadApps();
    if (_prefs?.getBool('photosOk') == true) await loadPhotos();
    await loadDocs();
  }

  DrawerCfg drawer(String id) => drawers.firstWhere((d) => d.id == id,
      orElse: () => defaultDrawers().firstWhere((d) => d.id == id, orElse: () => DrawerCfg(id, '?', 7, 'star', type: 'custom')));

  // ---------- Escritorio: cuadrícula con páginas y barra lateral ----------
  int get perPage => gridCols * gridRows;
  int pageOf(int slot) => slot ~/ perPage;
  int rowOf(int slot) => (slot % perPage) ~/ gridCols;
  int colOf(int slot) => slot % gridCols;

  bool blocked(int slot) {
    final p = pageOf(slot), r = rowOf(slot);
    return widgets.any((w) => w.page == p && r >= w.row && r < w.row + w.rows);
  }

  List<DrawerCfg> get deskItems => drawers.where((d) => d.pos >= 0 && !dock.contains(d.id)).toList();
  List<DrawerCfg> get dockItems => [for (final id in dock) ...drawers.where((d) => d.id == id)];

  DrawerCfg? itemAt(int slot) {
    for (final d in drawers) {
      if (d.pos == slot && !dock.contains(d.id)) return d;
    }
    return null;
  }

  bool slotFree(int slot) => !blocked(slot) && itemAt(slot) == null;

  int firstFree([int fromPage = 0]) {
    var s = max(0, fromPage) * perPage;
    while (!slotFree(s)) {
      s++;
    }
    return s;
  }

  int get pageCount {
    var m = 1;
    for (final d in deskItems) {
      m = max(m, pageOf(d.pos) + 1);
    }
    for (final w in widgets) {
      m = max(m, w.page + 1);
    }
    return m;
  }

  List<DrawerCfg> hiddenBuiltins() => defaultDrawers().where((b) => !drawers.any((d) => d.type == b.type)).toList();

  String newId() => 'c${DateTime.now().microsecondsSinceEpoch}';

  DrawerCfg addDrawer(DrawerCfg d, {int fromPage = 0, bool toDock = false}) {
    drawers.add(d);
    if (toDock) {
      dock.add(d.id);
    } else {
      d.pos = firstFree(fromPage);
    }
    changed();
    return d;
  }

  void addMany(List<DrawerCfg> list, {int fromPage = 0}) {
    for (final d in list) {
      drawers.add(d);
      d.pos = firstFree(fromPage);
    }
    changed();
  }

  /// Mueve un icono a una casilla. Si está ocupada, los dos se intercambian.
  void moveToSlot(String id, int slot) {
    final i = drawers.indexWhere((d) => d.id == id);
    if (i < 0 || blocked(slot)) return;
    final d = drawers[i];
    final other = itemAt(slot);
    if (other != null && other.id == id) return;
    final fromDock = dock.indexOf(id);
    if (other != null) {
      if (fromDock >= 0) {
        dock[fromDock] = other.id;
        other.pos = -1;
      } else {
        other.pos = d.pos;
      }
    } else if (fromDock >= 0) {
      dock.removeAt(fromDock);
    }
    d.pos = slot;
    changed();
  }

  /// Mete un icono en la barra lateral en esa posición.
  void moveToDock(String id, int index) {
    final i = drawers.indexWhere((d) => d.id == id);
    if (i < 0) return;
    final old = dock.indexOf(id);
    var at = index;
    if (old >= 0) {
      dock.removeAt(old);
      if (old < at) at--;
    }
    drawers[i].pos = -1;
    dock.insert(at.clamp(0, dock.length), id);
    changed();
  }

  void removeDrawer(DrawerCfg d) {
    drawers.remove(d);
    dock.remove(d.id);
    changed();
  }

  void restoreDrawer(DrawerCfg d, int dockIndex, int pos) {
    drawers.add(d);
    if (dockIndex >= 0) {
      dock.insert(min(dockIndex, dock.length), d.id);
    } else {
      d.pos = -1;
      d.pos = (pos >= 0 && slotFree(pos)) ? pos : firstFree();
    }
    changed();
  }

  /// Saca los iconos que hayan quedado debajo de un widget y los coloca en huecos libres.
  void _relocate() {
    final moved = deskItems.where((d) => blocked(d.pos)).toList();
    for (final d in moved) {
      final page = pageOf(d.pos);
      d.pos = -1;
      d.pos = firstFree(page);
    }
  }

  /// Recoloca todo en orden cuando cambia el tamaño de la cuadrícula.
  void reflow() {
    for (final w in widgets) {
      w.rows = w.rows.clamp(1, gridRows);
      w.row = w.row.clamp(0, gridRows - w.rows);
    }
    final items = deskItems..sort((a, b) => a.pos.compareTo(b.pos));
    for (final d in items) {
      d.pos = -1;
    }
    for (final d in items) {
      d.pos = firstFree();
    }
    changed();
  }

  void setGrid(int cols, int rows) {
    // Conserva el orden de lectura de los iconos al cambiar la cuadrícula.
    final items = deskItems..sort((a, b) => a.pos.compareTo(b.pos));
    gridCols = cols;
    gridRows = rows;
    for (var k = 0; k < items.length; k++) {
      items[k].pos = -1;
    }
    for (final w in widgets) {
      w.rows = w.rows.clamp(1, gridRows);
      w.row = w.row.clamp(0, gridRows - w.rows);
    }
    for (final d in items) {
      d.pos = firstFree();
    }
    changed();
  }

  void _migrate() {
    if (layoutV >= 2) return;
    dock = [
      for (final t in ['apps', 'fotos', 'files', 'ia'])
        ...drawers.where((d) => d.type == t).take(1).map((d) => d.id),
    ];
    for (final d in drawers) {
      d.pos = -1;
    }
    var page = 0, row = 0;
    for (final w in widgets) {
      w.rows = (w.height / 110).round().clamp(1, 4);
      if (row + w.rows > gridRows) {
        page++;
        row = 0;
      }
      w.page = page;
      w.row = row;
      row += w.rows;
    }
    for (final d in drawers) {
      if (!dock.contains(d.id)) d.pos = firstFree();
    }
    layoutV = 2;
    save();
  }

  // ---------- Notificaciones ----------
  Future<void> loadNotifs() async {
    notifAccess = await Native.notifAccess();
    if (notifAccess) {
      setNotifs(await Native.notifs());
    } else {
      notifs = [];
      notifyListeners();
    }
  }

  void setNotifs(List<dynamic> raw) {
    notifs = raw.map((e) => Notif.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    if (notifs.isNotEmpty) notifAccess = true;
    notifyListeners();
  }

  void dropNotif(String key) {
    notifs.removeWhere((n) => n.key == key);
    notifyListeners();
    Native.dismissNotif(key);
  }

  // ---------- Widgets ----------
  bool _widgetFits(WidgetCfg w, int page, int row, {bool allowIcons = true}) {
    if (row < 0 || row + w.rows > gridRows) return false;
    for (final o in widgets) {
      if (o == w || o.page != page) continue;
      if (row < o.row + o.rows && o.row < row + w.rows) return false;
    }
    if (!allowIcons) {
      for (final d in deskItems) {
        final r = rowOf(d.pos);
        if (pageOf(d.pos) == page && r >= row && r < row + w.rows) return false;
      }
    }
    return true;
  }

  /// Coloca un widget nuevo: primero busca filas vacías; si no hay, lo pone arriba y aparta los iconos.
  void addWidget(WidgetCfg w, {int page = 0, int rows = 2}) {
    w.rows = rows.clamp(1, gridRows);
    var placed = false;
    for (var p = page; p < pageCount + 1 && !placed; p++) {
      for (var r = 0; r + w.rows <= gridRows; r++) {
        if (_widgetFits(w, p, r, allowIcons: false)) {
          w.page = p;
          w.row = r;
          placed = true;
          break;
        }
      }
    }
    if (!placed) {
      w.page = pageCount;
      w.row = 0;
    }
    widgets.add(w);
    _relocate();
    changed();
  }

  void removeWidget(WidgetCfg w) {
    widgets.remove(w);
    Native.removeWidget(w.id);
    changed();
  }

  void moveWidget(WidgetCfg w, int deltaRow) {
    var r = w.row + deltaRow;
    while (r >= 0 && r + w.rows <= gridRows && !_widgetFits(w, w.page, r)) {
      r += deltaRow;
    }
    if (r < 0 || r + w.rows > gridRows) return;
    w.row = r;
    _relocate();
    changed();
  }

  void moveWidgetPage(WidgetCfg w, int delta) {
    final p = w.page + delta;
    if (p < 0) return;
    for (var r = 0; r + w.rows <= gridRows; r++) {
      if (_widgetFits(w, p, r)) {
        w.page = p;
        w.row = r;
        _relocate();
        changed();
        return;
      }
    }
  }

  void resizeWidget(WidgetCfg w) {
    var n = w.rows + 1;
    if (n > gridRows - w.row || !_widgetFitsRows(w, n)) n = 1;
    w.rows = n;
    _relocate();
    changed();
  }

  bool _widgetFitsRows(WidgetCfg w, int n) {
    final old = w.rows;
    w.rows = n;
    final ok = _widgetFits(w, w.page, w.row);
    w.rows = old;
    return ok;
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
        'showNotifs': showNotifs,
        'dock': dock,
        'gridCols': gridCols,
        'gridRows': gridRows,
        'dockSide': dockSide,
        'layoutV': layoutV,
        'knownApps': knownApps.toList(),
      };

  void _fromJson(Map<String, dynamic> j) {
    if (j['drawers'] is List) {
      drawers = (j['drawers'] as List).map((e) => DrawerCfg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    }
    browserPkg = (j['browserPkg'] ?? '') as String;
    showNotifs = (j['showNotifs'] ?? true) as bool;
    if (j['dock'] is List) dock = (j['dock'] as List).map((e) => e as String).toList();
    gridCols = ((j['gridCols'] ?? gridCols) as num).toInt();
    gridRows = ((j['gridRows'] ?? gridRows) as num).toInt();
    dockSide = (j['dockSide'] ?? dockSide) as String;
    layoutV = ((j['layoutV'] ?? 0) as num).toInt();
    if (j['knownApps'] is List) knownApps = (j['knownApps'] as List).map((e) => e as String).toSet();
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
    _compactPages();
    save();
    notifyListeners();
  }

  /// Mientras se arrastra un icono no se quitan páginas (para no mover el escritorio bajo el dedo).
  bool holdCompact = false;

  /// Quita las páginas que se han quedado sin iconos ni widgets entre otras que sí tienen.
  bool _compactPages() {
    if (holdCompact) return false;
    var moved = false;
    var p = 0;
    while (p < pageCount) {
      final used = deskItems.any((d) => pageOf(d.pos) == p) || widgets.any((w) => w.page == p);
      if (!used) {
        final later = deskItems.any((d) => pageOf(d.pos) > p) || widgets.any((w) => w.page > p);
        if (!later) break;
        for (final d in deskItems) {
          if (pageOf(d.pos) > p) d.pos -= perPage;
        }
        for (final w in widgets) {
          if (w.page > p) w.page--;
        }
        moved = true;
        continue;
      }
      p++;
    }
    return moved;
  }

  /// Al terminar de arrastrar: recoge las páginas vacías que hayan quedado.
  void compactNow() {
    if (_compactPages()) {
      save();
      notifyListeners();
    }
  }

  Future<void> resetLook() async {
    drawers = defaultDrawers();
    dock = [];
    layoutV = 0;
    _migrate();
    if (isAndroid && apps.isNotEmpty) await buildDefaultLayout();
    wallpaper = 'laguna';
    wallpaperFile = null;
    iconSize = 72;
    radius = .28;
    changed();
  }

  // ---------- Apps ----------
  Future<void> loadApps() async {
    Desk.onAppsUpdated = (fresh) {
      apps = fresh;
      notifyListeners();
    };
    apps = await Native.apps();
    appsLoaded = true;
    if (isAndroid && apps.isNotEmpty) {
      if (layoutV < 3) {
        await buildDefaultLayout();
      } else {
        _syncApps();
      }
    }
    notifyListeners();
  }

  DrawerCfg _appDrawer(AppEntry a) => DrawerCfg('a_${a.pkg}', a.label, 1, 'apps', type: 'app', pkg: a.pkg);

  /// Escritorio de serie: barra con WhatsApp, cámara, teléfono, fotos, archivos y ajustes;
  /// cajones Google, Entretenimiento, Bancos, Utilidades y Juegos; y el resto de apps sueltas.
  /// Conserva los cajones que haya creado el usuario y los widgets.
  bool _building = false;
  Future<void> buildDefaultLayout() async {
    if (!isAndroid || apps.isEmpty || _building) return;
    _building = true;
    final Map<String, String> roles;
    try {
      roles = await Native.roles();
    } finally {
      _building = false;
    }
    final byPkg = {for (final a in apps) a.pkg: a};
    String? pick(String role, List<String> pkgs, List<String> labels) {
      final r = roles[role];
      if (r != null && byPkg.containsKey(r)) return r;
      for (final p in pkgs) {
        if (byPkg.containsKey(p)) return p;
      }
      for (final a in apps) {
        if (labels.contains(a.label.toLowerCase())) return a.pkg;
      }
      for (final a in apps) {
        final l = a.label.toLowerCase();
        if (labels.any(l.contains)) return a.pkg;
      }
      return null;
    }

    final wa = pick('', ['com.whatsapp', 'com.whatsapp.w4b'], ['whatsapp']);
    final cam = pick('camera', [
      'com.hihonor.camera', 'com.huawei.camera', 'com.android.camera', 'com.android.camera2', 'com.google.android.GoogleCamera',
      'com.sec.android.app.camera', 'com.oplus.camera', 'com.motorola.camera3',
    ], ['cámara', 'camara', 'camera']);
    final phone = pick('phone', [
      'com.hihonor.contacts', 'com.huawei.contacts', 'com.google.android.dialer', 'com.android.dialer', 'com.samsung.android.dialer',
    ], ['teléfono', 'telefono', 'phone']);
    final settings = pick('settings', ['com.android.settings'], ['ajustes', 'configuración', 'settings']);

    // Fuera las apps sueltas y los cajones automáticos de antes; vuelven los cajones de serie que faltaran.
    drawers.removeWhere((d) => d.type == 'app' || d.id.startsWith('g_'));
    for (final b in defaultDrawers()) {
      if (!drawers.any((d) => d.type == b.type)) drawers.add(b);
    }
    for (final d in drawers) {
      d.pos = -1;
    }
    dock = [];
    final dockPkgs = <String>{};
    void dockApp(String? pkg) {
      if (pkg == null || !dockPkgs.add(pkg)) return;
      final d = _appDrawer(byPkg[pkg]!);
      drawers.add(d);
      dock.add(d.id);
    }

    void dockBuiltin(String type) {
      for (final d in drawers) {
        if (d.type == type) {
          dock.add(d.id);
          return;
        }
      }
    }

    dockApp(wa);
    dockApp(cam);
    dockApp(phone);
    dockBuiltin('fotos');
    dockBuiltin('files');
    dockApp(settings);

    // Las apps básicas del sistema (mensajes, contactos, navegador…) se quedan sueltas, no en Utilidades.
    final core = {...dockPkgs, for (final k in ['sms', 'contacts', 'browser', 'email', 'gallery']) if (roles[k] != null) roles[k]!};
    // Apps que el usuario ya metió en sus propios cajones-carpeta: no se repiten.
    final inFolders = <String>{
      for (final d in drawers)
        if (d.type == 'custom' && d.icon == '_grid')
          for (final i in d.items)
            if (i.kind == 'app') i.value,
    };
    final groups = <String, List<AppEntry>>{for (final k in autoGroups.keys) k: []};
    final loose = <AppEntry>[];
    for (final a in apps) {
      if (dockPkgs.contains(a.pkg) || inFolders.contains(a.pkg)) continue;
      final g = core.contains(a.pkg) ? null : groupOf(a);
      if (g == null) {
        loose.add(a);
      } else {
        groups[g]!.add(a);
      }
    }

    final order = <DrawerCfg>[];
    for (final e in autoGroups.entries) {
      final list = groups[e.key]!;
      if (list.isEmpty) continue;
      order.add(DrawerCfg('g_${e.key}', e.value.$1, e.value.$2, '_grid',
          type: 'custom', mode: 'custom', items: [for (final a in list) Acceso('app', a.label, a.pkg, icon: 'apps', color: 1)]));
    }
    order.addAll(drawers.where((d) => !dock.contains(d.id)));
    loose.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    order.addAll(loose.map(_appDrawer));
    for (final d in order) {
      if (!drawers.contains(d)) drawers.add(d);
      d.pos = firstFree();
    }
    knownApps = apps.map((a) => a.pkg).toSet();
    layoutV = 3;
    changed();
  }

  /// Apps nuevas aparecen solas al final del escritorio; las desinstaladas desaparecen.
  void _syncApps() {
    if (apps.length < 5) return;
    final have = apps.map((a) => a.pkg).toSet();
    var dirty = false;
    final gone = drawers.where((d) => d.type == 'app' && !have.contains(d.pkg)).toList();
    for (final d in gone) {
      drawers.remove(d);
      dock.remove(d.id);
      dirty = true;
    }
    for (final d in drawers) {
      if (d.type != 'custom') continue;
      final n = d.items.length;
      d.items.removeWhere((a) => a.kind == 'app' && !have.contains(a.value));
      if (d.items.length != n) dirty = true;
    }
    final fresh = apps.where((a) => !knownApps.contains(a.pkg)).toList();
    for (final a in fresh) {
      final placed = drawers.any((d) => (d.type == 'app' && d.pkg == a.pkg) || d.items.any((i) => i.kind == 'app' && i.value == a.pkg));
      if (placed) continue;
      final d = _appDrawer(a);
      drawers.add(d);
      d.pos = firstFree();
    }
    if (fresh.isNotEmpty) {
      knownApps.addAll(fresh.map((a) => a.pkg));
      dirty = true;
    }
    if (dirty) changed();
  }

  /// Suelta un icono encima de otro:
  /// app sobre app → nuevo cajón con las dos; app sobre cajón propio → se añade; si no, se intercambian.
  /// Devuelve 'new', 'added' o null.
  String? dropOn(String fromId, String toId) {
    if (fromId == toId) return null;
    final fi = drawers.indexWhere((d) => d.id == fromId);
    final ti = drawers.indexWhere((d) => d.id == toId);
    if (fi < 0 || ti < 0) return null;
    final from = drawers[fi], to = drawers[ti];
    Acceso acc(DrawerCfg d) => Acceso('app', d.name, d.pkg, icon: 'apps', color: d.color);
    if (from.type == 'app' && to.type == 'app') {
      AppEntry? entry(String pkg) {
        for (final a in apps) {
          if (a.pkg == pkg) return a;
        }
        return null;
      }

      final ea = entry(from.pkg), eb = entry(to.pkg);
      final ga = ea == null ? null : groupOf(ea), gb = eb == null ? null : groupOf(eb);
      final name = (ga != null && ga == gb) ? autoGroups[ga]!.$1 : 'Cajón';
      final folder = DrawerCfg(newId(), name, 6, '_grid', type: 'custom', mode: 'custom', items: [acc(to), acc(from)]);
      final di = dock.indexOf(to.id);
      if (di >= 0) {
        dock[di] = folder.id;
      } else {
        folder.pos = to.pos;
      }
      drawers[ti] = folder;
      drawers.remove(from);
      dock.remove(from.id);
      changed();
      return 'new';
    }
    if (from.type == 'app' && to.type == 'custom') {
      if (!to.items.any((a) => a.kind == 'app' && a.value == from.pkg)) to.items.add(acc(from));
      to.mode = 'custom';
      drawers.remove(from);
      dock.remove(from.id);
      changed();
      return 'added';
    }
    final tDock = dock.indexOf(to.id), fDock = dock.indexOf(from.id);
    if (tDock >= 0) {
      if (fDock >= 0) {
        dock[tDock] = from.id;
        dock[fDock] = to.id;
      } else {
        dock[tDock] = from.id;
        to.pos = from.pos;
        from.pos = -1;
      }
      changed();
    } else if (to.pos >= 0) {
      moveToSlot(from.id, to.pos);
    }
    return null;
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
    if (isWin) {
      photosAllowed = true;
      final roots = ['$kRoot/Pictures', '$kRoot/OneDrive/Pictures', '$kRoot/OneDrive/Imágenes', '$kRoot/Desktop', '$kRoot/Downloads'];
      final files = await scanFiles(roots, imgExt, maxDepth: 4, limit: 4000);
      recentPhotos = files.take(400).map((f) => PhotoItem.file(f.path)).toList();
      notifyListeners();
      return true;
    }
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
      recentPhotos = paths.isEmpty ? [] : (await paths.first.getAssetListPaged(page: 0, size: 400)).map(PhotoItem.asset).toList();
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
      final roots = isWin
          ? ['$kRoot/Downloads', '$kRoot/Documents', '$kRoot/Desktop', '$kRoot/OneDrive/Documentos', '$kRoot/OneDrive/Documents', '$kRoot/OneDrive/Escritorio', '$kRoot/OneDrive/Desktop']
          : ['$kRoot/Download', '$kRoot/Documents', '$kRoot/Desktop'];
      final found = await scanFiles(roots, recentDocExt, maxDepth: 5, limit: 3000, dates: docDates);
      recentDocs = found.take(300).toList();
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


/// Busca archivos con esas extensiones y los devuelve del más nuevo al más antiguo (rutas con '/').
Future<List<File>> scanFiles(List<String> roots, Set<String> exts, {int maxDepth = 5, int limit = 3000, Map<String, DateTime>? dates}) async {
  final found = <File>[];
  const skip = {'Android', 'AppData', 'node_modules', '\$RECYCLE.BIN', 'Program Files', 'Windows'};
  Future<void> walk(Directory d, int depth) async {
    if (depth > maxDepth || found.length > limit) return;
    try {
      await for (final e in d.list(followLinks: false)) {
        final path = np(e.path);
        final n = baseName(path);
        if (n.startsWith('.')) continue;
        if (e is Directory) {
          if (skip.contains(n)) continue;
          await walk(Directory(path), depth + 1);
        } else if (e is File && exts.contains(extOf(n))) {
          found.add(File(path));
        }
      }
    } catch (_) {}
  }

  final seen = <String>{};
  for (final r in roots) {
    final d = Directory(r);
    if (!seen.add(r.toLowerCase())) continue;
    if (await d.exists()) await walk(d, 0);
  }
  final unique = <String, File>{for (final f in found) f.path.toLowerCase(): f}.values.toList();
  final when = dates ?? <String, DateTime>{};
  for (final f in unique) {
    try {
      when[f.path] = (await f.stat()).modified;
    } catch (_) {
      when[f.path] = DateTime(2000);
    }
  }
  unique.sort((a, b) => when[b.path]!.compareTo(when[a.path]!));
  return unique;
}
