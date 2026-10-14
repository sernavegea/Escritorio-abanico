import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    }
  }

  static const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${two(now.hour)}:${two(now.minute)}',
                            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w300, height: 1, shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
                        const SizedBox(height: 4),
                        Text('${_days[now.weekday - 1]}, ${now.day} de ${_months[now.month - 1]}',
                            style: const TextStyle(fontSize: 14, color: kInk, shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
                      ]),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Personalizar',
                        style: IconButton.styleFrom(backgroundColor: const Color(0x660C1C1E)),
                        icon: const Icon(Icons.tune, color: kInk),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
                      ),
                    ]),
                  ),
                  Expanded(child: Center(child: _grid(context))),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Mantén pulsado para desplegar · Toca para abrir',
                        style: TextStyle(fontSize: 12, color: kDim, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
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
    final cols = w >= 900 ? 6 : 3;
    final gap = w >= 600 ? 44.0 : 26.0;
    return SizedBox(
      width: cols * cell + (cols - 1) * gap,
      child: Wrap(
        spacing: gap,
        runSpacing: 36,
        alignment: WrapAlignment.center,
        children: [for (final d in app.drawers) SizedBox(width: cell, child: DeskIcon(id: d.id))],
      ),
    );
  }
}

class DeskIcon extends StatefulWidget {
  const DeskIcon({super.key, required this.id});
  final String id;
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openDrawer(context, widget.id),
      onLongPressStart: (_) => fan.show(
        context: context,
        drawerId: widget.id,
        tileCenter: _center(),
        items: buildFanEntries(context, widget.id),
        onCore: () => openDrawer(context, widget.id),
      ),
      onLongPressMoveUpdate: (e) => fan.hover(e.globalPosition),
      onLongPressEnd: (_) => fan.release(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DrawerTile(key: key, id: widget.id, size: app.iconSize),
        const SizedBox(height: 9),
        Text(d.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
      ]),
    );
  }
}
