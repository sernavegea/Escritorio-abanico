import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state.dart';
import 'ui.dart';

/// Un elemento del abanico.
class FanEntry {
  FanEntry(this.label, this.tile, this.onOpen);
  final String label;
  final Widget Function(double size) tile;
  final VoidCallback onOpen;
}

/// Huecos visibles en el círculo. Si hay más elementos, el abanico gira.
const fanSlots = 8;

/// Límite de elementos automáticos; si hay más, el último es "Ver todo".
const fanAutoMax = 48;

List<FanEntry> withMore(List<FanEntry> all, VoidCallback openAll) {
  if (all.length <= fanAutoMax) return all;
  final rest = all.length - (fanAutoMax - 1);
  return [
    ...all.take(fanAutoMax - 1),
    FanEntry(
        'Ver todo',
        (s) => Tile(
            size: s,
            colors: pal(7),
            child: Text('+$rest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s * .26))),
        openAll),
  ];
}

class FanController {
  OverlayEntry? _entry;
  final ValueNotifier<int> hot = ValueNotifier(-1);
  final ValueNotifier<double> offset = ValueNotifier(0);
  List<FanEntry> _items = [];
  Offset _c = Offset.zero;
  double _r = 100;
  int _slots = 1;

  bool get isOpen => _entry != null;
  int get slots => _slots;
  int get count => _items.length;
  bool get rotates => _items.length > _slots;
  double get maxOffset => max(0, _items.length - _slots).toDouble();
  double get step => 2 * pi / _slots;
  Offset get center => _c;
  double get radius => _r;

  /// Posición y visibilidad (0..1) del elemento [i] con el giro actual.
  /// Los elementos salen y entran por arriba del círculo, en la posición de las 12.
  (Offset, double) place(int i) {
    double p = i.toDouble();
    double vis = 1;
    if (rotates) {
      p = i - offset.value;
      final e1 = (p + .5).clamp(0.0, 1.0);
      final e2 = (_slots - .5 - p).clamp(0.0, 1.0);
      vis = min(e1, e2);
    }
    final a = -pi / 2 + p * step;
    final rr = _r * (.5 + .5 * vis);
    return (_c + Offset(cos(a) * rr, sin(a) * rr), vis);
  }

  void show({
    required BuildContext context,
    required String drawerId,
    required Offset tileCenter,
    required List<FanEntry> items,
    required VoidCallback onCore,
    bool hover = false,
  }) {
    close();
    final size = MediaQuery.of(context).size;
    final r = (min(size.width, size.height) / 2 - 70).clamp(86.0, 124.0);
    final pad = r + 46;
    _c = Offset(
      tileCenter.dx.clamp(pad, max(pad, size.width - pad)),
      tileCenter.dy.clamp(pad + 30, max(pad + 30, size.height - pad - 30)),
    );
    _r = r;
    _items = items;
    _slots = items.length > fanSlots ? fanSlots : max(1, items.length);
    offset.value = 0;
    hot.value = -1;
    _entry = OverlayEntry(
      builder: (_) => _FanOverlay(
        drawerId: drawerId,
        hover: hover,
        items: items,
        onClose: close,
        onCore: () {
          close();
          onCore();
        },
        onPick: (i) {
          final it = _items[i];
          close();
          it.onOpen();
        },
      ),
    );
    Overlay.of(context).insert(_entry!);
    if (!hover) HapticFeedback.mediumImpact();
  }

  /// Mientras el dedo sigue pulsado, ilumina el elemento visible más cercano.
  void hover(Offset p) {
    var best = -1;
    var bd = 48.0;
    for (var i = 0; i < _items.length; i++) {
      final (pos, vis) = place(i);
      if (vis < .6) continue;
      final d = (p - pos).distance;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    if (hot.value != best) {
      hot.value = best;
      if (best >= 0) HapticFeedback.selectionClick();
    }
  }

  /// Al soltar el dedo: abre el elemento iluminado o deja el abanico abierto para girarlo o tocar.
  void release() {
    final i = hot.value;
    if (i >= 0 && i < _items.length && _entry != null) {
      final it = _items[i];
      close();
      it.onOpen();
    } else {
      hot.value = -1;
    }
  }

  void rotateBy(double dAngle) {
    if (!rotates) return;
    final before = offset.value.round();
    offset.value = (offset.value - dAngle / step).clamp(-.45, maxOffset + .45);
    if (offset.value.round() != before) HapticFeedback.selectionClick();
  }

  void close() {
    _entry?.remove();
    _entry = null;
    hot.value = -1;
  }
}

final fan = FanController();

class _FanOverlay extends StatefulWidget {
  const _FanOverlay({required this.drawerId, required this.hover, required this.items, required this.onClose, required this.onCore, required this.onPick});
  final String drawerId;
  final bool hover;
  final List<FanEntry> items;
  final VoidCallback onClose;
  final VoidCallback onCore;
  final ValueChanged<int> onPick;

  @override
  State<_FanOverlay> createState() => _FanOverlayState();
}

class _FanOverlayState extends State<_FanOverlay> with TickerProviderStateMixin {
  late final AnimationController intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 340))..forward();
  late final AnimationController snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  double _from = 0, _to = 0;
  double? _lastAngle;
  double _lastDelta = 0;

  @override
  void initState() {
    super.initState();
    snap.addListener(() {
      fan.offset.value = _from + (_to - _from) * Curves.easeOutCubic.transform(snap.value);
    });
  }

  Timer? _leave;

  @override
  void dispose() {
    _leave?.cancel();
    intro.dispose();
    snap.dispose();
    super.dispose();
  }

  /// Con ratón: si el puntero se aleja del círculo, el abanico se cierra solo.
  void _onHover(PointerHoverEvent e) {
    if (!widget.hover) return;
    final far = (e.position - fan.center).distance > fan.radius + 70;
    if (far) {
      _leave ??= Timer(const Duration(milliseconds: 280), widget.onClose);
    } else {
      _leave?.cancel();
      _leave = null;
    }
  }

  /// Rueda del ratón: gira el abanico de uno en uno.
  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !fan.rotates) return;
    final dir = e.scrollDelta.dy > 0 ? 1.0 : -1.0;
    _from = fan.offset.value;
    _to = (fan.offset.value.roundToDouble() + dir).clamp(0.0, fan.maxOffset);
    snap.forward(from: 0);
  }

  double _angleOf(Offset p) {
    final d = p - fan.center;
    return atan2(d.dy, d.dx);
  }

  void _panStart(DragStartDetails d) {
    snap.stop();
    _lastAngle = _angleOf(d.globalPosition);
    _lastDelta = 0;
  }

  void _panUpdate(DragUpdateDetails d) {
    final a = _angleOf(d.globalPosition);
    final last = _lastAngle ?? a;
    var da = a - last;
    if (da > pi) da -= 2 * pi;
    if (da < -pi) da += 2 * pi;
    _lastAngle = a;
    _lastDelta = da;
    fan.rotateBy(da);
  }

  void _panEnd(DragEndDetails d) {
    if (!fan.rotates) return;
    // Un poco de inercia y luego encaja en el hueco más cercano.
    final target = (fan.offset.value - _lastDelta / fan.step * 4).roundToDouble().clamp(0.0, fan.maxOffset);
    _from = fan.offset.value;
    _to = target;
    snap.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = fan.center;
    const s = 56.0;
    final d = fan.radius * 2 + s + 40;
    return Material(
      type: MaterialType.transparency,
      child: Listener(
        onPointerHover: _onHover,
        onPointerSignal: _onSignal,
        child: Stack(children: [
        // Fondo: tocar fuera del círculo cierra.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: FadeTransition(opacity: intro, child: Container(color: Colors.black.withValues(alpha: .32))),
          ),
        ),
        // El círculo y sus elementos: arrastrar en círculo gira el abanico.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onPanStart: _panStart,
            onPanUpdate: _panUpdate,
            onPanEnd: _panEnd,
            child: AnimatedBuilder(
              animation: Listenable.merge([intro, fan.offset]),
              builder: (_, __) {
                final t = Curves.easeOutCubic.transform(intro.value);
                final children = <Widget>[
                  Positioned(
                    left: c.dx - d / 2,
                    top: c.dy - d / 2,
                    width: d,
                    height: d,
                    child: Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: .4 + .6 * t,
                        child: Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xD60C1C1E), border: Border.all(color: kLine)),
                        ),
                      ),
                    ),
                  ),
                ];
                for (var i = 0; i < widget.items.length; i++) {
                  final (pos, vis) = fan.place(i);
                  if (vis <= 0.02) continue;
                  final delay = (i < fanSlots ? i * .035 : 0.0).clamp(0.0, .3);
                  final v = ((intro.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                  final p = Offset.lerp(c, pos, Curves.easeOutBack.transform(v))!;
                  final sc = .55 + .45 * vis;
                  children.add(Positioned(
                    left: p.dx - 42,
                    top: p.dy - s / 2,
                    width: 84,
                    child: Opacity(
                      opacity: (v * vis).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: sc,
                        child: GestureDetector(
                          onTap: () => widget.onPick(i),
                          child: ValueListenableBuilder<int>(
                            valueListenable: fan.hot,
                            builder: (_, h, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                              AnimatedScale(
                                scale: h == i ? 1.16 : 1,
                                duration: const Duration(milliseconds: 120),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(s * app.radius + 3),
                                    border: Border.all(color: h == i ? kGlow : Colors.transparent, width: 3),
                                  ),
                                  child: widget.items[i].tile(s),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: kInk, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ));
                }
                children.add(Positioned(
                  left: c.dx - 32,
                  top: c.dy - 32,
                  child: GestureDetector(onTap: widget.onCore, child: DrawerTile(id: widget.drawerId, size: 64)),
                ));
                final n = widget.items.length;
                String? info;
                if (n == 0) {
                  info = 'Vacío · toca el centro';
                } else if (fan.rotates) {
                  final first = fan.offset.value.round().clamp(0, n - 1) + 1;
                  final last = min(n, first + fan.slots - 1);
                  info = '$first–$last de $n · gira';
                }
                if (info != null) {
                  children.add(Positioned(
                    left: c.dx - 90,
                    width: 180,
                    top: c.dy + 38,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: t,
                        child: Text(info, textAlign: TextAlign.center, style: const TextStyle(color: kDim, fontSize: 11)),
                      ),
                    ),
                  ));
                }
                return Stack(children: children);
              },
            ),
          ),
        ),
      ]),
      ),
    );
  }
}
