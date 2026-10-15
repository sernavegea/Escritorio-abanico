import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'fan.dart';
import 'native.dart';
import 'pages.dart';
import 'settings.dart';
import 'state.dart';
import 'ui.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // El botón de inicio de Android con el escritorio ya abierto: cerrar todo y volver.
  Native.ch.setMethodCallHandler((call) async {
    if (call.method == 'home') {
      fan.close();
      navKey.currentState?.popUntil((r) => r.isFirst);
    }
    return null;
  });
  await app.init();
  runApp(const AbanicoApp());
}

class AbanicoApp extends StatelessWidget {
  const AbanicoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: kGlow, brightness: Brightness.dark).copyWith(
      primary: kGlow,
      onPrimary: const Color(0xFF1D1407),
      surface: kSheet,
    );
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Abanico',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: kExBg,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kField,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kLine)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGlow, width: 2)),
          isDense: true,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Timer timer;
  DateTime now = DateTime.now();
  DateTime lastRefresh = DateTime.now();
  bool editing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => now = DateTime.now()));
  }

  @override
  void dispose() {
    timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => now = DateTime.now());
      if (DateTime.now().difference(lastRefresh).inSeconds > 20) {
        lastRefresh = DateTime.now();
        app.refreshAll();
      }
    } else if (state == AppLifecycleState.paused) {
      fan.close();
      if (editing) setState(() => editing = false);
    }
  }

  void _startEditing() {
    fan.close();
    HapticFeedback.mediumImpact();
    setState(() => editing = true);
  }

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && editing) setState(() => editing = false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Stack(children: [
            Positioned.fill(child: Wallpaper()),
            SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (!await Native.openAlarms() && context.mounted) toast(context, 'No se ha encontrado la app de reloj');
                          },
                          child: Text('${two(now.hour)}:${two(now.minute)}',
                              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w300, height: 1, shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (!await Native.openCalendar() && context.mounted) toast(context, 'No se ha encontrado la app de calendario');
                          },
                          child: Text('${_days[now.weekday - 1]}, ${now.day} de ${_months[now.month - 1]}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: kInk, shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
                        ),
                      ]),
                    ),
                    if (editing) ...[
                      IconButton(
                        tooltip: 'Añadir',
                        style: IconButton.styleFrom(backgroundColor: const Color(0x660C1C1E)),
                        icon: const Icon(Icons.add, color: kInk),
                        onPressed: () => addToDesk(context),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(onPressed: () => setState(() => editing = false), child: const Text('Hecho')),
                    ] else ...[
                      IconButton(
                        tooltip: 'Editar escritorio',
                        style: IconButton.styleFrom(backgroundColor: const Color(0x660C1C1E)),
                        icon: const Icon(Icons.edit_outlined, color: kInk),
                        onPressed: _startEditing,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Personalizar',
                        style: IconButton.styleFrom(backgroundColor: const Color(0x660C1C1E)),
                        icon: const Icon(Icons.tune, color: kInk),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                      ),
                    ],
                  ]),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight - 40),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (final w in app.widgets) _WidgetBox(key: ValueKey('w${w.id}'), cfg: w, editing: editing),
                          if (app.widgets.isNotEmpty) const SizedBox(height: 12),
                          _grid(context),
                        ]),
                      ),
                    ),
                  ),
                ),
                if (editing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14, left: 16, right: 16),
                    child: Text(
                      'Arrastra para mover · Toca para editar · × para quitar',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: kDim, shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context) {
    final cell = app.iconSize + 28;
    final w = MediaQuery.of(context).size.width;
    final gap = w >= 600 ? 44.0 : 26.0;
    final fit = ((w - 32 + gap) / (cell + gap)).floor().clamp(2, 8);
    final cols = w >= 900 ? fit.clamp(2, 6) : fit.clamp(2, 3);
    final items = app.drawers;
    return SizedBox(
      width: cols * cell + (cols - 1) * gap,
      child: Wrap(
        spacing: gap,
        runSpacing: 30,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              key: ValueKey(items[i].id),
              width: cell,
              child: editing ? _EditIcon(id: items[i].id, index: i) : DeskIcon(id: items[i].id, onEditRequest: _startEditing),
            ),
          if (editing)
            SizedBox(
              width: cell,
              child: GestureDetector(
                onTap: () => addToDesk(context),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: app.iconSize,
                    height: app.iconSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(app.iconSize * app.radius),
                      border: Border.all(color: kInk.withValues(alpha: .5), width: 2),
                      color: Colors.black.withValues(alpha: .2),
                    ),
                    child: const Icon(Icons.add, color: kInk, size: 30),
                  ),
                  const SizedBox(height: 9),
                  const Text('Añadir', style: TextStyle(fontSize: 13, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                ]),
              ),
            ),
          if (!editing && items.isEmpty)
            TextButton.icon(onPressed: _startEditing, icon: const Icon(Icons.add), label: const Text('Añadir iconos')),
        ],
      ),
    );
  }
}

class _IconFace extends StatelessWidget {
  const _IconFace({required this.id, this.tileKey});
  final String id;
  final Key? tileKey;
  @override
  Widget build(BuildContext context) {
    final d = app.drawer(id);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DrawerTile(key: tileKey, id: id, size: app.iconSize),
      const SizedBox(height: 9),
      Text(d.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
    ]);
  }
}

class DeskIcon extends StatefulWidget {
  const DeskIcon({super.key, required this.id, required this.onEditRequest});
  final String id;
  final VoidCallback onEditRequest;
  @override
  State<DeskIcon> createState() => _DeskIconState();
}

class _DeskIconState extends State<DeskIcon> {
  final key = GlobalKey();

  Offset _center() {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final d = app.drawer(widget.id);
    final isApp = d.type == 'app';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openDrawer(context, widget.id),
      onLongPressStart: (_) {
        if (isApp) {
          widget.onEditRequest();
          return;
        }
        fan.show(
          context: context,
          drawerId: widget.id,
          tileCenter: _center(),
          items: buildFanEntries(context, widget.id),
          onCore: () => openDrawer(context, widget.id),
        );
      },
      onLongPressMoveUpdate: (e) {
        if (!isApp) fan.hover(e.globalPosition);
      },
      onLongPressEnd: (_) {
        if (!isApp) fan.release();
      },
      child: _IconFace(id: widget.id, tileKey: key),
    );
  }
}

/// Icono en modo edición: tiembla, se arrastra para reordenar, se toca para editar y tiene × para quitar.
class _EditIcon extends StatefulWidget {
  const _EditIcon({required this.id, required this.index});
  final String id;
  final int index;
  @override
  State<_EditIcon> createState() => _EditIconState();
}

class _EditIconState extends State<_EditIcon> with SingleTickerProviderStateMixin {
  late final AnimationController wig = AnimationController(vsync: this, duration: Duration(milliseconds: 240 + (widget.id.hashCode % 5) * 20))
    ..repeat(reverse: true);

  @override
  void dispose() {
    wig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = app.drawer(widget.id);
    final face = _IconFace(id: widget.id);
    return DragTarget<String>(
      onWillAcceptWithDetails: (det) => det.data != widget.id,
      onAcceptWithDetails: (det) {
        HapticFeedback.selectionClick();
        app.moveDrawerTo(det.data, widget.index);
      },
      builder: (context, cand, _) => LongPressDraggable<String>(
        data: widget.id,
        delay: const Duration(milliseconds: 120),
        hapticFeedbackOnStart: true,
        feedback: Material(type: MaterialType.transparency, child: SizedBox(width: app.iconSize + 28, child: Transform.scale(scale: 1.1, child: face))),
        childWhenDragging: Opacity(opacity: .25, child: face),
        child: Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: () => editDrawer(context, d),
            child: AnimatedBuilder(
              animation: wig,
              builder: (_, child) => Transform.rotate(angle: (wig.value - .5) * .07, child: child),
              child: AnimatedScale(
                scale: cand.isNotEmpty ? 1.12 : 1,
                duration: const Duration(milliseconds: 120),
                child: face,
              ),
            ),
          ),
          Positioned(
            top: -8,
            left: 2,
            child: GestureDetector(
              onTap: () => removeFromDesk(context, d),
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFC4473F),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Un widget de Android dentro del escritorio. En modo edición se puede quitar, subir, bajar y cambiar de alto.
class _WidgetBox extends StatelessWidget {
  const _WidgetBox({super.key, required this.cfg, required this.editing});
  final WidgetCfg cfg;
  final bool editing;

  static const _heights = [110.0, 160.0, 220.0, 300.0, 380.0];

  @override
  Widget build(BuildContext context) {
    final w = min(MediaQuery.of(context).size.width - 32, 620.0);
    final view = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: w,
        height: cfg.height,
        child: AndroidView(
          key: ValueKey('av${cfg.id}-${cfg.height.round()}'),
          viewType: 'abanico/widget',
          creationParams: {'id': cfg.id, 'w': w.round(), 'h': cfg.height.round()},
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
    if (!editing) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: view);
    }
    final i = app.widgets.indexOf(cfg);
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {Color color = kInk}) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: const Color(0xCC0C1C1E)),
          icon: Icon(icon, color: onTap == null ? kDim : color, size: 20),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Stack(children: [
        IgnorePointer(child: Opacity(opacity: .75, child: view)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGlow, width: 2)),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          right: 8,
          child: Row(children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xCC0C1C1E), borderRadius: BorderRadius.circular(10)),
                child: Text(cfg.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
            ),
            const Spacer(),
            btn(Icons.arrow_upward, 'Subir', i > 0 ? () => app.moveWidget(cfg, -1) : null),
            btn(Icons.arrow_downward, 'Bajar', i < app.widgets.length - 1 ? () => app.moveWidget(cfg, 1) : null),
            btn(Icons.height, 'Cambiar alto', () {
              final k = _heights.indexWhere((h) => h > cfg.height + 1);
              cfg.height = k < 0 ? _heights.first : _heights[k];
              app.changed();
            }),
            btn(Icons.close, 'Quitar', () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kSheet,
                  title: Text('¿Quitar «${cfg.label}»?'),
                  content: const Text('Podrás volver a añadirlo con el botón +.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Quitar')),
                  ],
                ),
              );
              if (ok == true) app.removeWidget(cfg);
            }, color: kDanger),
          ]),
        ),
      ]),
    );
  }
}
