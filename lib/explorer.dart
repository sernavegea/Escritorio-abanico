import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'pages.dart' show openFile;
import 'state.dart';
import 'ui.dart';

class _Pane {
  _Pane(String start)
      : path = start,
        hist = [start];
  String path;
  List<String> hist;
  int hi = 0;
  final Set<String> sel = {};
  bool selMode = false;
  List<FileSystemEntity> items = [];
  Map<String, FileStat> stats = {};
  bool loading = true;
  String? error;
}

class _Clip {
  _Clip(this.cut, this.paths);
  final bool cut;
  final List<String> paths;
}

/// Explorador de archivos estilo Windows, con doble panel en pantallas anchas.
class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key, this.start});
  final String? start;
  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

class _ExplorerPageState extends State<ExplorerPage> with WidgetsBindingObserver {
  late final List<_Pane> panes = [_Pane(np(widget.start ?? kRoot)), _Pane('$kRoot/${folderName('download')}')];
  int active = 0;
  _Clip? clip;
  bool checked = false;
  bool allowed = false;

  bool get wide => MediaQuery.of(context).size.width >= 600;
  bool get dual => wide && app.dual;
  int get ai => dual ? active : 0;
  _Pane get cur => panes[ai];
  _Pane get other => panes[1 - ai];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await Native.hasAllFiles();
    if (!mounted) return;
    setState(() {
      allowed = ok;
      checked = true;
    });
    if (ok) {
      for (final p in panes) {
        _load(p);
      }
    }
  }

  Future<void> _load(_Pane p) async {
    if (mounted) setState(() => p.loading = true);
    try {
      final raw = await Directory(p.path).list(followLinks: false).toList();
      // Rutas siempre con '/', también en Windows.
      final list = raw.map<FileSystemEntity>((e) => e is Directory ? Directory(np(e.path)) : File(np(e.path))).toList();
      final items = list.where((e) => app.showHidden || !_hiddenName(baseName(e.path))).toList();
      final stats = <String, FileStat>{};
      for (final e in items) {
        try {
          stats[e.path] = await e.stat();
        } catch (_) {}
      }
      items.sort((a, b) {
        final ad = a is Directory, bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return baseName(a.path).toLowerCase().compareTo(baseName(b.path).toLowerCase());
      });
      p.items = items;
      p.stats = stats;
      p.error = null;
    } catch (_) {
      p.items = [];
      p.error = 'No se puede abrir esta carpeta';
    }
    p.sel.removeWhere((s) => !p.items.any((e) => e.path == s));
    if (p.sel.isEmpty) p.selMode = false;
    p.loading = false;
    if (mounted) setState(() {});
  }

  static const _winHidden = {
    'desktop.ini', 'thumbs.db', 'appdata', 'application data', 'cookies', 'local settings', 'nethood', 'printhood', 'recent',
    'sendto', 'start menu', 'templates', 'my documents', 'mis documentos', 'configuración local', 'datos de programa',
    'entorno de red', 'impresoras', 'menú inicio', 'plantillas', 'reciente', r'$recycle.bin', 'system volume information',
    'pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'dumpstack.log.tmp', 'recovery', 'config.msi', 'documents and settings',
  };

  bool _hiddenName(String n) {
    if (n.startsWith('.')) return true;
    if (!isWin) return false;
    final l = n.toLowerCase();
    return l.startsWith('ntuser') || _winHidden.contains(l);
  }

  Future<void> _reloadAll() async {
    for (final p in panes) {
      await _load(p);
    }
  }

  // ---------- Navegación ----------
  void nav(_Pane p, String path) {
    if (path == p.path) return;
    p.hist = p.hist.sublist(0, p.hi + 1)..add(path);
    p.hi = p.hist.length - 1;
    _go(p, path);
  }

  void _go(_Pane p, String path) {
    p.path = path;
    p.sel.clear();
    p.selMode = false;
    p.items = [];
    app.usePin(path);
    _load(p);
  }

  void back(_Pane p) {
    if (p.hi > 0) {
      p.hi--;
      _go(p, p.hist[p.hi]);
    }
  }

  void up(_Pane p) {
    final parent = parentOf(p.path, kRoot);
    if (parent != null) nav(p, parent);
  }

  void _handleBack() {
    final p = cur;
    if (p.selMode || p.sel.isNotEmpty) {
      setState(() {
        p.sel.clear();
        p.selMode = false;
      });
    } else if (p.hi > 0) {
      back(p);
    } else {
      Navigator.of(context).pop();
    }
  }

  // ---------- Selección ----------
  void tapItem(_Pane p, FileSystemEntity e) {
    if (p.selMode) {
      setState(() {
        if (!p.sel.remove(e.path)) p.sel.add(e.path);
        if (p.sel.isEmpty) p.selMode = false;
      });
    } else if (e is Directory) {
      nav(p, e.path);
    } else {
      openFile(context, e.path);
    }
  }

  void longItem(_Pane p, FileSystemEntity e) {
    HapticFeedback.mediumImpact();
    setState(() {
      p.selMode = true;
      p.sel.add(e.path);
    });
  }

  // ---------- Operaciones ----------
  String _unique(String dir, String name, bool isDir) {
    String cand = '$dir/$name';
    if (FileSystemEntity.typeSync(cand) == FileSystemEntityType.notFound) return cand;
    final dot = isDir ? -1 : name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2;; i++) {
      cand = '$dir/$base ($i)$ext';
      if (FileSystemEntityType.notFound == FileSystemEntity.typeSync(cand)) return cand;
    }
  }

  Future<void> _copyDir(Directory src, String dst) async {
    await Directory(dst).create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final t = '$dst/${baseName(e.path)}';
      if (e is Directory) {
        await _copyDir(e, t);
      } else if (e is File) {
        await e.copy(t);
      }
    }
  }

  Future<String?> _transfer(List<String> paths, String dest, {required bool move}) async {
    var done = 0;
    String? problem;
    for (final src in paths) {
      final type = FileSystemEntity.typeSync(src, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      final isDir = type == FileSystemEntityType.directory;
      if (isDir && (dest == src || dest.startsWith('$src/'))) {
        problem = 'No se puede ${move ? 'mover' : 'copiar'} una carpeta dentro de sí misma';
        continue;
      }
      final parent = src.substring(0, src.lastIndexOf('/'));
      if (move && parent == dest) continue;
      final target = _unique(dest, baseName(src), isDir);
      try {
        if (move) {
          try {
            await (isDir ? Directory(src) : File(src)).rename(target);
          } on FileSystemException {
            if (isDir) {
              await _copyDir(Directory(src), target);
              await Directory(src).delete(recursive: true);
            } else {
              await File(src).copy(target);
              await File(src).delete();
            }
          }
        } else {
          if (isDir) {
            await _copyDir(Directory(src), target);
          } else {
            await File(src).copy(target);
          }
        }
        done++;
      } catch (e) {
        problem = 'Error con ${baseName(src)}';
      }
    }
    final what = done == 1 ? '1 elemento' : '$done elementos';
    return problem ?? (done == 0 ? 'No había nada que ${move ? 'mover' : 'copiar'}' : '$what ${move ? 'movido' : 'copiado'}${done == 1 ? '' : 's'} a ${baseName(dest)}');
  }

  Future<T> _busy<T>(String label, Future<T> Function() job) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: kSheet,
          content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 18), Expanded(child: Text(label))]),
        ),
      ),
    );
    try {
      return await job();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> paste() async {
    final c = clip;
    if (c == null) return;
    final dest = cur.path;
    final msg = await _busy(c.cut ? 'Moviendo…' : 'Copiando…', () => _transfer(c.paths, dest, move: c.cut));
    if (c.cut) clip = null;
    await _reloadAll();
    if (mounted) toast(context, msg ?? '');
  }

  Future<void> toOther({required bool move}) async {
    final p = cur, dest = other.path;
    final paths = p.sel.toList();
    final msg = await _busy(move ? 'Moviendo…' : 'Copiando…', () => _transfer(paths, dest, move: move));
    p.sel.clear();
    p.selMode = false;
    await _reloadAll();
    if (mounted) toast(context, msg ?? '');
  }

  void setClip(bool cut) {
    final p = cur;
    setState(() {
      clip = _Clip(cut, p.sel.toList());
      p.sel.clear();
      p.selMode = false;
    });
    toast(context, '${clip!.paths.length} ${cut ? 'cortado' : 'copiado'}${clip!.paths.length == 1 ? '' : 's'}. Ve a la carpeta de destino y pulsa Pegar aquí.');
  }

  Future<void> deleteSel() async {
    final p = cur;
    final paths = p.sel.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSheet,
        title: Text(paths.length == 1 ? '¿Eliminar «${baseName(paths.first)}»?' : '¿Eliminar ${paths.length} elementos?'),
        content: const Text('Se borrarán del móvil. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC4473F)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    var n = 0;
    await _busy('Eliminando…', () async {
      for (final s in paths) {
        try {
          final t = FileSystemEntity.typeSync(s, followLinks: false);
          if (t == FileSystemEntityType.directory) {
            await Directory(s).delete(recursive: true);
          } else if (t != FileSystemEntityType.notFound) {
            await File(s).delete();
          }
          n++;
        } catch (_) {}
      }
    });
    p.sel.clear();
    p.selMode = false;
    await _reloadAll();
    if (mounted) toast(context, n == 1 ? '1 elemento eliminado' : '$n elementos eliminados');
  }

  Future<String?> _askName({required String title, required String initial, required String button, bool selectBase = false}) {
    final c = TextEditingController(text: initial);
    final dot = initial.lastIndexOf('.');
    c.selection = TextSelection(baseOffset: 0, extentOffset: selectBase && dot > 0 ? dot : initial.length);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          void submit() {
            final v = c.text.trim();
            if (v.isEmpty) return set(() => error = 'Escribe un nombre');
            if (RegExp(r'[\\/:*?"<>|]').hasMatch(v)) return set(() => error = 'No puede llevar \\ / : * ? " < > |');
            Navigator.of(ctx).pop(v);
          }

          return AlertDialog(
            backgroundColor: kSheet,
            title: Text(title),
            content: TextField(controller: c, autofocus: true, onSubmitted: (_) => submit(), decoration: InputDecoration(errorText: error)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              FilledButton(onPressed: submit, child: Text(button)),
            ],
          );
        },
      ),
    );
  }

  Future<void> renameSel() async {
    final p = cur;
    final src = p.sel.first;
    final old = baseName(src);
    final v = await _askName(title: 'Renombrar', initial: old, button: 'Renombrar', selectBase: true);
    if (v == null || v == old) return;
    final parent = src.substring(0, src.lastIndexOf('/'));
    final target = '$parent/$v';
    if (FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound) {
      if (mounted) toast(context, 'Ya hay un elemento con ese nombre');
      return;
    }
    try {
      final isDir = FileSystemEntity.isDirectorySync(src);
      await (isDir ? Directory(src) : File(src)).rename(target);
      for (final pin in app.pins) {
        if (pin.path == src) {
          pin.path = target;
          if (pin.name == old) pin.name = v;
          app.changed();
        }
      }
      p.sel.clear();
      p.selMode = false;
      await _reloadAll();
    } catch (_) {
      if (mounted) toast(context, 'No se ha podido renombrar');
    }
  }

  Future<void> newFolder() async {
    final p = cur;
    final v = await _askName(title: 'Nueva carpeta', initial: 'Nueva carpeta', button: 'Crear');
    if (v == null) return;
    final target = _unique(p.path, v, true);
    try {
      await Directory(target).create();
      await _load(p);
    } catch (_) {
      if (mounted) toast(context, 'No se ha podido crear la carpeta aquí');
    }
  }

  // ---------- Interfaz ----------
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = cur;
        final n = p.sel.length;
        final selecting = p.selMode || n > 0;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _handleBack();
          },
          child: Scaffold(
            backgroundColor: kExBg,
            appBar: AppBar(
              backgroundColor: kExBg,
              leading: selecting
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                            p.sel.clear();
                            p.selMode = false;
                          }))
                  : null,
              title: selecting
                  ? Text(n == 1 ? '1 seleccionado' : '$n seleccionados')
                  : Row(children: [
                      const DrawerTile(id: 'files', size: 30, shadow: false),
                      const SizedBox(width: 10),
                      Flexible(child: Text(app.drawer('files').name, overflow: TextOverflow.ellipsis)),
                    ]),
              actions: [
                if (selecting)
                  IconButton(
                    tooltip: 'Seleccionar todo',
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() {
                      p.sel.addAll(p.items.map((e) => e.path));
                      p.selMode = true;
                    }),
                  ),
                if (!selecting && wide)
                  IconButton(
                    tooltip: 'Doble panel',
                    isSelected: app.dual,
                    icon: const Icon(Icons.vertical_split_outlined),
                    selectedIcon: const Icon(Icons.vertical_split, color: kGlow),
                    onPressed: () {
                      app.dual = !app.dual;
                      active = 0;
                      app.changed();
                    },
                  ),
                if (!selecting)
                  IconButton(
                    tooltip: app.listView ? 'Ver como iconos' : 'Ver como lista',
                    icon: Icon(app.listView ? Icons.grid_view : Icons.view_list),
                    onPressed: () {
                      app.listView = !app.listView;
                      app.changed();
                    },
                  ),
                if (!selecting)
                  PopupMenuButton<String>(
                    color: kSheet2,
                    onSelected: (v) {
                      if (v == 'new') newFolder();
                      if (v == 'select') setState(() => p.selMode = true);
                      if (v == 'hidden') {
                        app.showHidden = !app.showHidden;
                        app.changed();
                        _reloadAll();
                      }
                      if (v == 'pin') app.togglePin(p.path == kRoot ? rootLabel : (baseName(p.path).isEmpty ? p.path : baseName(p.path)), p.path);
                      if (v == 'reload') _reloadAll();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'new', child: ListTile(leading: Icon(Icons.create_new_folder_outlined), title: Text('Nueva carpeta'))),
                      const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Seleccionar'))),
                      PopupMenuItem(
                          value: 'pin',
                          child: ListTile(
                              leading: const Icon(Icons.push_pin_outlined),
                              title: Text(app.isPinned(p.path) ? 'Quitar carpeta del abanico' : 'Anclar carpeta al abanico'))),
                      PopupMenuItem(
                          value: 'hidden',
                          child: ListTile(
                              leading: Icon(app.showHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                              title: Text(app.showHidden ? 'Ocultar archivos ocultos' : 'Mostrar archivos ocultos'))),
                      const PopupMenuItem(value: 'reload', child: ListTile(leading: Icon(Icons.refresh), title: Text('Actualizar'))),
                    ],
                  ),
              ],
            ),
            body: !checked
                ? const Center(child: CircularProgressIndicator())
                : !allowed
                    ? _permission()
                    : dual
                        ? Row(children: [
                            Expanded(child: _paneView(0)),
                            const VerticalDivider(width: 1, color: kLine),
                            Expanded(child: _paneView(1)),
                          ])
                        : _paneView(0),
            floatingActionButton: clip != null && allowed
                ? FloatingActionButton.extended(
                    backgroundColor: kGlow,
                    foregroundColor: const Color(0xFF1D1407),
                    onPressed: paste,
                    icon: const Icon(Icons.content_paste),
                    label: Text('Pegar aquí (${clip!.paths.length})'),
                  )
                : null,
            bottomNavigationBar: n > 0 ? _selectionBar(p) : null,
          ),
        );
      },
    );
  }

  Widget _permission() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open, size: 64, color: kDim),
          const SizedBox(height: 14),
          const Text(
            'Para ver, mover y organizar tus archivos, permite el acceso a todos los archivos. Se abrirán los ajustes de Android: activa el permiso para Abanico y vuelve.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kDim, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: Native.requestAllFiles, child: const Text('Permitir acceso a archivos')),
        ]),
      ),
    );
  }

  Widget _selectionBar(_Pane p) {
    final one = p.sel.length == 1 ? p.sel.first : null;
    final oneIsDir = one != null && FileSystemEntity.isDirectorySync(one);
    Widget act(IconData icon, String label, VoidCallback? onTap, {Color? color}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Opacity(
            opacity: onTap == null ? .35 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: color ?? kInk, size: 22),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 11, color: color ?? kInk)),
              ]),
            ),
          ),
        );
    return Material(
      color: kSheet2,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            act(Icons.content_cut, 'Cortar', () => setClip(true)),
            act(Icons.copy, 'Copiar', () => setClip(false)),
            if (dual) act(Icons.drive_file_move_outline, 'Mover al otro', () => toOther(move: true)),
            if (dual) act(Icons.file_copy_outlined, 'Copiar al otro', () => toOther(move: false)),
            act(Icons.drive_file_rename_outline, 'Renombrar', one != null ? renameSel : null),
            if (one != null && oneIsDir)
              act(Icons.push_pin_outlined, app.isPinned(one) ? 'Desanclar' : 'Anclar', () {
                app.togglePin(baseName(one), one);
                toast(context, app.isPinned(one) ? 'Carpeta anclada al abanico' : 'Carpeta quitada del abanico');
              }),
            if (one != null && !oneIsDir) act(Icons.open_in_new, 'Abrir con', () => openFile(context, one)),
            act(Icons.delete_outline, 'Eliminar', deleteSel, color: kDanger),
          ]),
        ),
      ),
    );
  }

  Widget _paneView(int i) {
    final p = panes[i];
    final highlighted = dual && i == active;
    return Listener(
      onPointerDown: (_) {
        if (dual && active != i) setState(() => active = i);
      },
      child: Column(children: [
        _navBar(p, highlighted),
        Expanded(
          child: p.loading && p.items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : p.error != null
                  ? Center(child: Text(p.error!, style: const TextStyle(color: kDim)))
                  : p.items.isEmpty
                      ? const Center(child: Text('Esta carpeta está vacía', style: TextStyle(color: kDim)))
                      : RefreshIndicator(
                          onRefresh: () => _load(p),
                          child: app.listView ? _list(p) : _grid(p),
                        ),
        ),
      ]),
    );
  }

  Widget _navBar(_Pane p, bool highlighted) {
    final parts = [for (final c in crumbsOf(p.path, kRoot)) MapEntry(c.$1, c.$2)];
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: highlighted ? kGlow : kLine, width: highlighted ? 2 : 1)),
      ),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Atrás', onPressed: p.hi > 0 ? () => back(p) : null),
        IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'Subir', onPressed: parentOf(p.path, kRoot) != null ? () => up(p) : null),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              for (var k = 0; k < parts.length; k++) ...[
                if (k > 0) const Icon(Icons.chevron_right, size: 16, color: kDim),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => nav(p, parts[k].value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(parts[k].key,
                        style: TextStyle(fontSize: 13.5, fontWeight: k == parts.length - 1 ? FontWeight.w600 : FontWeight.w400, color: k == parts.length - 1 ? kInk : kDim)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  String _sub(_Pane p, FileSystemEntity e) {
    final st = p.stats[e.path];
    if (st == null) return '';
    final d = fmtDate(st.modified);
    return e is Directory ? d : '$d · ${fmtSize(st.size)}';
  }

  Widget _checkMark(bool on) => Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? kGlow : Colors.transparent,
          border: Border.all(color: on ? kGlow : kDim, width: 1.6),
        ),
        child: on ? const Icon(Icons.check, size: 15, color: Color(0xFF1D1407)) : null,
      );

  Widget _list(_Pane p) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: p.items.length,
      itemBuilder: (_, i) {
        final e = p.items[i];
        final sel = p.sel.contains(e.path);
        final cut = clip?.cut == true && clip!.paths.contains(e.path);
        return Material(
          color: sel ? kSel : Colors.transparent,
          child: InkWell(
            onTap: () => tapItem(p, e),
            onLongPress: () => longItem(p, e),
                onSecondaryTap: () => longItem(p, e),
            child: Opacity(
              opacity: cut ? .45 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  if (p.selMode) _checkMark(sel),
                  fileTile(baseName(e.path), e is Directory, 40, path: e.path),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(baseName(e.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(_sub(p, e), style: const TextStyle(fontSize: 12, color: kDim)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _grid(_Pane p) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 100).floor().clamp(3, 10);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, childAspectRatio: .82),
        itemCount: p.items.length,
        itemBuilder: (_, i) {
          final e = p.items[i];
          final sel = p.sel.contains(e.path);
          final cut = clip?.cut == true && clip!.paths.contains(e.path);
          return Padding(
            padding: const EdgeInsets.all(3),
            child: Material(
              color: sel ? kSel : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => tapItem(p, e),
                onLongPress: () => longItem(p, e),
                onSecondaryTap: () => longItem(p, e),
                child: Opacity(
                  opacity: cut ? .45 : 1,
                  child: Stack(children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          fileTile(baseName(e.path), e is Directory, 52, path: e.path),
                          const SizedBox(height: 6),
                          Text(baseName(e.path), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                    if (p.selMode) Positioned(top: 6, left: 6, child: _checkMark(sel)),
                  ]),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}
