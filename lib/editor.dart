import 'package:flutter/material.dart';

import 'explorer.dart';
import 'native.dart';
import 'pages.dart' show AiPage;
import 'state.dart';
import 'ui.dart';

// ======================================================================
// Accesos directos (contenido elegido de un abanico)
// ======================================================================

const _folderColors = [Color(0xFF6FB0EE), Color(0xFF2F62B8)];

Widget shortcutTile(Acceso s, double size) {
  switch (s.kind) {
    case 'app':
      return AppIcon(pkg: s.value, size: size);
    case 'folder':
      return Tile(size: size, colors: _folderColors, icon: iconFor(s.icon));
    default:
      return Tile(size: size, colors: pal(s.color), icon: iconFor(s.icon));
  }
}

void openShortcut(BuildContext context, Acceso s) {
  switch (s.kind) {
    case 'app':
      app.launchApp(s.value);
      break;
    case 'link':
      app.openUrl(s.value);
      break;
    case 'folder':
      app.usePin(s.value);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExplorerPage(start: s.value)));
      break;
    case 'ai':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiPage(mode: aiModes.containsKey(s.value) ? s.value : 'Chat')));
      break;
  }
}

String _kindLabel(String k) => const {'app': 'App', 'link': 'Web', 'folder': 'Carpeta', 'ai': 'IA'}[k] ?? '';

const _autoText = {
  'fotos': 'tus fotos, de la más nueva a la más antigua',
  'apps': 'las apps que más recientemente has abierto',
  'docs': 'tus documentos más recientes',
  'files': 'tus carpetas ancladas, las más usadas primero',
  'net': 'tus accesos web, los más usados primero',
  'ia': 'los modos del asistente',
};

// ======================================================================
// Cajón propio: lo que se ve al tocarlo
// ======================================================================
class CustomDrawerPage extends StatelessWidget {
  const CustomDrawerPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final d = app.drawer(id);
        final items = d.items;
        return Column(children: [
          SheetHeader(id: id, subtitle: items.length == 1 ? '1 acceso' : '${items.length} accesos', actions: [
            TextButton(onPressed: () => editDrawer(context, d), child: const Text('Editar')),
          ]),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Este cajón está vacío', style: TextStyle(color: kDim)),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: () => editDrawer(context, d), child: const Text('Añadir accesos')),
                    ]),
                  )
                : LayoutBuilder(builder: (context, c) {
                    return GridView.count(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      crossAxisCount: (c.maxWidth / 88).floor().clamp(3, 12),
                      childAspectRatio: .8,
                      children: [
                        for (final s in items)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.of(context).pop();
                              openShortcut(context, s);
                            },
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              shortcutTile(s, 54),
                              const SizedBox(height: 6),
                              Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
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

// ======================================================================
// Editor de un icono del escritorio
// ======================================================================
Future<void> editDrawer(BuildContext context, DrawerCfg d, {bool isNew = false}) async {
  final name = TextEditingController(text: d.name);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: .92,
      child: StatefulBuilder(builder: (ctx, set) {
        void touch() {
          app.changed();
          set(() {});
        }

        Future<void> add(Future<List<Acceso>> Function() picker) async {
          final got = await picker();
          if (got.isEmpty) return;
          d.items.addAll(got);
          touch();
        }

        final isApp = d.type == 'app';
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 4),
              child: Row(children: [
                DrawerTile(id: d.id, size: 44, shadow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(isNew ? 'Nuevo cajón' : (isApp ? 'Acceso a app' : 'Editar cajón'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Listo')),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
                TextField(
                  controller: name,
                  maxLength: 18,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  onChanged: (v) {
                    d.name = v.trim().isEmpty ? '·' : v.trim();
                    app.changed();
                  },
                ),
                if (!isApp) ...[
                  const SizedBox(height: 6),
                  IconColorPicker(
                    icon: d.icon,
                    color: d.color,
                    onIcon: (v) {
                      d.icon = v;
                      touch();
                    },
                    onColor: (v) {
                      d.color = v;
                      touch();
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text('CONTENIDO DEL ABANICO', style: TextStyle(fontSize: 12, letterSpacing: 1, color: kDim, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  if (d.builtin) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'auto', label: Text('Automático'), icon: Icon(Icons.history)),
                        ButtonSegment(value: 'custom', label: Text('Lo elijo yo'), icon: Icon(Icons.touch_app_outlined)),
                      ],
                      selected: {d.mode},
                      onSelectionChanged: (v) {
                        d.mode = v.first;
                        touch();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      d.mode == 'auto'
                          ? 'El abanico muestra ${_autoText[d.type] ?? 'lo más reciente'}.'
                          : 'El abanico muestra solo lo que pongas aquí, en este orden. Mantén pulsado y arrastra para reordenar.',
                      style: const TextStyle(color: kDim, fontSize: 13, height: 1.35),
                    ),
                  ] else
                    const Text('Mantén pulsado y arrastra para reordenar.', style: TextStyle(color: kDim, fontSize: 13)),
                  if (d.customFan) ...[
                    const SizedBox(height: 10),
                    if (d.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Todavía no hay nada. Añade apps, webs, carpetas o modos de IA.', style: TextStyle(color: kDim)),
                      )
                    else
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        onReorder: (a, b) {
                          if (b > a) b--;
                          final it = d.items.removeAt(a);
                          d.items.insert(b, it);
                          touch();
                        },
                        children: [
                          for (final s in d.items)
                            ListTile(
                              key: ObjectKey(s),
                              contentPadding: const EdgeInsets.only(left: 4, right: 0),
                              leading: shortcutTile(s, 38),
                              title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(_kindLabel(s.kind), style: const TextStyle(color: kDim, fontSize: 12)),
                              trailing: IconButton(
                                tooltip: 'Quitar',
                                icon: const Icon(Icons.remove_circle_outline, color: kDanger),
                                onPressed: () {
                                  d.items.remove(s);
                                  touch();
                                },
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ActionChip(
                        avatar: const Icon(Icons.apps_rounded, size: 18),
                        label: const Text('Apps'),
                        onPressed: () => add(() => pickApps(ctx, exclude: d.items.where((s) => s.kind == 'app').map((s) => s.value).toSet())),
                      ),
                      ActionChip(avatar: const Icon(Icons.public, size: 18), label: const Text('Web'), onPressed: () => add(() => pickLink(ctx))),
                      ActionChip(
                          avatar: const Icon(Icons.folder_outlined, size: 18), label: const Text('Carpeta'), onPressed: () => add(() => pickFolder(ctx))),
                      ActionChip(avatar: const Icon(Icons.auto_awesome, size: 18), label: const Text('IA'), onPressed: () => add(() => pickAi(ctx))),
                    ]),
                  ],
                ],
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: kDanger, side: const BorderSide(color: kDanger)),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Quitar del escritorio'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    removeFromDesk(context, d);
                  },
                ),
              ]),
            ),
          ]),
        );
      }),
    ),
  );
}

/// Quitar un icono del escritorio o de la barra (con deshacer).
void removeFromDesk(BuildContext context, DrawerCfg d) {
  final dockIndex = app.dock.indexOf(d.id);
  final pos = d.pos;
  app.removeDrawer(d);
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text('«${d.name}» quitado'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: kSheet2,
    action: SnackBarAction(label: 'Deshacer', textColor: kGlow, onPressed: () => app.restoreDrawer(d, dockIndex, pos)),
  ));
}

// ======================================================================
// Añadir al escritorio
// ======================================================================
Future<void> addToDesk(BuildContext context, {int page = 0, bool toDock = false}) async {
  final hidden = app.hiddenBuiltins();
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text('Añadir al escritorio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: Tile(size: 40, colors: pal(4), icon: Icons.add, shadow: false),
            title: const Text('Cajón nuevo'),
            subtitle: const Text('Con las apps, webs, carpetas o IA que tú elijas', style: TextStyle(color: kDim)),
            onTap: () => Navigator.of(ctx).pop('custom'),
          ),
          ListTile(
            leading: Tile(size: 40, colors: pal(1), icon: Icons.apps_rounded, shadow: false),
            title: const Text('Apps'),
            subtitle: const Text('Elige una o varias; cada una con su icono de verdad', style: TextStyle(color: kDim)),
            onTap: () => Navigator.of(ctx).pop('app'),
          ),
          if (!toDock)
            ListTile(
              leading: Tile(size: 40, colors: pal(7), icon: Icons.grid_view_rounded, shadow: false),
              title: const Text('Todas mis apps'),
              subtitle: const Text('Las que aún no están, por orden alfabético, en páginas nuevas', style: TextStyle(color: kDim)),
              onTap: () => Navigator.of(ctx).pop('allapps'),
            ),
          if (isAndroid && !toDock) ListTile(
            leading: Tile(size: 40, colors: pal(3), icon: Icons.widgets_outlined, shadow: false),
            title: const Text('Widget'),
            subtitle: const Text('Reloj, tiempo, calendario, notas… de tus apps', style: TextStyle(color: kDim)),
            onTap: () => Navigator.of(ctx).pop('widget'),
          ),
          if (hidden.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text('VOLVER A PONER', style: TextStyle(fontSize: 12, letterSpacing: 1, color: kDim)),
            ),
          for (final h in hidden)
            ListTile(
              leading: Tile(size: 40, colors: pal(h.color), icon: iconFor(h.icon), shadow: false),
              title: Text(h.name),
              onTap: () => Navigator.of(ctx).pop('builtin:${h.type}'),
            ),
          const SizedBox(height: 10),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'custom') {
    final d = app.addDrawer(DrawerCfg(app.newId(), 'Mi cajón', 6, 'star', type: 'custom'), fromPage: page, toDock: toDock);
    await editDrawer(context, d, isNew: true);
  } else if (choice == 'app') {
    final apps = await pickApps(context);
    if (apps.isEmpty) return;
    if (toDock) {
      for (final s in apps) {
        app.addDrawer(DrawerCfg(app.newId(), s.label, 1, 'apps', type: 'app', pkg: s.value), toDock: true);
      }
    } else {
      app.addMany([for (final s in apps) DrawerCfg(app.newId(), s.label, 1, 'apps', type: 'app', pkg: s.value)], fromPage: page);
    }
  } else if (choice == 'allapps') {
    if (!app.appsLoaded) await app.loadApps();
    final have = app.drawers.where((d) => d.type == 'app').map((d) => d.pkg).toSet();
    final missing = app.apps.where((a) => !have.contains(a.pkg)).toList();
    var id = DateTime.now().microsecondsSinceEpoch;
    app.addMany([for (final a in missing) DrawerCfg('c${id++}', a.label, 1, 'apps', type: 'app', pkg: a.pkg)], fromPage: app.pageCount);
    if (context.mounted) toast(context, '${missing.length} apps añadidas');
  } else if (choice == 'widget') {
    await pickWidget(context, page: page);
  } else if (choice.startsWith('builtin:')) {
    final t = choice.substring(8);
    app.addDrawer(defaultDrawers().firstWhere((b) => b.type == t), fromPage: page, toDock: toDock);
  }
}

// ======================================================================
// Selectores
// ======================================================================
Future<List<Acceso>> pickApps(BuildContext context, {Set<String> exclude = const {}, bool single = false}) async {
  if (!app.appsLoaded) await app.loadApps();
  if (!context.mounted) return [];
  final chosen = <String>{};
  var q = '';
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: .9,
      child: StatefulBuilder(builder: (ctx, set) {
        final list = app.apps.where((a) => !exclude.contains(a.pkg) && (q.isEmpty || a.label.toLowerCase().contains(q.toLowerCase()))).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
            child: Row(children: [
              Expanded(child: Text(single ? 'Elige una app' : 'Elige apps', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              if (!single)
                FilledButton(
                  onPressed: chosen.isEmpty ? null : () => Navigator.of(ctx).pop(true),
                  child: Text(chosen.isEmpty ? 'Añadir' : 'Añadir (${chosen.length})'),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => set(() => q = v.trim()),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar app'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final a = list[i];
                final on = chosen.contains(a.pkg);
                return ListTile(
                  leading: AppIcon(pkg: a.pkg, size: 40),
                  title: Text(a.label),
                  trailing: single ? null : Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? kGlow : kDim),
                  onTap: () {
                    if (single) {
                      chosen.add(a.pkg);
                      Navigator.of(ctx).pop(true);
                    } else {
                      set(() => on ? chosen.remove(a.pkg) : chosen.add(a.pkg));
                    }
                  },
                );
              },
            ),
          ),
        ]);
      }),
    ),
  );
  if (ok != true) return [];
  return [
    for (final a in app.apps)
      if (chosen.contains(a.pkg)) Acceso('app', a.label, a.pkg, icon: 'apps', color: 1),
  ];
}

Future<List<Acceso>> pickLink(BuildContext context) async {
  final name = TextEditingController();
  final url = TextEditingController(text: 'https://');
  var icon = 'globe';
  var color = 3;
  final ok = await showModalBottomSheet<bool>(
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
              const Text('Acceso web', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Dirección web')),
            const SizedBox(height: 16),
            IconColorPicker(icon: icon, color: color, onIcon: (v) => set(() => icon = v), onColor: (v) => set(() => color = v)),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Añadir')),
            ),
          ]),
        ),
      ),
    ),
  );
  var u = url.text.trim();
  if (ok != true || u.isEmpty || u == 'https://') return [];
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
  final n = name.text.trim().isEmpty ? (Uri.tryParse(u)?.host ?? u) : name.text.trim();
  return [Acceso('link', n, u, icon: icon, color: color)];
}

Future<List<Acceso>> pickFolder(BuildContext context) async {
  final options = <(String, String, String)>[
    for (final p in app.pins) (p.name, p.path, p.icon),
    if (isWin) ('Escritorio', '$kRoot/${folderName('desktop')}', 'screen'),
    ('Descargas', '$kRoot/${folderName('download')}', 'down'),
    ('Documentos', '$kRoot/${folderName('documents')}', 'doc'),
    if (!isWin) ('Cámara', '$kRoot/${folderName('camera')}', 'cam'),
    ('Imágenes', '$kRoot/${folderName('pictures')}', 'image'),
    ('Capturas', '$kRoot/${folderName('screenshots')}', 'image'),
    ('Música', '$kRoot/${folderName('music')}', 'music'),
    ('Vídeos', '$kRoot/${folderName('videos')}', 'video'),
    if (!isWin) ('WhatsApp', '$kRoot/Android/media/com.whatsapp/WhatsApp/Media', 'chat'),
    if (isWin) ('Disco C:', 'C:/', 'drive') else ('Raíz', kRoot, 'drive'),
  ];
  final seen = <String>{};
  final unique = options.where((o) => seen.add(o.$2)).toList();
  final pick = await showModalBottomSheet<(String, String, String)>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: .8,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 4),
          child: Text('Elige una carpeta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Text('Para otras carpetas: ábrelas en el explorador y usa «Anclar». Saldrán aquí.', style: TextStyle(color: kDim, fontSize: 12)),
        ),
        Expanded(
          child: ListView(children: [
            for (final o in unique)
              ListTile(
                leading: Tile(size: 38, colors: _folderColors, icon: iconFor(o.$3), shadow: false),
                title: Text(o.$1),
                subtitle: Text(o.$2.replaceFirst(kRoot, rootLabel), style: const TextStyle(color: kDim, fontSize: 12)),
                onTap: () => Navigator.of(ctx).pop(o),
              ),
          ]),
        ),
      ]),
    ),
  );
  if (pick == null) return [];
  return [Acceso('folder', pick.$1, pick.$2, icon: pick.$3)];
}

Future<List<Acceso>> pickAi(BuildContext context) async {
  final m = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Modo de IA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        ),
        for (final e in aiModes.entries)
          ListTile(
            leading: Tile(size: 38, colors: pal(e.value.$2), icon: iconFor(e.value.$1), shadow: false),
            title: Text(e.key),
            onTap: () => Navigator.of(ctx).pop(e.key),
          ),
        const SizedBox(height: 10),
      ]),
    ),
  );
  if (m == null) return [];
  final v = aiModes[m]!;
  return [Acceso('ai', m, m, icon: v.$1, color: v.$2)];
}

/// Elegir con qué navegador se abren las webs.
Future<void> pickBrowser(BuildContext context) async {
  final list = await Native.browsers();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Navegador para Internet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          ),
          ListTile(
            leading: Tile(size: 40, colors: pal(7), icon: Icons.public, shadow: false),
            title: const Text('El que tenga Android por defecto'),
            trailing: app.browserPkg.isEmpty ? const Icon(Icons.check, color: kGlow) : null,
            onTap: () {
              app.browserPkg = '';
              app.changed();
              Navigator.of(ctx).pop();
            },
          ),
          for (final b in list)
            ListTile(
              leading: AppIcon(pkg: b.pkg, size: 40),
              title: Text(b.label),
              trailing: app.browserPkg == b.pkg ? const Icon(Icons.check, color: kGlow) : null,
              onTap: () {
                app.browserPkg = b.pkg;
                app.changed();
                Navigator.of(ctx).pop();
              },
            ),
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(18), child: Text('No se han encontrado navegadores instalados.', style: TextStyle(color: kDim))),
          const SizedBox(height: 10),
        ]),
      ),
    ),
  );
}

String browserName() {
  if (app.browserPkg.isEmpty) return 'El de Android por defecto';
  final a = app.apps.where((x) => x.pkg == app.browserPkg);
  return a.isEmpty ? app.browserPkg : a.first.label;
}

/// Elegir un widget de Android y colocarlo en el escritorio.
Future<void> pickWidget(BuildContext context, {int page = 0}) async {
  final list = await Native.widgetProviders();
  if (!context.mounted) return;
  var q = '';
  final pick = await showModalBottomSheet<WidgetProvider>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => FractionallySizedBox(
      heightFactor: .9,
      child: StatefulBuilder(builder: (ctx, set) {
        final shown = list.where((w) => q.isEmpty || '${w.app} ${w.label}'.toLowerCase().contains(q.toLowerCase())).toList();
        return Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Añadir widget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => set(() => q = v.trim()),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por app o widget'),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No se han encontrado widgets', style: TextStyle(color: kDim)))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final w = shown[i];
                      final newApp = i == 0 || shown[i - 1].pkg != w.pkg;
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (newApp)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                            child: Row(children: [
                              AppIcon(pkg: w.pkg, size: 26),
                              const SizedBox(width: 10),
                              Text(w.app, style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ListTile(
                          contentPadding: const EdgeInsets.only(left: 52, right: 16),
                          title: Text(w.label),
                          subtitle: Text('${w.minW.round()} × ${w.minH.round()}', style: const TextStyle(color: kDim, fontSize: 12)),
                          trailing: const Icon(Icons.add_circle_outline, color: kGlow),
                          onTap: () => Navigator.of(ctx).pop(w),
                        ),
                      ]);
                    },
                  ),
          ),
        ]);
      }),
    ),
  );
  if (pick == null) return;
  final id = await Native.addWidget(pick.pkg, pick.cls);
  if (id < 0) {
    if (context.mounted) toast(context, 'No se ha añadido el widget');
    return;
  }
  final rows = ((pick.minH + 20) / 100).ceil().clamp(1, 4);
  app.addWidget(WidgetCfg(id, pick.label, pick.pkg, rows * 100.0), page: page, rows: rows);
}
