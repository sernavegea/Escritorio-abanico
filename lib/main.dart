import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desk.dart';
import 'editor.dart';
import 'headmouse.dart';
import 'menu.dart';
import 'search.dart';
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
    if (call.method == 'notifs') {
      app.setNotifs((call.arguments as List?) ?? const []);
      return null;
    }
    if (call.method == 'home') {
      closeMenus();
      navKey.currentState?.popUntil((r) => r.isFirst);
    }
    return null;
  });
  // Pase lo que pase al cargar la configuración, el escritorio tiene que aparecer (nunca pantalla negra).
  try {
    await app.init().timeout(const Duration(seconds: 6));
  } catch (_) {}
  try {
    await head.init(navKey).timeout(const Duration(seconds: 3));
  } catch (_) {}
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
      builder: (context, child) => HeadLayer(child: child ?? const SizedBox.shrink()),
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
  final deskKey = GlobalKey<DeskAreaState>();

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
      app.loadNotifs();
      if (app.forceRefresh || DateTime.now().difference(lastRefresh).inSeconds > 20) {
        app.forceRefresh = false;
        lastRefresh = DateTime.now();
        app.refreshAll();
      }
    } else if (state == AppLifecycleState.paused) {
      closeMenus();
      if (editing) setState(() => editing = false);
    }
  }

  void _startEditing() {
    closeMenus();
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
        if (didPop) return;
        if (iconMenu.isOpen) {
          iconMenu.close();
        } else if (editing) {
          setState(() => editing = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) => Stack(children: [
            Positioned.fill(child: RepaintBoundary(child: Wallpaper())),
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
                        onPressed: () => addToDesk(context, page: deskKey.currentState?.page ?? 0),
                      ),
                      const SizedBox(width: 6),
                      FilledButton(onPressed: () => setState(() => editing = false), child: const Text('Hecho')),
                    ] else ...[
                      IconButton(
                        tooltip: 'Buscar apps',
                        style: IconButton.styleFrom(backgroundColor: const Color(0x660C1C1E)),
                        icon: const Icon(Icons.search, color: kInk),
                        onPressed: () => openAppSearch(context),
                      ),
                      const SizedBox(width: 6),
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
                  // Deslizar hacia arriba en el escritorio abre el buscador de apps.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragEnd: (d) {
                      if (!editing && (d.primaryVelocity ?? 0) < -250) openAppSearch(context);
                    },
                    child: DeskArea(key: deskKey, editing: editing, onEditRequest: _startEditing),
                  ),
                ),
                if (editing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14, left: 16, right: 16),
                    child: Text(
                      'Arrastra a otra casilla o a la barra · Toca para editar · × para quitar',
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
}
