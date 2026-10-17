// Control con la cabeza: la cámara frontal mueve un cursor por la pantalla
// y los gestos de la cara hacen clic, abren el abanico o vuelven atrás.
// Solo Android (usa ML Kit de Google para detectar la cara, todo en el móvil).
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fan.dart';
import 'platform.dart';
import 'ui.dart';

/// Gestos que se pueden asignar a cada acción.
const headGestures = <String, String>{
  'boca': 'Abrir la boca',
  'cejas': 'Levantar las cejas',
  'nariz': 'Abrir las aletas de la nariz',
  'sonrisa': 'Sonreír',
  'guino': 'Guiñar un ojo',
  'ninguno': 'Ninguno',
};

/// Acciones que hace el control con la cabeza.
const headActions = <String, String>{
  'click': 'Clic',
  'hold': 'Mantener pulsado / girar abanico',
  'back': 'Atrás / cerrar',
};

enum HeadStatus { off, starting, running, noPermission, error }

class HeadMouse extends ChangeNotifier with WidgetsBindingObserver {
  // ---------------- Ajustes (se guardan en el móvil) ----------------
  bool enabled = false;
  double sens = 1.2; // velocidad del cursor
  double gestureSens = 1.0; // facilidad para detectar gestos
  bool dwell = false; // clic al quedarse quieto
  bool invertX = false;
  bool invertY = false;
  int camIndex = 0; // qué cámara frontal usar (los plegables tienen dos)
  final Map<String, String> map = {'click': 'boca', 'hold': 'cejas', 'back': 'ninguno'};

  // ---------------- Estado en vivo ----------------
  HeadStatus status = HeadStatus.off;
  String? message;
  bool face = false;
  int frontCams = 0;
  bool calibrating = false;

  // Diagnóstico (se ve en los ajustes del control con la cabeza).
  final ValueNotifier<String> diag = ValueNotifier('');
  int _frames = 0, _faceFrames = 0, _noFace = 0, _rotFix = 0;
  String? _lastError;
  String _imgInfo = '';
  CameraController? get camera => _cam;

  void _updateDiag() {
    diag.value = 'Fotogramas: $_frames · con cara: $_faceFrames\n'
        'Imagen: $_imgInfo · corrección de giro: $_rotFix°'
        '${_lastError != null ? '\nError: $_lastError' : ''}';
  }
  final ValueNotifier<Offset> cursor = ValueNotifier(Offset.zero);
  final ValueNotifier<double> dwellProgress = ValueNotifier(0);
  final ValueNotifier<bool> pressing = ValueNotifier(false);

  /// Fuerza de cada gesto (1.0 = se dispara). Para las barras de ajustes.
  final ValueNotifier<Map<String, double>> meters = ValueNotifier(const {});

  GlobalKey<NavigatorState>? navKey;
  SharedPreferences? _prefs;
  CameraController? _cam;
  CameraDescription? _desc;
  FaceDetector? _detector;
  bool _busy = false;
  bool _starting = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // Postura y gestos de referencia (cara en reposo mirando al centro).
  double _yaw0 = 0, _pitch0 = 0, _gap0 = 0, _brow0 = 1, _nose0 = 1, _smile0 = 0;
  final List<List<double>> _calib = [];
  // Valores suavizados.
  double? _gap, _brow, _nose;
  Offset _pos = Offset.zero;
  bool _posInit = false;

  // Gestos: cuántos fotogramas seguidos supera el umbral y si ya se disparó.
  final Map<String, int> _over = {};
  final Set<String> _latched = {};
  DateTime _lastAction = DateTime.fromMillisecondsSinceEpoch(0);

  // Clic al quedarse quieto y desplazamiento al empujar contra un borde.
  Offset? _dwellAnchor;
  DateTime? _dwellStart;
  bool _dwellArmed = true;
  String? _edge;
  DateTime? _edgeStart;
  DateTime _lastEdge = DateTime.fromMillisecondsSinceEpoch(0);

  // Punteros sintéticos.
  static const _mouseDevice = 9100;
  static const _touchDevice = 9101;
  int _pointer = 91000;
  bool _mouseAdded = false;
  final Stopwatch _clock = Stopwatch()..start();

  bool get supported => isAndroid;

  Future<void> init(GlobalKey<NavigatorState> nav) async {
    navKey = nav;
    if (!supported) return;
    WidgetsBinding.instance.addObserver(this);
    final p = _prefs = await SharedPreferences.getInstance();
    enabled = p.getBool('head.enabled') ?? false;
    sens = p.getDouble('head.sens') ?? sens;
    gestureSens = p.getDouble('head.gsens') ?? gestureSens;
    dwell = p.getBool('head.dwell') ?? false;
    invertX = p.getBool('head.invX') ?? false;
    invertY = p.getBool('head.invY') ?? false;
    camIndex = p.getInt('head.cam') ?? 0;
    for (final a in headActions.keys) {
      final g = p.getString('head.map.$a');
      if (g != null && headGestures.containsKey(g)) map[a] = g;
    }
    if (enabled) {
      // Se arranca cuando ya hay pantalla dibujada.
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setBool('head.enabled', enabled);
    p.setDouble('head.sens', sens);
    p.setDouble('head.gsens', gestureSens);
    p.setBool('head.dwell', dwell);
    p.setBool('head.invX', invertX);
    p.setBool('head.invY', invertY);
    p.setInt('head.cam', camIndex);
    for (final e in map.entries) {
      p.setString('head.map.${e.key}', e.value);
    }
  }

  /// Cambia un ajuste y lo guarda.
  void update(void Function() f) {
    f();
    _save();
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    _save();
    if (v) {
      await _start();
    } else {
      await _stop();
      status = HeadStatus.off;
      message = null;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (frontCams < 2) return;
    camIndex = (camIndex + 1) % frontCams;
    _save();
    await _stop();
    await _start();
  }

  /// Vuelve a tomar como "centro" la postura actual de la cabeza.
  void recenter() {
    _calib.clear();
    calibrating = true;
    _posInit = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _stop(keepStatus: true);
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  // ======================================================================
  // Cámara
  // ======================================================================
  Future<void> _start() async {
    if (!supported || _starting || _cam != null) return;
    _starting = true;
    status = HeadStatus.starting;
    message = null;
    notifyListeners();
    try {
      final cams = await availableCameras();
      final fronts = cams.where((c) => c.lensDirection == CameraLensDirection.front).toList();
      frontCams = fronts.length;
      if (cams.isEmpty) throw CameraException('NoCamera', 'No hay cámara');
      final desc = fronts.isEmpty ? cams.first : fronts[camIndex % fronts.length];
      final cam = CameraController(desc, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await cam.initialize();
      _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableClassification: true,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.15,
        ),
      );
      if (!enabled) {
        await cam.dispose();
        return;
      }
      _cam = cam;
      _desc = desc;
      await cam.startImageStream(_onFrame);
      status = HeadStatus.running;
      if (!calibrating && _calib.isEmpty && _yaw0 == 0 && _pitch0 == 0) recenter();
      _addMouse();
    } on CameraException catch (e) {
      final denied = e.code.contains('AccessDenied') || e.code.contains('Permission');
      status = denied ? HeadStatus.noPermission : HeadStatus.error;
      message = denied
          ? 'Abanico no tiene permiso para usar la cámara. Dáselo en Ajustes → Aplicaciones → Abanico → Permisos.'
          : 'No se pudo abrir la cámara (${e.description ?? e.code}).';
      await _stop(keepStatus: true);
    } catch (e) {
      status = HeadStatus.error;
      message = 'No se pudo abrir la cámara ($e).';
      await _stop(keepStatus: true);
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _stop({bool keepStatus = false}) async {
    final cam = _cam;
    _cam = null;
    face = false;
    pressing.value = false;
    dwellProgress.value = 0;
    _removeMouse();
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) await cam.stopImageStream();
      } catch (_) {}
      try {
        await cam.dispose();
      } catch (_) {}
    }
    if (!keepStatus) status = HeadStatus.off;
    notifyListeners();
  }

  void _onFrame(CameraImage img) {
    if (_busy) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 33) return; // máx. ~30 por segundo
    _lastFrame = now;
    _busy = true;
    _process(img).whenComplete(() => _busy = false);
  }

  static const _orient = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _toInput(CameraImage img) {
    final cam = _cam, desc = _desc;
    if (cam == null || desc == null) return null;
    var comp = _orient[cam.value.deviceOrientation] ?? 0;
    comp = desc.lensDirection == CameraLensDirection.front
        ? (desc.sensorOrientation + comp) % 360
        : (desc.sensorOrientation - comp + 360) % 360;
    comp = (comp + _rotFix) % 360;
    final rotation = InputImageRotationValue.fromRawValue(comp) ?? InputImageRotation.rotation0deg;
    final size = Size(img.width.toDouble(), img.height.toDouble());
    _imgInfo = '${img.width}×${img.height}, ${img.planes.length} plano(s), giro $comp°';
    if (img.planes.length == 1) {
      final p = img.planes.first;
      return InputImage.fromBytes(
        bytes: p.bytes,
        metadata: InputImageMetadata(size: size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: p.bytesPerRow),
      );
    }
    if (img.planes.length == 3) {
      return InputImage.fromBytes(
        bytes: _yuvToNv21(img),
        metadata: InputImageMetadata(size: size, rotation: rotation, format: InputImageFormat.nv21, bytesPerRow: img.width),
      );
    }
    return null;
  }

  /// Por si la cámara entrega YUV en tres planos: lo junta en NV21.
  Uint8List _yuvToNv21(CameraImage img) {
    final w = img.width, h = img.height;
    final out = Uint8List(w * h + 2 * (w ~/ 2) * (h ~/ 2));
    final y = img.planes[0], u = img.planes[1], v = img.planes[2];
    var o = 0;
    for (var r = 0; r < h; r++) {
      final start = r * y.bytesPerRow;
      out.setRange(o, o + w, y.bytes, start);
      o += w;
    }
    final ups = u.bytesPerPixel ?? 1, vps = v.bytesPerPixel ?? 1;
    for (var r = 0; r < h ~/ 2; r++) {
      for (var c = 0; c < w ~/ 2; c++) {
        final vi = r * v.bytesPerRow + c * vps;
        final ui_ = r * u.bytesPerRow + c * ups;
        out[o++] = vi < v.bytes.length ? v.bytes[vi] : 128;
        out[o++] = ui_ < u.bytes.length ? u.bytes[ui_] : 128;
      }
    }
    return out;
  }

  Future<void> _process(CameraImage img) async {
    final det = _detector;
    if (det == null || _cam == null) return;
    _frames++;
    InputImage? input;
    try {
      input = _toInput(img);
    } catch (e) {
      _lastError = 'imagen: $e';
    }
    if (input == null) {
      if (_frames % 10 == 0) _updateDiag();
      return;
    }
    List<Face> faces;
    try {
      faces = await det.processImage(input);
    } catch (e) {
      _lastError = 'detector: $e';
      if (_frames % 10 == 0) _updateDiag();
      return;
    }
    if (_frames % 10 == 0) _updateDiag();
    if (_cam == null) return;
    if (faces.isEmpty) {
      // Si en un buen rato no aparece ninguna cara, prueba otro giro de la imagen
      // (algunos móviles, sobre todo plegables, informan mal la orientación de la cámara).
      if (++_noFace >= 25 && _faceFrames == 0) {
        _noFace = 0;
        _rotFix = (_rotFix + 90) % 360;
      }
      if (face) {
        face = false;
        notifyListeners();
      }
      return;
    }
    _noFace = 0;
    _faceFrames++;
    final big = faces.reduce((a, b) => a.boundingBox.width * a.boundingBox.height >= b.boundingBox.width * b.boundingBox.height ? a : b);
    if (!face) {
      face = true;
      notifyListeners();
    }
    _onFace(big);
  }

  // ======================================================================
  // De la cara a cursor y gestos
  // ======================================================================
  static Offset? _centroid(Face f, FaceContourType t) {
    final pts = f.contours[t]?.points;
    if (pts == null || pts.isEmpty) return null;
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.x;
      y += p.y;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  static double _ema(double? old, double v, double a) => old == null ? v : old + (v - old) * a;

  ui.FlutterView get _view => WidgetsBinding.instance.platformDispatcher.views.first;

  Size get _screen {
    final v = _view;
    return v.physicalSize / v.devicePixelRatio;
  }

  void _onFace(Face f) {
    final yaw = f.headEulerAngleY ?? 0;
    final pitch = f.headEulerAngleX ?? 0;

    final le = _centroid(f, FaceContourType.leftEye);
    final re = _centroid(f, FaceContourType.rightEye);
    final iod = (le != null && re != null) ? (le - re).distance : f.boundingBox.width * .4;
    if (iod < 4) return;

    final upper = _centroid(f, FaceContourType.upperLipBottom);
    final lower = _centroid(f, FaceContourType.lowerLipTop);
    final gap = (upper != null && lower != null) ? (lower - upper).distance / iod : 0.0;

    final lb = _centroid(f, FaceContourType.leftEyebrowTop);
    final rb = _centroid(f, FaceContourType.rightEyebrowTop);
    double brow = 1;
    if (lb != null && rb != null && le != null && re != null) {
      brow = ((lb - le).distance + (rb - re).distance) / 2 / iod;
    }

    final np = f.contours[FaceContourType.noseBottom]?.points;
    double nose = 1;
    if (np != null && np.length >= 2) {
      nose = Offset((np.first.x - np.last.x).toDouble(), (np.first.y - np.last.y).toDouble()).distance / iod;
    }

    final smile = f.smilingProbability ?? 0;
    final lo = f.leftEyeOpenProbability ?? 1, ro = f.rightEyeOpenProbability ?? 1;

    _gap = _ema(_gap, gap, .5);
    _brow = _ema(_brow, brow, .45);
    _nose = _ema(_nose, nose, .4);

    // --- Calibración: unos fotogramas con la cara quieta mirando al centro.
    if (calibrating) {
      _calib.add([yaw, pitch, _gap!, _brow!, _nose!, smile]);
      if (_calib.length >= 15) {
        double avg(int i) => _calib.map((e) => e[i]).reduce((a, b) => a + b) / _calib.length;
        _yaw0 = avg(0);
        _pitch0 = avg(1);
        _gap0 = avg(2);
        _brow0 = max(.05, avg(3));
        _nose0 = max(.05, avg(4));
        _smile0 = avg(5);
        calibrating = false;
        _calib.clear();
        _over.clear();
        _latched.clear();
        notifyListeners();
      }
      final s = _screen;
      _pos = Offset(s.width / 2, s.height / 2);
      _posInit = true;
      cursor.value = _pos;
      return;
    }

    // --- Fuerza de cada gesto (1.0 = umbral).
    final k = gestureSens;
    final wink = (max(lo, ro) > .6 && min(lo, ro) < .25) ? 1.3 : 0.0;
    final m = <String, double>{
      'boca': (_gap! - _gap0) / (.22 / k),
      'cejas': (_brow! / _brow0 - 1) / (.12 / k),
      'nariz': (_nose! / _nose0 - 1) / (.07 / k),
      'sonrisa': (smile - _smile0) / (max(.2, .8 - _smile0) / k),
      'guino': wink,
    };
    meters.value = m;

    // Mientras se hace un gesto, el cursor se queda quieto (abrir la boca mueve la cabeza).
    final used = map.values.where((g) => g != 'ninguno').toSet();
    var gesturing = false;
    for (final g in used) {
      if ((m[g] ?? 0) > .45) gesturing = true;
    }
    final sinceAction = DateTime.now().difference(_lastAction).inMilliseconds;

    // --- Cursor
    final s = _screen;
    if (!_posInit) {
      _pos = Offset(s.width / 2, s.height / 2);
      _posInit = true;
    }
    if (!gesturing && sinceAction > 250) {
      final rangeX = 22 / sens, rangeY = 14 / sens;
      final dx = (invertX ? 1 : -1) * (yaw - _yaw0) / rangeX;
      final dy = (invertY ? 1 : -1) * (pitch - _pitch0) / rangeY;
      final target = Offset(
        (s.width / 2 + dx * s.width / 2).clamp(0.0, s.width - 1),
        (s.height / 2 + dy * s.height / 2).clamp(0.0, s.height - 1),
      );
      final dist = (target - _pos).distance;
      final a = (.16 + dist / 500).clamp(.16, .7);
      final next = _pos + (target - _pos) * a;
      if ((next - _pos).distance > .4) {
        _pos = next;
        cursor.value = _pos;
        _hover();
      }
    }

    // --- Gestos → acciones
    for (final action in headActions.keys) {
      final g = map[action];
      if (g == null || g == 'ninguno') continue;
      final v = m[g] ?? 0;
      if (v >= 1) {
        _over[g] = (_over[g] ?? 0) + 1;
        if (_over[g]! >= 2 && !_latched.contains(g) && sinceAction > 350) {
          _latched.add(g);
          _fire(action);
        }
      } else {
        _over[g] = 0;
        if (v < .55) _latched.remove(g);
      }
    }

    _checkDwell();
    _checkEdges(s);
  }

  void _fire(String action) {
    _lastAction = DateTime.now();
    _dwellArmed = false;
    dwellProgress.value = 0;
    HapticFeedback.lightImpact();
    switch (action) {
      case 'click':
        click();
      case 'hold':
        hold();
      case 'back':
        back();
    }
  }

  void _checkDwell() {
    if (!dwell) {
      dwellProgress.value = 0;
      return;
    }
    final now = DateTime.now();
    final a = _dwellAnchor;
    if (a == null || (_pos - a).distance > 22) {
      if (a != null && (_pos - a).distance > 40) _dwellArmed = true;
      _dwellAnchor = _pos;
      _dwellStart = now;
      dwellProgress.value = 0;
      return;
    }
    if (!_dwellArmed) return;
    const ms = 1100;
    final t = now.difference(_dwellStart!).inMilliseconds;
    dwellProgress.value = (t / ms).clamp(0.0, 1.0);
    if (t >= ms) {
      _dwellArmed = false;
      dwellProgress.value = 0;
      _lastAction = now;
      HapticFeedback.lightImpact();
      click();
    }
  }

  /// Empujar el cursor contra un borde un rato desplaza la pantalla (páginas, listas).
  void _checkEdges(Size s) {
    String? e;
    if (_pos.dx <= 2) {
      e = 'left';
    } else if (_pos.dx >= s.width - 3) {
      e = 'right';
    } else if (_pos.dy <= 2) {
      e = 'top';
    } else if (_pos.dy >= s.height - 3) {
      e = 'bottom';
    }
    final now = DateTime.now();
    if (e == null || e != _edge) {
      _edge = e;
      _edgeStart = now;
      return;
    }
    if (now.difference(_edgeStart!).inMilliseconds < 700) return;
    if (now.difference(_lastEdge).inMilliseconds < 900) return;
    _lastEdge = now;
    _edgeStart = now;
    final w = s.width, h = s.height;
    switch (e) {
      case 'right':
        swipe(Offset(w * .75, h / 2), Offset(w * .2, h / 2));
      case 'left':
        swipe(Offset(w * .25, h / 2), Offset(w * .8, h / 2));
      case 'bottom':
        swipe(Offset(w / 2, h * .7), Offset(w / 2, h * .35));
      case 'top':
        swipe(Offset(w / 2, h * .3), Offset(w / 2, h * .65));
    }
  }

  // ======================================================================
  // Pulsaciones sintéticas: el cursor se comporta como un ratón
  // ======================================================================
  Duration get _ts => _clock.elapsed;

  void _send(PointerEvent e) {
    try {
      GestureBinding.instance.handlePointerEvent(e);
    } catch (_) {}
  }

  void _addMouse() {
    if (_mouseAdded) return;
    _mouseAdded = true;
    _send(PointerAddedEvent(timeStamp: _ts, kind: PointerDeviceKind.mouse, device: _mouseDevice, position: _pos, viewId: _view.viewId));
  }

  void _removeMouse() {
    if (!_mouseAdded) return;
    _mouseAdded = false;
    _send(PointerRemovedEvent(timeStamp: _ts, kind: PointerDeviceKind.mouse, device: _mouseDevice, position: _pos, viewId: _view.viewId));
  }

  Offset _lastHover = Offset.zero;
  void _hover() {
    if (!_mouseAdded || pressing.value) return;
    final d = _pos - _lastHover;
    _lastHover = _pos;
    _send(PointerHoverEvent(timeStamp: _ts, kind: PointerDeviceKind.mouse, device: _mouseDevice, position: _pos, delta: d, viewId: _view.viewId));
  }

  Future<void> _press(Duration hold) async {
    if (pressing.value) return;
    _addMouse();
    final p = _pos;
    final id = ++_pointer;
    pressing.value = true;
    _send(PointerDownEvent(
        timeStamp: _ts, pointer: id, kind: PointerDeviceKind.mouse, device: _mouseDevice, position: p, buttons: kPrimaryButton, viewId: _view.viewId));
    await Future.delayed(hold);
    _send(PointerUpEvent(timeStamp: _ts, pointer: id, kind: PointerDeviceKind.mouse, device: _mouseDevice, position: p, viewId: _view.viewId));
    pressing.value = false;
  }

  Future<void> click() => _press(const Duration(milliseconds: 60));

  /// Mantener pulsado. Si hay un abanico abierto que no cabe entero, lo gira.
  Future<void> hold() async {
    if (fan.isOpen) {
      if (fan.rotates) {
        final next = fan.offset.value.round() + 1;
        fan.offset.value = next > fan.maxOffset ? 0.0 : next.toDouble();
        HapticFeedback.selectionClick();
      }
      return;
    }
    await _press(const Duration(milliseconds: 650));
  }

  void back() {
    if (fan.isOpen) {
      fan.close();
      return;
    }
    navKey?.currentState?.maybePop();
  }

  /// Arrastre con "dedo" (las páginas y listas no se arrastran con ratón).
  Future<void> swipe(Offset from, Offset to) async {
    final id = ++_pointer;
    final v = _view.viewId;
    _send(PointerDownEvent(timeStamp: _ts, pointer: id, kind: PointerDeviceKind.touch, device: _touchDevice, position: from, viewId: v));
    const steps = 8;
    var last = from;
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(const Duration(milliseconds: 14));
      final p = Offset.lerp(from, to, Curves.easeOut.transform(i / steps))!;
      _send(PointerMoveEvent(timeStamp: _ts, pointer: id, kind: PointerDeviceKind.touch, device: _touchDevice, position: p, delta: p - last, buttons: kPrimaryButton, viewId: v));
      last = p;
    }
    _send(PointerUpEvent(timeStamp: _ts, pointer: id, kind: PointerDeviceKind.touch, device: _touchDevice, position: to, viewId: v));
  }
}

final head = HeadMouse();

// ======================================================================
// Capa por encima de todo: el cursor y el indicador de la cámara
// ======================================================================
class HeadLayer extends StatelessWidget {
  const HeadLayer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!head.supported) return child;
    return ListenableBuilder(
      listenable: head,
      child: child,
      builder: (context, child) {
        final on = head.enabled && head.status == HeadStatus.running;
        return Stack(children: [
          child!,
          if (on)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _CursorPainter(head.face && !head.calibrating)),
                ),
              ),
            ),
          if (head.enabled && head.status != HeadStatus.off)
            Positioned(
              top: MediaQuery.of(context).padding.top + 2,
              left: 0,
              right: 0,
              child: Center(child: _HeadPill()),
            ),
        ]);
      },
    );
  }
}

class _CursorPainter extends CustomPainter {
  _CursorPainter(this.visible) : super(repaint: Listenable.merge([head.cursor, head.dwellProgress, head.pressing]));
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final p = head.cursor.value;
    final down = head.pressing.value;
    final r = down ? 9.0 : 12.0;
    canvas.drawCircle(p, r + 3, Paint()..color = Colors.black.withValues(alpha: .35));
    canvas.drawCircle(p, r, Paint()..color = (down ? kGlow : Colors.white).withValues(alpha: .85));
    canvas.drawCircle(p, r, Paint()
      ..color = kGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5);
    canvas.drawCircle(p, 2.5, Paint()..color = const Color(0xFF1D1407));
    final d = head.dwellProgress.value;
    if (d > 0.02) {
      canvas.drawArc(
        Rect.fromCircle(center: p, radius: r + 8),
        -pi / 2,
        2 * pi * d,
        false,
        Paint()
          ..color = kGlow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.visible != visible;
}

class _HeadPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (head.status) {
      HeadStatus.starting => (kDim, 'Abriendo cámara…'),
      HeadStatus.noPermission => (kDanger, 'Sin permiso de cámara'),
      HeadStatus.error => (kDanger, 'Error de cámara'),
      _ => head.calibrating
          ? (kGlow, 'Mira al centro…')
          : head.face
              ? (const Color(0xFF7BD88F), 'Cabeza')
              : (kDanger, 'No te veo'),
    };
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: head.recenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xAA0C1C1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(fontSize: 11, color: kInk)),
            if (head.status == HeadStatus.running && !head.calibrating) ...[
              const SizedBox(width: 6),
              const Icon(Icons.center_focus_strong, size: 13, color: kDim),
            ],
          ]),
        ),
      ),
    );
  }
}

// ======================================================================
// Ajustes del control con la cabeza
// ======================================================================
class HeadSettingsPage extends StatelessWidget {
  const HeadSettingsPage({super.key});

  Future<void> _pickGesture(BuildContext context, String action) async {
    final g = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSheet,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Gesto para «${headActions[action]}»', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final e in headGestures.entries)
            ListTile(
              title: Text(e.value),
              subtitle: e.key == 'nariz'
                  ? const Text('Experimental: es un gesto muy pequeño, ajusta la sensibilidad de gestos', style: TextStyle(color: kDim))
                  : null,
              trailing: head.map[action] == e.key ? const Icon(Icons.check, color: kGlow) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (g == null) return;
    head.update(() {
      // Un gesto solo hace una cosa: si ya estaba en otra acción, se le quita.
      if (g != 'ninguno') {
        for (final a in head.map.keys.toList()) {
          if (a != action && head.map[a] == g) head.map[a] = 'ninguno';
        }
      }
      head.map[action] = g;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: head,
      builder: (context, _) => Scaffold(
        backgroundColor: kExBg,
        appBar: AppBar(backgroundColor: kExBg, title: const Text('Control con la cabeza')),
        body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          SwitchListTile(
            title: const Text('Activar control con la cabeza'),
            subtitle: const Text('Mueve la cabeza para mover el cursor. Solo funciona dentro de Abanico.', style: TextStyle(color: kDim)),
            value: head.enabled,
            onChanged: head.setEnabled,
          ),
          if (head.message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(head.message!, style: const TextStyle(color: kDanger)),
            ),
          ListTile(
            leading: const Icon(Icons.center_focus_strong),
            title: const Text('Recentrar'),
            subtitle: const Text('Mira al centro de la pantalla con la cara relajada. También tocando el aviso de arriba.', style: TextStyle(color: kDim)),
            enabled: head.enabled,
            onTap: head.recenter,
          ),
          if (head.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (head.camera != null && head.camera!.value.isInitialized)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: 96, height: 128, child: CameraPreview(head.camera!)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: head.diag,
                    builder: (_, t, __) => Text(t.isEmpty ? 'Esperando a la cámara…' : t, style: const TextStyle(color: kDim, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          if (head.frontCams > 1)
            ListTile(
              leading: const Icon(Icons.cameraswitch_outlined),
              title: const Text('Cambiar de cámara frontal'),
              subtitle: Text('Usando la ${head.camIndex + 1} de ${head.frontCams} (pantalla interior / exterior)', style: const TextStyle(color: kDim)),
              enabled: head.enabled,
              onTap: head.switchCamera,
            ),
          const _HH('Movimiento'),
          _Slider(
            label: 'Velocidad',
            value: head.sens,
            min: .5,
            max: 2.5,
            onChanged: (v) => head.update(() => head.sens = v),
          ),
          SwitchListTile(
            title: const Text('Invertir izquierda / derecha'),
            value: head.invertX,
            onChanged: (v) => head.update(() => head.invertX = v),
          ),
          SwitchListTile(
            title: const Text('Invertir arriba / abajo'),
            value: head.invertY,
            onChanged: (v) => head.update(() => head.invertY = v),
          ),
          const _HH('Gestos'),
          for (final a in headActions.keys)
            ListTile(
              title: Text(headActions[a]!),
              subtitle: Text(headGestures[head.map[a]] ?? 'Ninguno', style: const TextStyle(color: kGlow)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickGesture(context, a),
            ),
          SwitchListTile(
            title: const Text('Clic al quedarse quieto'),
            subtitle: const Text('Deja el cursor quieto 1 segundo sobre algo para pulsarlo', style: TextStyle(color: kDim)),
            value: head.dwell,
            onChanged: (v) => head.update(() => head.dwell = v),
          ),
          _Slider(
            label: 'Facilidad',
            value: head.gestureSens,
            min: .5,
            max: 2.5,
            onChanged: (v) => head.update(() => head.gestureSens = v),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text(
              'Haz cada gesto y mira su barra: cuando pasa la raya, se dispara. Si no llega, sube «Facilidad»; si salta solo, bájala.',
              style: TextStyle(color: kDim, fontSize: 13),
            ),
          ),
          const _Meters(),
          const _HH('Cómo se usa'),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Text(
              '• Cursor encima de un cajón: se abre su abanico.\n'
              '• Clic: abre lo que hay debajo del cursor.\n'
              '• Mantener: en un abanico grande lo gira; en el escritorio entra en edición.\n'
              '• Empuja el cursor contra un borde: pasa de página o desplaza la lista.\n'
              '• Al abrir otra app la cámara se apaga y vuelve al regresar a Abanico.',
              style: TextStyle(color: kInk, height: 1.5),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HH extends StatelessWidget {
  const _HH(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
        child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 1, color: kDim, fontWeight: FontWeight.w600)),
      );
}

class _Slider extends StatelessWidget {
  const _Slider({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)),
          SizedBox(width: 44, child: Text('${value.toStringAsFixed(1)}×', textAlign: TextAlign.right, style: const TextStyle(color: kDim))),
        ]),
      );
}

class _Meters extends StatelessWidget {
  const _Meters();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: head.meters,
      builder: (context, m, _) {
        if (!head.enabled || m.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Text('Activa el control para ver las barras.', style: TextStyle(color: kDim, fontSize: 13)),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(children: [
            for (final g in headGestures.keys.where((g) => g != 'ninguno'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 120, child: Text(headGestures[g]!.replaceFirst('Abrir las aletas de la nariz', 'Nariz'), style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: LayoutBuilder(builder: (context, c) {
                      final v = (m[g] ?? 0).clamp(0.0, 1.5) / 1.5;
                      final line = c.maxWidth / 1.5;
                      return SizedBox(
                        height: 14,
                        child: Stack(children: [
                          Container(decoration: BoxDecoration(color: kField, borderRadius: BorderRadius.circular(7))),
                          FractionallySizedBox(
                            widthFactor: v,
                            child: Container(
                              decoration: BoxDecoration(color: v >= 1 / 1.5 ? kGlow : kDim, borderRadius: BorderRadius.circular(7)),
                            ),
                          ),
                          Positioned(left: line - 1, top: 0, bottom: 0, child: Container(width: 2, color: kInk)),
                        ]),
                      );
                    }),
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
