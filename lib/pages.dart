import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:photo_manager/photo_manager.dart';

import 'explorer.dart';
import 'fan.dart';
import 'native.dart';
import 'state.dart';
import 'ui.dart';

// ======================================================================
// Abrir cajones y construir el abanico de cada uno
// ======================================================================

void openDrawer(BuildContext context, String id) {
  switch (id) {
    case 'apps':
      showSheet(context, (_) => const AppsPage());
      break;
    case 'fotos':
      showSheet(context, (_) => const PhotosPage());
      break;
    case 'docs':
      showSheet(context, (_) => const DocsPage());
      break;
    case 'files':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExplorerPage()));
      break;
    case 'net':
      showSheet(context, (_) => const LinksPage());
      break;
    case 'ia':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiPage()));
      break;
  }
}

Future<void> openFile(BuildContext context, String path) async {
  final r = await OpenFilex.open(path);
  if (r.type != ResultType.done && context.mounted) {
    toast(context, r.type == ResultType.noAppToOpen ? 'No hay ninguna app para abrir este archivo' : 'No se ha podido abrir: ${r.message}');
  }
}

List<FanEntry> buildFanEntries(BuildContext context, String id) {
  void all() => openDrawer(context, id);
  switch (id) {
    case 'apps':
      return withMore([
        for (final a in app.recentApps())
          FanEntry(a.label, (s) => AppIcon(pkg: a.pkg, size: s), () => app.launchApp(a.pkg)),
      ], all);
    case 'fotos':
      if (!app.photosAllowed) {
        return [FanEntry('Permitir', (s) => Tile(size: s, colors: pal(0), icon: Icons.lock_open), all)];
      }
      final photos = app.recentPhotos;
      final many = photos.length > fanMax;
      final n = many ? fanMax - 1 : photos.length;
      return [
        for (var i = 0; i < n; i++)
          FanEntry(photos[i].title ?? 'Foto', (s) => PhotoThumb(asset: photos[i], size: s),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(index: i)))),
        if (many)
          FanEntry(
              'Ver todo',
              (s) => Tile(
                  size: s,
                  colors: pal(7),
                  child: Text('+${photos.length - n}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s * .24))),
              all),
      ];
    case 'docs':
      if (!app.filesAllowed) {
        return [FanEntry('Permitir', (s) => Tile(size: s, colors: pal(2), icon: Icons.lock_open), all)];
      }
      return withMore([
        for (final f in app.recentDocs)
          FanEntry(baseName(f.path), (s) => fileTile(baseName(f.path), false, s), () => openFile(context, f.path)),
      ], all);
    case 'files':
      return withMore([
        for (final p in app.recentPins())
          FanEntry(p.name, (s) => Tile(size: s, colors: const [Color(0xFF6FB0EE), Color(0xFF2F62B8)], icon: iconFor(p.icon)), () {
            app.usePin(p.path);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExplorerPage(start: p.path)));
          }),
      ], all);
    case 'net':
      return withMore([
        for (final l in app.recentLinks()) FanEntry(l.name, (s) => Tile(size: s, colors: pal(l.color), icon: iconFor(l.icon)), () => app.openLink(l)),
      ], all);
    case 'ia':
      return [
        for (final m in aiModes.entries)
          FanEntry(m.key, (s) => Tile(size: s, colors: pal(m.value.$2), icon: iconFor(m.value.$1)),
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiPage(mode: m.key)))),
      ];
  }
  return [];
}

int _cols(double width, double cell) => (width / cell).floor().clamp(3, 12);

// ======================================================================
// Apps
// ======================================================================
class AppsPage extends StatefulWidget {
  const AppsPage({super.key});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = q.isEmpty ? app.apps : app.apps.where((a) => a.label.toLowerCase().contains(q.toLowerCase())).toList();
        final recent = app.recentApps().where((a) => app.appUse.containsKey(a.pkg)).take(5).toList();
        return Column(children: [
          SheetHeader(id: 'apps', subtitle: '${app.apps.length} apps instaladas'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => q = v.trim()),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar app'),
            ),
          ),
          Expanded(
            child: !app.appsLoaded
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, c) {
                    final cols = _cols(c.maxWidth - 24, 88);
                    return CustomScrollView(slivers: [
                      if (q.isEmpty && recent.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                            child: Padding(padding: EdgeInsets.fromLTRB(18, 6, 18, 6), child: Text('RECIENTES', style: TextStyle(fontSize: 11, letterSpacing: 1, color: kDim)))),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          sliver: SliverGrid.count(crossAxisCount: cols, childAspectRatio: .78, children: [for (final a in recent) _appCell(a)]),
                        ),
                        const SliverToBoxAdapter(
                            child: Padding(padding: EdgeInsets.fromLTRB(18, 10, 18, 6), child: Text('TODAS', style: TextStyle(fontSize: 11, letterSpacing: 1, color: kDim)))),
                      ],
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        sliver: SliverGrid.count(crossAxisCount: cols, childAspectRatio: .78, children: [for (final a in list) _appCell(a)]),
                      ),
                    ]);
                  }),
          ),
        ]);
      },
    );
  }

  Widget _appCell(AppEntry a) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await app.launchApp(a.pkg);
        if (mounted) Navigator.of(context).pop();
      },
      onLongPress: () => Native.appInfo(a.pkg),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AppIcon(pkg: a.pkg, size: 54),
          const SizedBox(height: 6),
          Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

// ======================================================================
// Fotos
// ======================================================================
class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final photos = app.recentPhotos;
        return Column(children: [
          SheetHeader(id: 'fotos', subtitle: app.photosAllowed ? 'Las ${photos.length} más recientes' : 'Sin permiso todavía'),
          Expanded(
            child: !app.photosAllowed
                ? _PermissionCard(
                    icon: Icons.photo_library_outlined,
                    text: 'Para ver tus fotos aquí, permite el acceso a la galería.',
                    button: 'Permitir acceso a fotos',
                    onTap: () => app.loadPhotos(),
                  )
                : LayoutBuilder(builder: (context, c) {
                    final cols = _cols(c.maxWidth, 110);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 3, crossAxisSpacing: 3),
                      itemCount: photos.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoViewer(index: i))),
                        child: LayoutBuilder(builder: (_, cc) => PhotoThumb(asset: photos[i], size: cc.maxWidth, rounded: false)),
                      ),
                    );
                  }),
          ),
        ]);
      },
    );
  }
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.index});
  final int index;
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController pc = PageController(initialPage: widget.index);
  late int cur = widget.index;

  Future<File?> _file() => app.recentPhotos[cur].file;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = app.recentPhotos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: Text('${cur + 1} de ${photos.length}', style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'Usar como fondo',
            icon: const Icon(Icons.wallpaper),
            onPressed: () async {
              final f = await _file();
              if (f == null) return;
              await app.setWallpaperFile(f);
              if (context.mounted) toast(context, 'Fondo de escritorio cambiado');
            },
          ),
          IconButton(
            tooltip: 'Abrir con otra app',
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final f = await _file();
              if (f != null && context.mounted) openFile(context, f.path);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: pc,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => cur = i),
        itemBuilder: (_, i) => _FullPhoto(asset: photos[i]),
      ),
    );
  }
}

class _FullPhoto extends StatefulWidget {
  const _FullPhoto({required this.asset});
  final AssetEntity asset;
  @override
  State<_FullPhoto> createState() => _FullPhotoState();
}

class _FullPhotoState extends State<_FullPhoto> {
  late final Future<File?> f = widget.asset.file;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: f,
      builder: (_, s) {
        final file = s.data;
        if (file == null) return const Center(child: CircularProgressIndicator());
        return InteractiveViewer(maxScale: 5, child: Center(child: Image.file(file, fit: BoxFit.contain)));
      },
    );
  }
}

// ======================================================================
// Documentos recientes
// ======================================================================
class DocsPage extends StatelessWidget {
  const DocsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final docs = app.recentDocs;
        return Column(children: [
          SheetHeader(
            id: 'docs',
            subtitle: app.filesAllowed ? '${docs.length} documentos, los más recientes primero' : 'Sin permiso todavía',
            actions: [IconButton(tooltip: 'Actualizar', icon: const Icon(Icons.refresh), onPressed: () => app.loadDocs())],
          ),
          Expanded(
            child: !app.filesAllowed
                ? _PermissionCard(
                    icon: Icons.folder_open,
                    text: 'Para ver tus documentos, permite el acceso a todos los archivos. Se abrirán los ajustes de Android: activa el permiso y vuelve.',
                    button: 'Permitir acceso a archivos',
                    onTap: Native.requestAllFiles,
                  )
                : docs.isEmpty
                    ? const Center(child: Text('No hay documentos en Descargas ni en Documentos', style: TextStyle(color: kDim)))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final f = docs[i];
                          final parent = baseName(f.parent.path);
                          final d = app.docDates[f.path];
                          return ListTile(
                            leading: fileTile(baseName(f.path), false, 42),
                            title: Text(baseName(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('$parent${d != null ? ' · ${fmtDate(d)}' : ''}', style: const TextStyle(color: kDim, fontSize: 12)),
                            onTap: () => openFile(context, f.path),
                            onLongPress: () => Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => ExplorerPage(start: f.parent.path))),
                          );
                        },
                      ),
          ),
        ]);
      },
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.icon, required this.text, required this.button, required this.onTap});
  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: kDim),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kDim, height: 1.4)),
          const SizedBox(height: 18),
          FilledButton(onPressed: onTap, child: Text(button)),
        ]),
      ),
    );
  }
}

// ======================================================================
// Internet
// ======================================================================
class LinksPage extends StatefulWidget {
  const LinksPage({super.key});
  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  bool edit = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final links = app.links;
        return Column(children: [
          SheetHeader(id: 'net', subtitle: '${links.length} accesos', actions: [
            TextButton(onPressed: () => setState(() => edit = !edit), child: Text(edit ? 'Hecho' : 'Editar')),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar en Google o escribir una web'),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isEmpty) return;
                final isUrl = !t.contains(' ') && t.contains('.');
                Native.openUrl(isUrl ? (t.startsWith('http') ? t : 'https://$t') : 'https://www.google.com/search?q=${Uri.encodeComponent(t)}');
              },
            ),
          ),
          if (edit)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Text('Toca un acceso para editarlo. Mantén pulsado y arrastra para reordenar.', style: TextStyle(color: kDim, fontSize: 12)),
            ),
          Expanded(
            child: edit
                ? ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: links.length + 1,
                    onReorder: (a, b) {
                      if (a >= links.length) return;
                      if (b > links.length) b = links.length;
                      if (b > a) b--;
                      final it = links.removeAt(a);
                      links.insert(b, it);
                      app.changed();
                    },
                    itemBuilder: (_, i) {
                      if (i == links.length) {
                        return ListTile(
                          key: const ValueKey('add'),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(border: Border.all(color: kLine, width: 2), borderRadius: BorderRadius.circular(40 * app.radius)),
                            child: const Icon(Icons.add, color: kDim),
                          ),
                          title: const Text('Añadir acceso'),
                          onTap: () => editLink(context, null),
                        );
                      }
                      final l = links[i];
                      return ListTile(
                        key: ObjectKey(l),
                        leading: Tile(size: 40, colors: pal(l.color), icon: iconFor(l.icon), shadow: false),
                        title: Text(l.name),
                        subtitle: Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 12)),
                        onTap: () => editLink(context, l),
                      );
                    },
                  )
                : LayoutBuilder(builder: (context, c) {
                    return GridView.count(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      crossAxisCount: _cols(c.maxWidth - 24, 88),
                      childAspectRatio: .8,
                      children: [
                        for (final l in links)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              app.openLink(l);
                              Navigator.of(context).pop();
                            },
                            onLongPress: () => editLink(context, l),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Tile(size: 54, colors: pal(l.color), icon: iconFor(l.icon)),
                              const SizedBox(height: 6),
                              Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => editLink(context, null),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(border: Border.all(color: kLine, width: 2), borderRadius: BorderRadius.circular(54 * app.radius)),
                              child: const Icon(Icons.add, color: kDim),
                            ),
                            const SizedBox(height: 6),
                            const Text('Añadir', style: TextStyle(fontSize: 12, color: kDim)),
                          ]),
                        ),
                      ],
                    );
                  }),
          ),
        ]);
      },
    );
  }
}

Future<void> editLink(BuildContext context, LinkItem? l) async {
  final isNew = l == null;
  final name = TextEditingController(text: l?.name ?? '');
  final url = TextEditingController(text: l?.url ?? 'https://');
  var icon = l?.icon ?? 'globe';
  var color = l?.color ?? 3;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Tile(size: 44, colors: pal(color), icon: iconFor(icon), shadow: false),
              const SizedBox(width: 12),
              Text(isNew ? 'Nuevo acceso' : 'Editar acceso', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Dirección web')),
            const SizedBox(height: 16),
            IconColorPicker(icon: icon, color: color, onIcon: (v) => set(() => icon = v), onColor: (v) => set(() => color = v)),
            const SizedBox(height: 20),
            Row(children: [
              if (!isNew)
                TextButton(
                  onPressed: () {
                    app.links.remove(l);
                    app.changed();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Quitar', style: TextStyle(color: kDanger)),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  var u = url.text.trim();
                  if (u.isEmpty || u == 'https://') return;
                  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
                  final n = name.text.trim().isEmpty ? Uri.tryParse(u)?.host ?? u : name.text.trim();
                  if (isNew) {
                    app.links.add(LinkItem(n, u, icon: icon, color: color, used: DateTime.now().millisecondsSinceEpoch));
                  } else {
                    l!.name = n;
                    l.url = u;
                    l.icon = icon;
                    l.color = color;
                  }
                  app.changed();
                  Navigator.of(ctx).pop();
                },
                child: Text(isNew ? 'Añadir' : 'Guardar'),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

// ======================================================================
// Asistente IA (Claude por API, con la clave del usuario)
// ======================================================================
class AiPage extends StatefulWidget {
  const AiPage({super.key, this.mode = 'Chat'});
  final String mode;
  @override
  State<AiPage> createState() => _AiPageState();
}

class _Msg {
  _Msg(this.me, this.text, {this.error = false});
  final bool me;
  final String text;
  final bool error;
}

class _AiPageState extends State<AiPage> {
  late String mode = widget.mode;
  final msgs = <_Msg>[];
  final input = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty || sending) return;
    if (app.apiKey.isEmpty) {
      await aiKeyDialog(context);
      if (app.apiKey.isEmpty) return;
    }
    setState(() {
      msgs.add(_Msg(true, t));
      input.clear();
      sending = true;
    });
    _toEnd();
    final history = mode == 'Chat'
        ? msgs.where((m) => !m.error).map((m) => {'role': m.me ? 'user' : 'assistant', 'content': m.text}).toList()
        : [
            {'role': 'user', 'content': t}
          ];
    try {
      final r = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {'x-api-key': app.apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
            body: jsonEncode({'model': app.model, 'max_tokens': 1500, 'system': aiModes[mode]!.$3, 'messages': history}),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (r.statusCode == 200) {
        final parts = (data['content'] as List).where((c) => (c as Map)['type'] == 'text').map((c) => (c as Map)['text'] as String);
        msgs.add(_Msg(false, parts.join('\n').trim()));
      } else {
        final err = (data['error'] is Map) ? (data['error'] as Map)['message'] : r.body;
        msgs.add(_Msg(false, 'Error ${r.statusCode}: $err', error: true));
      }
    } catch (e) {
      msgs.add(_Msg(false, 'No se ha podido conectar: $e', error: true));
    }
    if (mounted) setState(() => sending = false);
    _toEnd();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kExBg,
      appBar: AppBar(
        backgroundColor: kExBg,
        title: Row(children: [
          const DrawerTile(id: 'ia', size: 30, shadow: false),
          const SizedBox(width: 10),
          Text(app.drawer('ia').name),
        ]),
        actions: [
          IconButton(tooltip: 'Clave de API', icon: const Icon(Icons.key_outlined), onPressed: () => aiKeyDialog(context)),
          IconButton(tooltip: 'Borrar conversación', icon: const Icon(Icons.delete_sweep_outlined), onPressed: () => setState(msgs.clear)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final m in aiModes.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(iconFor(m.value.$1), size: 16),
                    label: Text(m.key),
                    selected: mode == m.key,
                    onSelected: (_) => setState(() => mode = m.key),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        app.apiKey.isEmpty
                            ? 'Para usar la IA, añade tu clave de API de Claude con el botón de la llave.'
                            : {
                                  'Chat': 'Pregunta lo que quieras.',
                                  'Traducir': 'Escribe o pega el texto que quieres traducir.',
                                  'Resumir': 'Pega un texto largo y te lo resumo.',
                                  'Corregir': 'Pega un texto y te lo devuelvo corregido.',
                                  'Ideas': '¿Sobre qué necesitas ideas?',
                                }[mode] ??
                                '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kDim, height: 1.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: msgs.length + (sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == msgs.length) {
                        return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
                      }
                      final m = msgs[i];
                      return Align(
                        alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
                        child: GestureDetector(
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: m.text));
                            toast(context, 'Texto copiado');
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
                            decoration: BoxDecoration(
                              color: m.me ? kGlow : (m.error ? const Color(0x33D4544A) : kSheet2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SelectableText(m.text, style: TextStyle(color: m.me ? const Color(0xFF1D1407) : kInk, height: 1.4, fontSize: 15)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: mode == 'Chat' ? 'Escribe tu pregunta' : 'Escribe o pega el texto'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send)),
            ]),
          ),
        ]),
      ),
    );
  }
}

Future<void> aiKeyDialog(BuildContext context) async {
  final key = TextEditingController(text: app.apiKey);
  final model = TextEditingController(text: app.model);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: kSheet,
      title: const Text('Conectar la IA'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pega tu clave de API de Claude. La consigues en console.anthropic.com → API Keys. Se guarda solo en este móvil.',
              style: TextStyle(color: kDim, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'Clave de API (sk-ant-...)')),
          const SizedBox(height: 10),
          TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            app.apiKey = key.text.trim();
            if (model.text.trim().isNotEmpty) app.model = model.text.trim();
            app.changed();
            Navigator.of(ctx).pop();
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
