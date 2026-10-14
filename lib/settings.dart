import 'package:flutter/material.dart';

import 'native.dart';
import 'pages.dart' show aiKeyDialog;
import 'state.dart';
import 'ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        backgroundColor: kExBg,
        appBar: AppBar(backgroundColor: kExBg, title: const Text('Personalizar')),
        body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Usar Abanico como pantalla de inicio'),
            subtitle: const Text('Elige «Abanico» en la app de inicio predeterminada', style: TextStyle(color: kDim)),
            onTap: Native.homeSettings,
          ),
          const _H('Fondo'),
          SizedBox(
            height: 128,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final e in wallPresets.entries)
                _WallChoice(
                  label: e.value.name,
                  selected: app.wallpaperFile == null && app.wallpaper == e.key,
                  onTap: () => app.setPreset(e.key),
                  child: WallPreview(preset: e.value),
                ),
              _WallChoice(
                label: 'Tu foto',
                selected: app.wallpaperFile != null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WallpaperPicker())),
                child: Container(color: kField, child: const Icon(Icons.add_photo_alternate_outlined, color: kDim)),
              ),
            ]),
          ),
          const _H('Iconos'),
          _SliderRow(
            label: 'Tamaño',
            value: app.iconSize,
            min: 56,
            max: 96,
            shown: '${app.iconSize.round()}',
            onChanged: (v) {
              app.iconSize = v;
              app.changed();
            },
          ),
          _SliderRow(
            label: 'Esquinas',
            value: app.radius,
            min: .1,
            max: .5,
            shown: '${(app.radius * 100).round()}%',
            onChanged: (v) {
              app.radius = v;
              app.changed();
            },
          ),
          const _H('Cajones'),
          for (final d in app.drawers)
            ListTile(
              leading: DrawerTile(id: d.id, size: 40, shadow: false),
              title: Text(d.name),
              trailing: const Icon(Icons.chevron_right, color: kDim),
              onTap: () => _editDrawer(context, d),
            ),
          const _H('Archivos'),
          SwitchListTile(
            title: const Text('Doble panel con el móvil desplegado'),
            subtitle: const Text('Dos carpetas lado a lado en pantallas anchas', style: TextStyle(color: kDim)),
            value: app.dual,
            onChanged: (v) {
              app.dual = v;
              app.changed();
            },
          ),
          SwitchListTile(
            title: const Text('Mostrar archivos ocultos'),
            value: app.showHidden,
            onChanged: (v) {
              app.showHidden = v;
              app.changed();
            },
          ),
          const _H('Inteligencia artificial'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Clave de API de Claude'),
            subtitle: Text(app.apiKey.isEmpty ? 'Sin configurar' : 'Configurada · modelo ${app.model}', style: const TextStyle(color: kDim)),
            onTap: () => aiKeyDialog(context),
          ),
          const _H('Otros'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Volver a leer apps, fotos y documentos'),
            onTap: () {
              app.refreshAll();
              toast(context, 'Actualizando…');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: kDanger),
            title: const Text('Restablecer aspecto', style: TextStyle(color: kDanger)),
            subtitle: const Text('Fondo, iconos y cajones vuelven a como estaban', style: TextStyle(color: kDim)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: kSheet,
                  title: const Text('¿Restablecer el aspecto?'),
                  content: const Text('Tus enlaces, carpetas ancladas y la clave de la IA se mantienen.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Restablecer')),
                  ],
                ),
              );
              if (ok == true) app.resetLook();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _editDrawer(BuildContext context, DrawerCfg d) async {
    final name = TextEditingController(text: d.name);
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
                Tile(size: 44, colors: pal(d.color), icon: iconFor(d.icon), shadow: false),
                const SizedBox(width: 12),
                const Text('Editar cajón', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                maxLength: 18,
                decoration: const InputDecoration(labelText: 'Nombre'),
                onChanged: (v) {
                  d.name = v.trim().isEmpty ? defaultDrawers().firstWhere((x) => x.id == d.id).name : v.trim();
                  app.changed();
                },
              ),
              const SizedBox(height: 8),
              IconColorPicker(
                icon: d.icon,
                color: d.color,
                onIcon: (v) => set(() {
                  d.icon = v;
                  app.changed();
                }),
                onColor: (v) => set(() {
                  d.color = v;
                  app.changed();
                }),
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Listo'))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1, color: kDim, fontWeight: FontWeight.w600)),
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.shown, required this.onChanged});
  final String label;
  final double value, min, max;
  final String shown;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)),
          SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.right, style: const TextStyle(color: kDim))),
        ]),
      );
}

class _WallChoice extends StatelessWidget {
  const _WallChoice({required this.label, required this.selected, required this.onTap, required this.child});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 78,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? kGlow : Colors.transparent, width: 2.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                child,
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black45,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

class WallpaperPicker extends StatefulWidget {
  const WallpaperPicker({super.key});
  @override
  State<WallpaperPicker> createState() => _WallpaperPickerState();
}

class _WallpaperPickerState extends State<WallpaperPicker> {
  @override
  void initState() {
    super.initState();
    if (!app.photosAllowed || app.recentPhotos.isEmpty) app.loadPhotos();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final photos = app.recentPhotos;
        return Scaffold(
          backgroundColor: kExBg,
          appBar: AppBar(backgroundColor: kExBg, title: const Text('Elige una foto de fondo')),
          body: !app.photosAllowed
              ? Center(child: FilledButton(onPressed: () => app.loadPhotos(), child: const Text('Permitir acceso a fotos')))
              : GridView.builder(
                  padding: const EdgeInsets.all(4),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 3, crossAxisSpacing: 3),
                  itemCount: photos.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () async {
                      final f = await photos[i].file;
                      if (f == null) return;
                      await app.setWallpaperFile(f);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: LayoutBuilder(builder: (_, c) => PhotoThumb(asset: photos[i], size: c.maxWidth, rounded: false)),
                  ),
                ),
        );
      },
    );
  }
}
