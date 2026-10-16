import 'dart:io';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'native.dart';
import 'state.dart';

// Colores de la interfaz (tema oscuro único, igual que el prototipo).
const kInk = Color(0xFFF3F1EA);
const kDim = Color(0xFFB9C4BF);
const kGlow = Color(0xFFE0A458);
const kSheet = Color(0xFF132C2F);
const kSheet2 = Color(0xFF1B3A3D);
const kField = Color(0xFF0E2326);
const kExBg = Color(0xFF102629);
const kLine = Color(0x24F3F1EA);
const kSel = Color(0x2EE0A458);
const kDanger = Color(0xFFFF8A80);

const palettes = <List<Color>>[
  [Color(0xFFF2B45A), Color(0xFFD9782B)],
  [Color(0xFF3FB5A3), Color(0xFF1F7F78)],
  [Color(0xFFEE7D6B), Color(0xFFC4473F)],
  [Color(0xFF5AA2E8), Color(0xFF2F62B8)],
  [Color(0xFFA98BF0), Color(0xFF6A4FC4)],
  [Color(0xFFD76FA8), Color(0xFF9B3D78)],
  [Color(0xFF8FCF6B), Color(0xFF3F8F3A)],
  [Color(0xFF7B8790), Color(0xFF3E4A57)],
  [Color(0xFFF0D36A), Color(0xFFC49A1D)],
  [Color(0xFF2B2F36), Color(0xFF0F1216)],
];
List<Color> pal(int i) => palettes[(i < 0 || i >= palettes.length) ? 0 : i];

const iconChoices = <String, IconData>{
  'photo': Icons.photo_outlined,
  'apps': Icons.apps_rounded,
  'doc': Icons.description_outlined,
  'folder': Icons.folder_outlined,
  'globe': Icons.public,
  'ai': Icons.auto_awesome,
  'mail': Icons.mail_outline,
  'cal': Icons.calendar_today_outlined,
  'cam': Icons.photo_camera_outlined,
  'music': Icons.music_note_outlined,
  'map': Icons.map_outlined,
  'note': Icons.sticky_note_2_outlined,
  'down': Icons.download_outlined,
  'video': Icons.movie_outlined,
  'drive': Icons.storage_outlined,
  'image': Icons.image_outlined,
  'chat': Icons.chat_bubble_outline,
  'lang': Icons.translate,
  'edit': Icons.edit_outlined,
  'idea': Icons.lightbulb_outline,
  'search': Icons.search,
  'news': Icons.newspaper,
  'sun': Icons.wb_sunny_outlined,
  'star': Icons.star_outline,
  'home': Icons.home_outlined,
  'heart': Icons.favorite_border,
  'bolt': Icons.bolt,
  'bank': Icons.account_balance_outlined,
  'phone': Icons.phone_outlined,
  'cart': Icons.shopping_cart_outlined,
  'game': Icons.sports_esports_outlined,
  'car': Icons.directions_car_outlined,
  'gym': Icons.fitness_center,
  'shield': Icons.shield_outlined,
  'screen': Icons.desktop_windows_outlined,
};
IconData iconFor(String k) => iconChoices[k] ?? Icons.star_outline;

// ---------- Utilidades de archivos ----------
String baseName(String path) {
  final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return p.substring(p.lastIndexOf('/') + 1);
}

String extOf(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0 || i == name.length - 1) return '';
  return name.substring(i + 1).toLowerCase();
}

String fmtSize(int b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${s.replaceAll('.', ',')} ${u[i]}';
}

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';

const imgExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
const audExt = {'mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac', 'opus'};
const vidExt = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp'};
const apkExt = {'apk', 'xapk', 'exe', 'msi'};
const docTypes = <String, (String, Color)>{
  'pdf': ('PDF', Color(0xFFD4473B)),
  'doc': ('DOC', Color(0xFF2F62B8)),
  'docx': ('DOC', Color(0xFF2F62B8)),
  'odt': ('DOC', Color(0xFF2F62B8)),
  'rtf': ('DOC', Color(0xFF2F62B8)),
  'xls': ('XLS', Color(0xFF1F8A52)),
  'xlsx': ('XLS', Color(0xFF1F8A52)),
  'ods': ('XLS', Color(0xFF1F8A52)),
  'csv': ('CSV', Color(0xFF1F8A52)),
  'ppt': ('PPT', Color(0xFFD9782B)),
  'pptx': ('PPT', Color(0xFFD9782B)),
  'txt': ('TXT', Color(0xFF6C7A89)),
  'md': ('TXT', Color(0xFF6C7A89)),
  'zip': ('ZIP', Color(0xFF8A6D3B)),
  'rar': ('ZIP', Color(0xFF8A6D3B)),
  '7z': ('ZIP', Color(0xFF8A6D3B)),
};
const recentDocExt = {'pdf', 'doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'ods', 'csv', 'ppt', 'pptx', 'txt', 'md'};

/// Icono de un archivo o carpeta, con miniatura si es una imagen.
Widget fileTile(String name, bool isDir, double s, {String? path}) {
  if (isDir) {
    return Tile(size: s, colors: const [Color(0xFF6FB0EE), Color(0xFF2F62B8)], icon: Icons.folder_rounded, shadow: false);
  }
  final e = extOf(name);
  if (imgExt.contains(e) && path != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * app.radius),
      child: Image.file(File(path),
          width: s,
          height: s,
          fit: BoxFit.cover,
          cacheWidth: (s * 2.5).round(),
          errorBuilder: (_, __, ___) => Tile(size: s, colors: pal(0), icon: Icons.image_outlined, shadow: false)),
    );
  }
  if (audExt.contains(e)) return Tile(size: s, colors: pal(5), icon: Icons.music_note_outlined, shadow: false);
  if (vidExt.contains(e)) return Tile(size: s, colors: pal(2), icon: Icons.movie_outlined, shadow: false);
  if (imgExt.contains(e)) return Tile(size: s, colors: pal(0), icon: Icons.image_outlined, shadow: false);
  if (apkExt.contains(e)) return Tile(size: s, colors: pal(7), icon: Icons.android, shadow: false);
  final t = docTypes[e];
  final label = t?.$1 ?? (e.isEmpty ? '?' : e.toUpperCase().substring(0, e.length > 4 ? 4 : e.length));
  final color = t?.$2 ?? const Color(0xFF6C7A89);
  return Container(
    width: s,
    height: s,
    decoration: BoxDecoration(color: const Color(0xFFF1EFE8), borderRadius: BorderRadius.circular(s * app.radius)),
    child: Stack(alignment: Alignment.center, children: [
      Positioned(top: s * .14, child: Icon(Icons.description_outlined, color: const Color(0xFF5D6B68), size: s * .42)),
      Positioned(
        bottom: s * .12,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s * .07, vertical: 1),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: TextStyle(color: Colors.white, fontSize: s * .19, fontWeight: FontWeight.w700, height: 1.1)),
        ),
      ),
    ]),
  );
}

// ---------- Piezas visuales ----------
class Tile extends StatelessWidget {
  const Tile({super.key, required this.size, this.colors, this.icon, this.child, this.shadow = true});
  final double size;
  final List<Color>? colors;
  final IconData? icon;
  final Widget? child;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? palettes[0];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * app.radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 6))] : null,
      ),
      child: child ?? Icon(icon ?? Icons.star_outline, color: Colors.white, size: size * .46),
    );
  }
}

class DrawerTile extends StatelessWidget {
  const DrawerTile({super.key, required this.id, required this.size, this.shadow = true});
  final String id;
  final double size;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    final d = app.drawer(id);
    if (d.type == 'app' && d.pkg.isNotEmpty) return AppIcon(pkg: d.pkg, size: size);
    if (d.icon == '_grid') return FolderTile(items: d.items, size: size);
    return Tile(size: size, colors: pal(d.color), icon: iconFor(d.icon), shadow: shadow);
  }
}

/// Cajón con aspecto de carpeta: se ven en pequeño las primeras cuatro apps de dentro.
class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.items, required this.size});
  final List<Acceso> items;
  final double size;
  @override
  Widget build(BuildContext context) {
    final s = size;
    final pad = s * .12, gap = s * .07;
    final c = (s - pad * 2 - gap) / 2;
    Widget cell(int i) {
      if (i >= items.length) return SizedBox(width: c, height: c);
      final it = items[i];
      if (it.kind == 'app') return AppIcon(pkg: it.value, size: c);
      return Tile(size: c, colors: pal(it.color), icon: iconFor(it.icon), shadow: false);
    }

    return Container(
      width: s,
      height: s,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * app.radius),
        color: const Color(0x5C0C1C1E),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [cell(0), cell(1)]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [cell(2), cell(3)]),
      ]),
    );
  }
}

class AppIcon extends StatefulWidget {
  const AppIcon({super.key, required this.pkg, required this.size});
  final String pkg;
  final double size;
  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AppIcon old) {
    super.didUpdateWidget(old);
    if (old.pkg != widget.pkg) {
      bytes = null;
      _load();
    }
  }

  void _load() {
    final cache = app.iconCache;
    if (cache.containsKey(widget.pkg)) {
      bytes = cache[widget.pkg];
      return;
    }
    Native.icon(widget.pkg).then((b) {
      cache[widget.pkg] = b;
      if (mounted) setState(() => bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final b = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * app.radius),
      child: b == null
          ? Container(width: s, height: s, color: kSheet2)
          : Image.memory(b, width: s, height: s, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
    );
  }
}

class PhotoThumb extends StatefulWidget {
  const PhotoThumb({super.key, required this.asset, required this.size, this.rounded = true});
  final PhotoItem asset;
  final double size;
  final bool rounded;
  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  Uint8List? bytes;

  @override
  void initState() {
    super.initState();
    final a = widget.asset.asset;
    if (a == null) return; // En Windows la miniatura sale directamente del archivo.
    final cache = app.thumbCache;
    final id = a.id;
    if (cache.containsKey(id)) {
      bytes = cache[id];
    } else {
      a.thumbnailDataWithSize(const ThumbnailSize(240, 240)).then((b) {
        cache[id] = b;
        if (mounted) setState(() => bytes = b);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final b = bytes;
    final path = widget.asset.path;
    final Widget img;
    if (path != null) {
      img = Image.file(File(path),
          width: s,
          height: s,
          fit: BoxFit.cover,
          cacheWidth: 260,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(width: s, height: s, color: kSheet2));
    } else if (b == null) {
      img = Container(width: s, height: s, color: kSheet2);
    } else {
      img = Image.memory(b, width: s, height: s, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (!widget.rounded) return img;
    return ClipRRect(borderRadius: BorderRadius.circular(s * app.radius), child: img);
  }
}

class WallPreset {
  const WallPreset(this.name, this.colors, this.glow, this.glowAt);
  final String name;
  final List<Color> colors;
  final Color glow;
  final Alignment glowAt;
}

const wallPresets = <String, WallPreset>{
  'laguna': WallPreset('Laguna', [Color(0xFF16383A), Color(0xFF0F2A2E)], Color(0xFFE0A458), Alignment(.8, -.9)),
  'alba': WallPreset('Alba', [Color(0xFF2A2346), Color(0xFF7A4A6C), Color(0xFFD4836A)], Color(0xFFF6B26B), Alignment(0, 1.2)),
  'noche': WallPreset('Noche', [Color(0xFF1D2B5A), Color(0xFF070B1D)], Color(0xFF6B8CFF), Alignment(0, -1.2)),
  'bosque': WallPreset('Bosque', [Color(0xFF24452C), Color(0xFF0D1F14)], Color(0xFFBEDC8C), Alignment(-.7, -.8)),
  'calima': WallPreset('Calima', [Color(0xFFC9A074), Color(0xFF8A5A3C), Color(0xFF4F3324)], Color(0xFFFFF0D2), Alignment(.5, -.6)),
  'grafito': WallPreset('Grafito', [Color(0xFF2A2D33), Color(0xFF121418)], Color(0xFFFFFFFF), Alignment(-.5, -.7)),
  'mar': WallPreset('Mar', [Color(0xFF1B6FA3), Color(0xFF0B3556), Color(0xFF061C30)], Color(0xFF8CD2FF), Alignment(0, -1.1)),
};

class WallPreview extends StatelessWidget {
  const WallPreview({super.key, required this.preset});
  final WallPreset preset;
  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
          decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: preset.colors))),
      DecoratedBox(
          decoration: BoxDecoration(
              gradient: RadialGradient(
                  center: preset.glowAt,
                  radius: 1.1,
                  colors: [preset.glow.withValues(alpha: .26), preset.glow.withValues(alpha: 0)]))),
    ]);
  }
}

int _wallPx(BuildContext context) {
  final m = MediaQuery.of(context);
  final side = max(m.size.width, m.size.height) * m.devicePixelRatio;
  return (side * 1.3).round().clamp(800, 4096);
}

class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key});
  @override
  Widget build(BuildContext context) {
    final f = app.wallpaperFile;
    if (f != null && File(f).existsSync()) {
      return Stack(fit: StackFit.expand, children: [
        Image(
          // Se decodifica al tamaño de la pantalla (no a los megapíxeles de la foto),
          // así cada fotograma mueve mucha menos imagen.
          image: ResizeImage(FileImage(File(f)), width: _wallPx(context), height: _wallPx(context), policy: ResizeImagePolicy.fit),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
        Container(color: Colors.black.withValues(alpha: .22)),
      ]);
    }
    return WallPreview(preset: wallPresets[app.wallpaper] ?? wallPresets['laguna']!);
  }
}

/// Abre una hoja inferior a pantalla casi completa con su propio sistema de avisos.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder, {double height = .9}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: height,
      child: ScaffoldMessenger(
        child: Scaffold(backgroundColor: Colors.transparent, body: Builder(builder: builder)),
      ),
    ),
  );
}

void toast(BuildContext context, String msg) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: kSheet2,
    duration: const Duration(seconds: 3),
  ));
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.id, required this.subtitle, this.actions = const []});
  final String id;
  final String subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      child: Row(children: [
        DrawerTile(id: id, size: 40, shadow: false),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.drawer(id).name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: kDim)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

/// Selector de color e icono reutilizable.
class IconColorPicker extends StatelessWidget {
  const IconColorPicker({super.key, required this.icon, required this.color, required this.onIcon, required this.onColor});
  final String icon;
  final int color;
  final ValueChanged<String> onIcon;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Color', style: TextStyle(fontSize: 12, color: kDim)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < palettes.length; i++)
          GestureDetector(
            onTap: () => onColor(i),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: palettes[i]),
                border: Border.all(color: i == color ? kInk : Colors.transparent, width: 2),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      const Text('Icono', style: TextStyle(fontSize: 12, color: kDim)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in iconChoices.entries)
          GestureDetector(
            onTap: () => onIcon(e.key),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kSheet2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: e.key == icon ? kGlow : Colors.transparent, width: 2),
              ),
              child: Icon(e.value, size: 21, color: kInk),
            ),
          ),
      ]),
    ]);
  }
}
