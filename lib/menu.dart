// Menú de opciones de un icono (al mantenerlo pulsado): accesos rápidos de la app,
// información, editar, barra, quitar y desinstalar.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'fan.dart';
import 'native.dart';
import 'pages.dart';
import 'state.dart';
import 'ui.dart';

class MenuAction {
  const MenuAction(this.icon, this.label, this.onTap, {this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class IconMenuController {
  OverlayEntry? _entry;
  bool get isOpen => _entry != null;

  void close() {
    _entry?.remove();
    _entry = null;
  }

  void show({
    required BuildContext context,
    required Rect anchor,
    required String title,
    required List<MenuAction> actions,
    String? pkg,
  }) {
    close();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => _IconMenu(anchor: anchor, title: title, actions: actions, pkg: pkg, onClose: close),
    );
    overlay.insert(_entry!);
  }
}

final iconMenu = IconMenuController();

bool _isSystemApp(String pkg) {
  for (final a in app.apps) {
    if (a.pkg == pkg) return a.sys;
  }
  return false;
}

Rect rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Opciones de un icono del escritorio o de la barra.
void showIconMenu(BuildContext context, String id, {Rect? anchor}) {
  final d = app.drawer(id);
  final inDock = app.dock.contains(d.id);
  final onDesk = inDock || d.pos >= 0;
  void dockToggle() {
    if (inDock) {
      app.moveToSlot(d.id, app.firstFree());
    } else {
      app.moveToDock(d.id, app.dock.length);
    }
  }

  final folder = d.type == 'custom' && d.icon == '_grid';
  final actions = <MenuAction>[
    if (d.type != 'app') MenuAction(Icons.open_in_new, 'Abrir', () => openDrawer(context, d.id)),
    if (d.type == 'app' && isAndroid) MenuAction(Icons.info_outline, 'Info', () => Native.appInfo(d.pkg)),
    MenuAction(Icons.edit_outlined, folder ? 'Renombrar' : 'Editar', () => editDrawer(context, d)),
    if (onDesk)
      MenuAction(inDock ? Icons.south_east : Icons.view_sidebar_outlined, inDock ? 'Sacar de la barra' : 'A la barra', dockToggle),
    if (onDesk) MenuAction(folder ? Icons.unarchive_outlined : Icons.close, folder ? 'Deshacer' : 'Quitar', () => removeFromDesk(context, d)),
    if (d.type == 'app' && isAndroid && !_isSystemApp(d.pkg))
      MenuAction(Icons.delete_outline, 'Desinstalar', () {
        app.forceRefresh = true;
        Native.uninstall(d.pkg);
      }, danger: true),
  ];
  iconMenu.show(
    context: context,
    anchor: anchor ?? rectOf(context),
    title: d.name,
    actions: actions,
    pkg: d.type == 'app' ? d.pkg : null,
  );
}

/// Opciones de una app que no está en el escritorio (por ejemplo, en el buscador).
void showAppMenu(BuildContext context, AppEntry a, {Rect? anchor}) {
  final onDesk = app.drawers.any((d) => d.type == 'app' && d.pkg == a.pkg);
  iconMenu.show(
    context: context,
    anchor: anchor ?? rectOf(context),
    title: a.label,
    pkg: a.pkg,
    actions: [
      if (isAndroid) MenuAction(Icons.info_outline, 'Info', () => Native.appInfo(a.pkg)),
      if (!onDesk)
        MenuAction(Icons.add_to_home_screen, 'Al escritorio', () {
          app.addDrawer(DrawerCfg(app.newId(), a.label, 1, 'apps', type: 'app', pkg: a.pkg));
          toast(context, '«${a.label}» añadida al escritorio');
        }),
      if (isAndroid && !a.sys)
        MenuAction(Icons.delete_outline, 'Desinstalar', () {
          app.forceRefresh = true;
          Native.uninstall(a.pkg);
        }, danger: true),
    ],
  );
}

class _IconMenu extends StatefulWidget {
  const _IconMenu({required this.anchor, required this.title, required this.actions, required this.pkg, required this.onClose});
  final Rect anchor;
  final String title;
  final List<MenuAction> actions;
  final String? pkg;
  final VoidCallback onClose;
  @override
  State<_IconMenu> createState() => _IconMenuState();
}

class _IconMenuState extends State<_IconMenu> with SingleTickerProviderStateMixin {
  late final AnimationController intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 160))..forward();
  List<AppShortcut> shortcuts = const [];

  @override
  void initState() {
    super.initState();
    final pkg = widget.pkg;
    if (pkg != null) {
      Native.shortcuts(pkg).then((s) {
        if (mounted) setState(() => shortcuts = s);
      });
    }
  }

  @override
  void dispose() {
    intro.dispose();
    super.dispose();
  }

  void _run(VoidCallback f) {
    widget.onClose();
    HapticFeedback.selectionClick();
    f();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const w = 248.0;
    final a = widget.anchor;
    final rows = (widget.actions.length / 4).ceil();
    final estH = 46 + rows * 66 + shortcuts.length * 46.0;
    final below = a.bottom + 8 + estH < size.height - 16 || a.top - estH < 40;
    final double left = (a.center.dx - w / 2).clamp(12.0, max(12.0, size.width - w - 12)).toDouble();
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            onSecondaryTap: widget.onClose,
            child: FadeTransition(opacity: intro, child: Container(color: Colors.black.withValues(alpha: .25))),
          ),
        ),
        Positioned(
          left: left,
          width: w,
          top: below ? a.bottom + 8 : null,
          bottom: below ? null : size.height - a.top + 8,
          child: FadeTransition(
            opacity: intro,
            child: ScaleTransition(
              scale: Tween(begin: .92, end: 1.0).animate(CurvedAnimation(parent: intro, curve: Curves.easeOutCubic)),
              alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  color: kSheet,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kLine),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  for (final s in shortcuts)
                    InkWell(
                      onTap: () => _run(() => Native.startShortcut(s.pkg, s.id)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(children: [
                          if (s.icon != null)
                            ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(s.icon!, width: 28, height: 28))
                          else
                            const Icon(Icons.bolt, size: 24, color: kGlow),
                          const SizedBox(width: 12),
                          Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ),
                  if (shortcuts.isNotEmpty) const Divider(height: 8, color: kLine),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                    child: Wrap(children: [
                      for (final act in widget.actions)
                        SizedBox(
                          width: (w - 14) / 4,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _run(act.onTap),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(act.icon, color: act.danger ? kDanger : kInk, size: 22),
                                const SizedBox(height: 4),
                                Text(act.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    style: TextStyle(fontSize: 10.5, height: 1.1, color: act.danger ? kDanger : kDim)),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Cierra a la vez el menú de opciones y el abanico.
void closeMenus() {
  iconMenu.close();
  fan.close();
}
