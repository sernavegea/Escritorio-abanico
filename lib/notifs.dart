import 'dart:math';

import 'package:flutter/material.dart';

import 'native.dart';
import 'state.dart';
import 'ui.dart';

const _ink = Color(0xFF1B1B1B);

/// Notificaciones como bocadillos de cómic, con el icono de la app al lado.
class NotifBubbles extends StatefulWidget {
  const NotifBubbles({super.key});
  @override
  State<NotifBubbles> createState() => _NotifBubblesState();
}

class _NotifBubblesState extends State<NotifBubbles> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    // Escucha los cambios: cada notificación nueva vuelve a pintar los bocadillos.
    return ListenableBuilder(listenable: app, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    if (!app.showNotifs) return const SizedBox.shrink();
    final maxW = min(MediaQuery.of(context).size.width - 32, 560.0);
    if (!app.notifAccess) {
      return _Invite(width: maxW);
    }
    final list = app.notifs;
    if (list.isEmpty) return const SizedBox.shrink();
    final shown = expanded ? list : list.take(3).toList();
    return SizedBox(
      width: maxW,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final n in shown) _BubbleRow(key: ValueKey(n.key), n: n),
        if (list.length > 3)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: kInk, backgroundColor: const Color(0x660C1C1E)),
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'Ver menos' : '+${list.length - 3} notificaciones más'),
            ),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _Invite extends StatelessWidget {
  const _Invite({required this.width});
  final double width;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: const Color(0xB30C1C1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
      child: Row(children: [
        const Icon(Icons.chat_bubble_outline, color: kGlow),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Activa los bocadillos para ver aquí tus notificaciones', style: TextStyle(fontSize: 13)),
        ),
        TextButton(onPressed: Native.requestNotifAccess, child: const Text('Activar')),
        IconButton(
          tooltip: 'No mostrar',
          icon: const Icon(Icons.close, size: 18, color: kDim),
          onPressed: () {
            app.showNotifs = false;
            app.changed();
          },
        ),
      ]),
    );
  }
}

String _when(DateTime t) {
  final now = DateTime.now();
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (t.day == now.day && t.month == now.month && t.year == now.year) return '${two(t.hour)}:${two(t.minute)}';
  return '${two(t.day)}/${two(t.month)}';
}

class _BubbleRow extends StatelessWidget {
  const _BubbleRow({super.key, required this.n});
  final Notif n;

  Future<void> _open(BuildContext context) async {
    final ok = await Native.openNotif(n.key);
    if (!ok && context.mounted) toast(context, 'No se ha podido abrir la notificación');
  }

  @override
  Widget build(BuildContext context) {
    final title = n.title.isEmpty ? n.app : n.title;
    return Dismissible(
      key: ValueKey('d${n.key}'),
      onDismissed: (_) => app.dropNotif(n.key),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: .6 + .4 * v, alignment: Alignment.centerLeft, child: child),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            GestureDetector(onTap: () => _open(context), child: AppIcon(pkg: n.pkg, size: 34)),
            Flexible(
              child: GestureDetector(
                onTap: () => _open(context),
                child: CustomPaint(
                  painter: _BubblePainter(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 9, 10, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                        const SizedBox(width: 6),
                        Text(_when(n.time), style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 11)),
                      ]),
                      if (n.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 13.5, height: 1.25)),
                        ),
                      if (n.reply)
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => quickReply(context, n),
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(20)),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.reply, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text('Responder', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bocadillo de cómic: fondo blanco, borde negro y pico apuntando al icono de la app.
class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tail = 12.0;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(tail, 0, size.width - tail - 1, size.height - 1), const Radius.circular(16));
    final pico = Path()
      ..moveTo(tail + 2, size.height - 26)
      ..lineTo(1, size.height - 6)
      ..lineTo(tail + 18, size.height - 12)
      ..close();
    final shape = Path.combine(PathOperation.union, Path()..addRRect(body), pico);
    canvas.drawShadow(shape, Colors.black, 4, false);
    canvas.drawPath(shape, Paint()..color = Colors.white);
    canvas.drawPath(
      shape,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> quickReply(BuildContext context, Notif n) async {
  final c = TextEditingController();
  final text = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSheet,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 10, 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIcon(pkg: n.pkg, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Text(n.title.isEmpty ? n.app : n.title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (n.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(n.text, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: c,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
              decoration: const InputDecoration(hintText: 'Escribe tu respuesta'),
            ),
          ),
          IconButton.filled(onPressed: () => Navigator.of(ctx).pop(c.text), icon: const Icon(Icons.send)),
        ]),
      ]),
    ),
  );
  if (text == null || text.trim().isEmpty) return;
  final ok = await Native.replyNotif(n.key, text.trim());
  if (!context.mounted) return;
  if (ok) {
    toast(context, 'Respuesta enviada');
  } else {
    toast(context, 'No se ha podido responder desde aquí. Abriendo la conversación…');
    await Native.openNotif(n.key);
  }
}
