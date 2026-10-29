import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor.dart';
import 'fan.dart';
import 'menu.dart';
import 'native.dart';
import 'notifs.dart';
import 'pages.dart';
import 'state.dart';
import 'ui.dart';

/// Zona principal del escritorio: barra lateral (estilo Ubuntu) + páginas con cuadrícula de iconos.
class DeskArea extends StatefulWidget {
  const DeskArea({super.key, required this.editing, required this.onEditRequest});
  final bool editing;
  final VoidCallback onEditRequest;
  @override
  State<DeskArea> createState() => DeskAreaState();
}

class DeskAreaState extends State<DeskArea> {
  final pc = PageController();
  final ValueNotifier<int> pageN = ValueNotifier(0);
  int get page => pageN.value;
  bool _warmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_warmed) {
      _warmed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _warmIcons());
    }
  }

  /// Carga y decodifica de antemano los iconos de todas las páginas,
  /// para que al pasar de página no haya que esperar a ninguno.
  Future<void> _warmIcons() async {
    final pkgs = <String>{
      for (final d in [...app.deskItems, ...app.dockItems])
        if (d.type == 'app' && d.pkg.isNotEmpty) d.pkg,
    };
    for (final pkg in pkgs) {
      if (!mounted) return;
      var b = app.iconCache[pkg];
      if (b == null && !app.iconCache.containsKey(pkg)) {
        b = await Native.icon(pkg);
        app.iconCache[pkg] = b;
      }
      if (b != null && mounted) {
        try {
          await precacheImage(MemoryImage(b), context);
        } catch (_) {}
      }
    }
  }
  Timer? _flip;
  bool dragging = false;

  @override
  void dispose() {
    _flip?.cancel();
    pc.dispose();
    pageN.dispose();
    super.dispose();
  }

  void _goTo(int p) {
    if (!pc.hasClients) return;
    pc.animateToPage(p, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  /// Al arrastrar un icono contra el borde, pasa de página.
  Widget _edge(bool right, int pages) {
    return Positioned(
      top: 0,
      bottom: 0,
      left: right ? null : 0,
      right: right ? 0 : null,
      width: 26,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onMove: (_) {
          _flip ??= Timer(const Duration(milliseconds: 550), () {
            _flip = null;
            final target = page + (right ? 1 : -1);
            if (target >= 0 && target < pages) _goTo(target);
          });
        },
        onLeave: (_) {
          _flip?.cancel();
          _flip = null;
        },
        onAcceptWithDetails: (_) {
          _flip?.cancel();
          _flip = null;
        },
        builder: (_, cand, __) => Container(color: cand.isNotEmpty ? kGlow.withValues(alpha: .18) : Colors.transparent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final pages = app.pageCount + (editing ? 1 : 0);
    if (page >= pages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && page >= pages) pageN.value = max(0, pages - 1);
      });
    }
    final side = app.dockSide;
    final grid = Column(children: [
      if (!editing && isAndroid) const Padding(padding: EdgeInsets.only(top: 4), child: NotifBubbles()),
      Expanded(
        child: Stack(children: [
          PageView.builder(
            controller: pc,
            itemCount: pages,
            // Prepara la página de al lado antes de llegar a ella.
            allowImplicitScrolling: true,
            onPageChanged: (p) => pageN.value = p,
            itemBuilder: (_, p) => _KeepPage(
              child: RepaintBoundary(
                child: _DeskPage(page: p, editing: editing, dragging: dragging, onEditRequest: widget.onEditRequest, onDrag: _setDragging),
              ),
            ),
          ),
          if (dragging) ...[_edge(false, pages), _edge(true, pages)],
        ]),
      ),
      if (pages > 1)
        ValueListenableBuilder<int>(
          valueListenable: pageN,
          builder: (_, page, __) => Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages; i++)
              GestureDetector(
                onTap: () => _goTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == page ? kInk : kInk.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ]),
        ),
        ),
    ]);
    final dock = side == 'none' && !editing
        ? null
        : _Dock(vertical: side != 'bottom', editing: editing, dragging: dragging, page: page, onEditRequest: widget.onEditRequest, onDrag: _setDragging);
    if (dock == null) return grid;
    if (side == 'bottom') {
      return Column(children: [Expanded(child: grid), dock]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [dock, Expanded(child: grid)]);
  }

  void _setDragging(bool v) {
    app.holdCompact = v;
    if (dragging != v) setState(() => dragging = v);
    if (!v) app.compactNow();
  }
}

/// Suelta un icono encima de otro: crea un cajón, lo añade a un cajón o los intercambia.
void dropOnIcon(BuildContext context, String from, String to, ValueChanged<bool> onDrag) {
  HapticFeedback.selectionClick();
  onDrag(false);
  final r = app.dropOn(from, to);
  if (r == 'new') {
    toast(context, 'Cajón creado. Suelta más apps encima para añadirlas');
  } else if (r == 'added') {
    toast(context, 'Añadida a «${app.drawer(to).name}»');
  }
}

/// Icono fuera del modo edición: se toca para abrir, las apps se arrastran con pulsación larga
/// y se puede soltar otra app encima para juntarlas en un cajón.
class _LiveIcon extends StatefulWidget {
  const _LiveIcon({required this.id, required this.size, required this.width, required this.onEditRequest, required this.onDrag, this.label = true});
  final String id;
  final double size;
  final double width;
  final bool label;
  final VoidCallback onEditRequest;
  final ValueChanged<bool> onDrag;
  @override
  State<_LiveIcon> createState() => _LiveIconState();
}

class _LiveIconState extends State<_LiveIcon> {
  Offset? _origin;

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final d = app.drawer(id);
    Widget icon = DeskIcon(id: id, size: widget.size, width: widget.width, label: widget.label, onEditRequest: widget.onEditRequest);
    if (d.type == 'app') {
      final face = SizedBox(width: widget.width, child: IconFace(id: id, size: widget.size, label: widget.label));
      // Mantener pulsado: salen las opciones. Si además se mueve el dedo, el menú se cierra y se arrastra el icono.
      icon = LongPressDraggable<String>(
        data: id,
        delay: const Duration(milliseconds: 380),
        hapticFeedbackOnStart: true,
        onDragStarted: () {
          fan.close();
          _origin = null;
          widget.onDrag(true);
          showIconMenu(context, id);
        },
        onDragUpdate: (u) {
          _origin ??= u.globalPosition;
          if (iconMenu.isOpen && (u.globalPosition - _origin!).distance > 18) iconMenu.close();
        },
        onDragEnd: (_) => widget.onDrag(false),
        feedback: Material(type: MaterialType.transparency, child: Transform.scale(scale: 1.12, child: face)),
        childWhenDragging: face,
        child: icon,
      );
    }
    final canTake = d.type == 'app' || d.type == 'custom';
    return DragTarget<String>(
      onWillAcceptWithDetails: (det) => det.data != id,
      onAcceptWithDetails: (det) => dropOnIcon(context, det.data, id, widget.onDrag),
      builder: (context, cand, _) => AnimatedScale(
        scale: cand.isNotEmpty ? (canTake ? 1.18 : 1.08) : 1,
        duration: const Duration(milliseconds: 120),
        child: icon,
      ),
    );
  }
}

/// Mantiene viva una página ya construida para no rehacerla al volver a ella.
class _KeepPage extends StatefulWidget {
  const _KeepPage({required this.child});
  final Widget child;
  @override
  State<_KeepPage> createState() => _KeepPageState();
}

class _KeepPageState extends State<_KeepPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ======================================================================
// Una página de la cuadrícula
// ======================================================================
class _DeskPage extends StatelessWidget {
  const _DeskPage({required this.page, required this.editing, required this.dragging, required this.onEditRequest, required this.onDrag});
  final int page;
  final bool editing;
  final bool dragging;
  final VoidCallback onEditRequest;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = app.gridCols, rows = app.gridRows;
      final cw = box.maxWidth / cols, ch = box.maxHeight / rows;
      final iconS = min(app.iconSize, min(cw - 14, ch - 30)).clamp(30.0, 120.0);
      final base = page * app.perPage;
      final children = <Widget>[];

      // Fondo: mantener pulsado en un hueco entra en modo edición.
      if (!editing) {
        children.add(Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onEditRequest),
        ));
      }

      // Casillas vacías (en edición o mientras se arrastra, para soltar iconos).
      if (editing || dragging) {
        for (var k = 0; k < app.perPage; k++) {
          final slot = base + k;
          if (app.blocked(slot) || app.itemAt(slot) != null) continue;
          children.add(Positioned(
            left: app.colOf(slot) * cw,
            top: app.rowOf(slot) * ch,
            width: cw,
            height: ch,
            child: DragTarget<String>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (det) {
                HapticFeedback.selectionClick();
                app.moveToSlot(det.data, slot);
              },
              builder: (_, cand, __) => Center(
                child: Container(
                  width: iconS,
                  height: iconS,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(iconS * app.radius),
                    border: Border.all(color: cand.isNotEmpty ? kGlow : kInk.withValues(alpha: .18), width: cand.isNotEmpty ? 2.5 : 1),
                    color: cand.isNotEmpty ? kGlow.withValues(alpha: .15) : Colors.transparent,
                  ),
                ),
              ),
            ),
          ));
        }
      }

      // Widgets de Android: ocupan filas completas.
      for (final w in app.widgets.where((w) => w.page == page)) {
        children.add(Positioned(
          key: ValueKey('w${w.id}'),
          left: 6,
          right: 6,
          top: w.row * ch + 4,
          height: w.rows * ch - 8,
          child: _WidgetBox(cfg: w, editing: editing, width: box.maxWidth - 12, height: w.rows * ch - 8),
        ));
      }

      // Iconos.
      for (final d in app.deskItems.where((d) => app.pageOf(d.pos) == page)) {
        children.add(Positioned(
          key: ValueKey(d.id),
          left: app.colOf(d.pos) * cw,
          top: app.rowOf(d.pos) * ch,
          width: cw,
          height: ch,
          child: Center(
            child: editing
                ? _EditIcon(
                    id: d.id,
                    size: iconS,
                    width: cw,
                    onDrag: onDrag,
                    onDrop: (from) => dropOnIcon(context, from, d.id, onDrag),
                  )
                : _LiveIcon(id: d.id, size: iconS, width: cw, onEditRequest: onEditRequest, onDrag: onDrag),
          ),
        ));
      }

      if (editing && app.deskItems.where((d) => app.pageOf(d.pos) == page).isEmpty && app.widgets.every((w) => w.page != page)) {
        children.add(Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: kInk, backgroundColor: const Color(0x880C1C1E)),
              onPressed: () => addToDesk(context, page: page),
              icon: const Icon(Icons.add),
              label: Text(page == 0 ? 'Añadir iconos' : 'Añadir a esta página'),
            ),
          ),
        ));
      }
      return Stack(children: children);
    });
  }
}

// ======================================================================
// Barra lateral (o inferior) con los iconos importantes
// ======================================================================
class _Dock extends StatelessWidget {
  const _Dock({required this.vertical, required this.editing, required this.dragging, required this.page, required this.onEditRequest, required this.onDrag});
  final bool vertical;
  final bool editing;
  final bool dragging;
  final int page;
  final VoidCallback onEditRequest;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) {
    final s = min(app.iconSize * .82, 60.0);
    final items = app.dockItems;
    final slot = s + 16;

    Widget wrapTarget(int index, Widget child) => DragTarget<String>(
          onWillAcceptWithDetails: (det) => true,
          onAcceptWithDetails: (det) {
            HapticFeedback.selectionClick();
            app.moveToDock(det.data, index);
          },
          builder: (_, cand, __) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.only(top: vertical && cand.isNotEmpty ? 18 : 0, left: !vertical && cand.isNotEmpty ? 18 : 0),
            child: child,
          ),
        );

    final children = <Widget>[
      for (var i = 0; i < items.length; i++)
        SizedBox(
          width: vertical ? slot : slot,
          height: vertical ? slot : slot,
          child: Center(
            child: editing
                ? wrapTarget(
                    i,
                    _EditIcon(
                      id: items[i].id,
                      size: s,
                      width: slot,
                      label: false,
                      onDrag: onDrag,
                      onDrop: (from) => dropOnIcon(context, from, items[i].id, onDrag),
                    ))
                : _LiveIcon(id: items[i].id, size: s, width: slot, label: false, onEditRequest: onEditRequest, onDrag: onDrag),
          ),
        ),
      if (editing || dragging)
        wrapTarget(
          items.length,
          SizedBox(
            width: slot,
            height: slot,
            child: Center(
              child: GestureDetector(
                onTap: editing ? () => addToDesk(context, toDock: true) : null,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s * app.radius),
                    border: Border.all(color: kInk.withValues(alpha: .5), width: 1.5),
                  ),
                  child: Icon(editing ? Icons.add : Icons.south, color: kInk),
                ),
              ),
            ),
          ),
        ),
    ];

    final bar = Container(
      margin: vertical ? const EdgeInsets.fromLTRB(8, 8, 4, 12) : const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x8C0C1C1E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kLine),
      ),
      child: vertical
          ? SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: children))
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: children)),
    );
    return vertical ? Center(child: bar) : Center(child: bar);
  }
}

// ======================================================================
// Icono normal (toque abre, mantener / pasar el ratón despliega el abanico)
// ======================================================================
class IconFace extends StatelessWidget {
  const IconFace({super.key, required this.id, required this.size, this.tileKey, this.label = true});
  final String id;
  final double size;
  final Key? tileKey;
  final bool label;
  @override
  Widget build(BuildContext context) {
    final d = app.drawer(id);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DrawerTile(key: tileKey, id: id, size: size),
      if (label) ...[
        const SizedBox(height: 5),
        Text(d.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 3, color: Colors.black)])),
      ],
    ]);
  }
}

class DeskIcon extends StatefulWidget {
  const DeskIcon({super.key, required this.id, required this.size, required this.width, required this.onEditRequest, this.label = true});
  final String id;
  final double size;
  final double width;
  final bool label;
  final VoidCallback onEditRequest;
  @override
  State<DeskIcon> createState() => _DeskIconState();
}

class _DeskIconState extends State<DeskIcon> {
  final key = GlobalKey();
  Timer? _hover;

  @override
  void dispose() {
    _hover?.cancel();
    super.dispose();
  }

  Offset _center() {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _showFan({bool hover = false}) {
    fan.show(
      context: context,
      drawerId: widget.id,
      tileCenter: _center(),
      items: buildFanEntries(context, widget.id),
      onCore: () => openDrawer(context, widget.id),
      onOptions: () => showIconMenu(context, widget.id, anchor: rectOf(key.currentContext ?? context)),
      hover: hover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isApp = app.drawer(widget.id).type == 'app';
    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _hover?.cancel();
        fan.close();
        openDrawer(context, widget.id);
      },
      // Las apps se arrastran con una pulsación larga; los cajones abren su abanico.
      onSecondaryTap: () {
        _hover?.cancel();
        fan.close();
        showIconMenu(context, widget.id, anchor: rectOf(key.currentContext ?? context));
      },
      onLongPressStart: isApp ? null : (_) => _showFan(),
      onLongPressMoveUpdate: isApp ? null : (e) => fan.hover(e.globalPosition),
      onLongPressEnd: isApp ? null : (_) => fan.release(),
      child: SizedBox(width: widget.width, child: IconFace(id: widget.id, size: widget.size, tileKey: key, label: widget.label)),
    );
    if (isApp) return gesture;
    return MouseRegion(
      onEnter: (e) {
        if (e.kind != PointerDeviceKind.mouse) return;
        _hover?.cancel();
        _hover = Timer(const Duration(milliseconds: 320), () {
          if (mounted && !fan.isOpen) _showFan(hover: true);
        });
      },
      onExit: (_) => _hover?.cancel(),
      child: gesture,
    );
  }
}

// ======================================================================
// Icono en modo edición: tiembla, se arrastra, se toca para editar y tiene × para quitar
// ======================================================================
class _EditIcon extends StatefulWidget {
  const _EditIcon({required this.id, required this.size, required this.width, required this.onDrop, required this.onDrag, this.label = true});
  final String id;
  final double size;
  final double width;
  final bool label;
  final ValueChanged<String> onDrop;
  final ValueChanged<bool> onDrag;
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
    final face = SizedBox(width: widget.width, child: IconFace(id: widget.id, size: widget.size, label: widget.label));
    return DragTarget<String>(
      onWillAcceptWithDetails: (det) => det.data != widget.id,
      onAcceptWithDetails: (det) {
        HapticFeedback.selectionClick();
        widget.onDrop(det.data);
      },
      builder: (context, cand, _) => LongPressDraggable<String>(
        data: widget.id,
        delay: const Duration(milliseconds: 120),
        hapticFeedbackOnStart: true,
        onDragStarted: () => widget.onDrag(true),
        onDragEnd: (_) => widget.onDrag(false),
        feedback: Material(type: MaterialType.transparency, child: Transform.scale(scale: 1.1, child: face)),
        childWhenDragging: Opacity(opacity: .25, child: face),
        child: Stack(clipBehavior: Clip.none, children: [
          GestureDetector(
            onTap: () => editDrawer(context, d),
            child: AnimatedBuilder(
              animation: wig,
              builder: (_, child) => Transform.rotate(angle: (wig.value - .5) * .07, child: child),
              child: AnimatedScale(scale: cand.isNotEmpty ? 1.12 : 1, duration: const Duration(milliseconds: 120), child: face),
            ),
          ),
          Positioned(
            top: -6,
            left: max(0, (widget.width - widget.size) / 2 - 8),
            child: GestureDetector(
              onTap: () => removeFromDesk(context, d),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFC4473F),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
                ),
                child: const Icon(Icons.close, size: 15, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================
// Widget de Android dentro de la cuadrícula
// ======================================================================
class _WidgetBox extends StatelessWidget {
  const _WidgetBox({required this.cfg, required this.editing, required this.width, required this.height});
  final WidgetCfg cfg;
  final bool editing;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final view = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: width,
        height: height,
        child: AndroidView(
          key: ValueKey('av${cfg.id}-${width.round()}-${height.round()}'),
          viewType: 'abanico/widget',
          creationParams: {'id': cfg.id, 'w': width.round(), 'h': height.round()},
          creationParamsCodec: const StandardMessageCodec(),
        ),
      ),
    );
    if (!editing) return view;
    Widget btn(IconData icon, String tip, VoidCallback onTap, {Color color = kInk}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: const Color(0xCC0C1C1E)),
          icon: Icon(icon, color: color, size: 18),
        );
    return Stack(children: [
      IgnorePointer(child: Opacity(opacity: .7, child: view)),
      Positioned.fill(
        child: IgnorePointer(
          child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGlow, width: 2))),
        ),
      ),
      Positioned(
        left: 6,
        top: 6,
        right: 6,
        child: Wrap(alignment: WrapAlignment.end, spacing: 2, runSpacing: 2, children: [
          btn(Icons.arrow_upward, 'Subir', () => app.moveWidget(cfg, -1)),
          btn(Icons.arrow_downward, 'Bajar', () => app.moveWidget(cfg, 1)),
          btn(Icons.arrow_back, 'Página anterior', () => app.moveWidgetPage(cfg, -1)),
          btn(Icons.arrow_forward, 'Página siguiente', () => app.moveWidgetPage(cfg, 1)),
          btn(Icons.height, 'Cambiar alto', () => app.resizeWidget(cfg)),
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
    ]);
  }
}
