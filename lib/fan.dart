import 'dart:math';

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

const fanMax = 10;

/// Si hay más de [fanMax], deja los 9 primeros (ya vienen ordenados por uso reciente) y un "+N".
List<FanEntry> withMore(List<FanEntry> all, VoidCallback openAll) {
  if (all.length <= fanMax) return all;
  final rest = all.length - (fanMax - 1);
  return [
    ...all.take(fanMax - 1),
    FanEntry('Ver todo', (s) => Tile(size: s, colors: pal(7), child: Text('+$rest', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s * .28))), openAll),
  ];
}

class FanController {
  OverlayEntry? _entry;
  final ValueNotifier<int> hot = ValueNotifier(-1);
  List<Offset> _centers = [];
  List<FanEntry> _items = [];

  bool get isOpen => _entry != null;

  void show({
    required BuildContext context,
    required String drawerId,
    required Offset tileCenter,
    required List<FanEntry> items,
    required VoidCallback onCore,
  }) {
    close();
    final size = MediaQuery.of(context).size;
    final r = (min(size.width, size.height) / 2 - 70).clamp(86.0, 124.0);
    final pad = r + 46;
    final c = Offset(
      tileCenter.dx.clamp(pad, max(pad, size.width - pad)),
      tileCenter.dy.clamp(pad + 30, max(pad + 30, size.height - pad - 30)),
    );
    _items = items;
    final n = items.length;
    _centers = [for (var i = 0; i < n; i++) c + Offset(cos(-pi / 2 + i * 2 * pi / n) * r, sin(-pi / 2 + i * 2 * pi / n) * r)];
    hot.value = -1;
    _entry = OverlayEntry(
      builder: (_) => _FanOverlay(
        drawerId: drawerId,
        center: c,
        radius: r,
        items: items,
        centers: _centers,
        hot: hot,
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
    HapticFeedback.mediumImpact();
  }

  /// Mientras el dedo sigue pulsado, ilumina el elemento más cercano.
  void hover(Offset p) {
    var best = -1;
    var bd = 48.0;
    for (var i = 0; i < _centers.length; i++) {
      final d = (p - _centers[i]).distance;
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

  /// Al soltar el dedo: abre el elemento iluminado o deja el abanico abierto para tocar.
  void release() {
    final i = hot.value;
    if (i >= 0 && i < _items.length && _entry != null) {
      final it = _items[i];
      close();
      it.onOpen();
    }
  }

  void close() {
    _entry?.remove();
    _entry = null;
    hot.value = -1;
  }
}

final fan = FanController();

class _FanOverlay extends StatefulWidget {
  const _FanOverlay({
    required this.drawerId,
    required this.center,
    required this.radius,
    required this.items,
    required this.centers,
    required this.hot,
    required this.onClose,
    required this.onCore,
    required this.onPick,
  });
  final String drawerId;
  final Offset center;
  final double radius;
  final List<FanEntry> items;
  final List<Offset> centers;
  final ValueNotifier<int> hot;
  final VoidCallback onClose;
  final VoidCallback onCore;
  final ValueChanged<int> onPick;

  @override
  State<_FanOverlay> createState() => _FanOverlayState();
}

class _FanOverlayState extends State<_FanOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 340))..forward();

  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.center;
    const s = 56.0;
    final d = widget.radius * 2 + s + 40;
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: FadeTransition(opacity: ac, child: Container(color: Colors.black.withValues(alpha: .32))),
          ),
        ),
        AnimatedBuilder(
          animation: ac,
          builder: (_, __) {
            final t = Curves.easeOutCubic.transform(ac.value);
            return Positioned(
              left: c.dx - d / 2,
              top: c.dy - d / 2,
              width: d,
              height: d,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: .4 + .6 * t,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xD60C1C1E),
                        border: Border.all(color: kLine),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        for (var i = 0; i < widget.items.length; i++)
          AnimatedBuilder(
            animation: ac,
            builder: (_, __) {
              final delay = (i * .035).clamp(0.0, .3);
              final v = ((ac.value - delay) / (1 - delay)).clamp(0.0, 1.0);
              final p = Offset.lerp(c, widget.centers[i], Curves.easeOutBack.transform(v))!;
              return Positioned(
                left: p.dx - 42,
                top: p.dy - s / 2,
                width: 84,
                child: Opacity(
                  opacity: v,
                  child: GestureDetector(
                    onTap: () => widget.onPick(i),
                    child: ValueListenableBuilder<int>(
                      valueListenable: widget.hot,
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
              );
            },
          ),
        Positioned(
          left: c.dx - 32,
          top: c.dy - 32,
          child: GestureDetector(onTap: widget.onCore, child: DrawerTile(id: widget.drawerId, size: 64)),
        ),
        if (widget.items.isEmpty)
          Positioned(
            left: c.dx - 100,
            width: 200,
            top: c.dy + 44,
            child: const Text('Vacío · toca para abrir', textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 12)),
          ),
      ]),
    );
  }
}
