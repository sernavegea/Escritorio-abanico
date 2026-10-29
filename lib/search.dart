// Buscador de apps: se abre deslizando hacia arriba en el escritorio.
import 'package:flutter/material.dart';

import 'menu.dart';
import 'state.dart';
import 'ui.dart';

String _plain(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

Future<void> openAppSearch(BuildContext context) {
  closeMenus();
  return Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const AppSearchPage(),
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class AppSearchPage extends StatefulWidget {
  const AppSearchPage({super.key});
  @override
  State<AppSearchPage> createState() => _AppSearchPageState();
}

class _AppSearchPageState extends State<AppSearchPage> {
  final ctrl = TextEditingController();
  String q = '';

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  List<AppEntry> _results() {
    final all = app.recentApps();
    if (q.trim().isEmpty) return all;
    final k = _plain(q.trim());
    final starts = <AppEntry>[], words = <AppEntry>[], contains = <AppEntry>[];
    for (final a in all) {
      final l = _plain(a.label);
      if (l.startsWith(k)) {
        starts.add(a);
      } else if (l.split(RegExp(r'[\s\-_.]+')).any((w) => w.startsWith(k))) {
        words.add(a);
      } else if (l.contains(k) || a.pkg.toLowerCase().contains(k)) {
        contains.add(a);
      }
    }
    return [...starts, ...words, ...contains];
  }

  void _launch(AppEntry a) {
    Navigator.of(context).pop();
    app.launchApp(a.pkg);
  }

  void _web() {
    final t = q.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop();
    app.openUrl('https://www.google.com/search?q=${Uri.encodeQueryComponent(t)}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = _results();
        return Scaffold(
          backgroundColor: kExBg.withValues(alpha: .97),
          body: SafeArea(
            child: GestureDetector(
              // Deslizar hacia abajo cierra el buscador.
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
              },
              child: Column(children: [
                Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => q = v),
                    onSubmitted: (_) {
                      if (list.isNotEmpty) {
                        _launch(list.first);
                      } else {
                        _web();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar apps',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                ctrl.clear();
                                q = '';
                              }),
                            ),
                    ),
                  ),
                ),
                if (q.trim().isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.travel_explore, color: kGlow),
                    title: Text('Buscar «${q.trim()}» en Internet'),
                    onTap: _web,
                  ),
                if (q.trim().isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 4, 18, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Usadas hace poco primero · mantén pulsada una app para ver sus opciones',
                          style: TextStyle(color: kDim, fontSize: 12)),
                    ),
                  ),
                Expanded(
                  child: !app.appsLoaded
                      ? const Center(child: CircularProgressIndicator())
                      : list.isEmpty
                          ? const Center(child: Text('Ninguna app coincide', style: TextStyle(color: kDim)))
                          : LayoutBuilder(builder: (context, box) {
                              final cols = (box.maxWidth / 92).floor().clamp(4, 10);
                              return GridView.builder(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(10, 6, 10, 24),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: .82),
                                itemCount: list.length,
                                itemBuilder: (context, i) {
                                  final a = list[i];
                                  return Builder(
                                    builder: (cellCtx) => InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => _launch(a),
                                      onLongPress: () => showAppMenu(cellCtx, a),
                                      onSecondaryTap: () => showAppMenu(cellCtx, a),
                                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        AppIcon(pkg: a.pkg, size: 52),
                                        const SizedBox(height: 6),
                                        Text(a.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 12)),
                                      ]),
                                    ),
                                  );
                                },
                              );
                            }),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
