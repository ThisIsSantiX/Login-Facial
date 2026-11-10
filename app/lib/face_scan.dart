import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'api.dart';

/// Escaneo facial en tiempo real, al estilo de las apps bancarias.
///
/// La cámara muestra una vista previa en vivo y ML Kit detecta la cara en el
/// propio teléfono, cuadro por cuadro. La app guía a la persona (centrar,
/// parpadear, girar) y toma las fotos sola cuando la cara está en posición.
/// Las dos fotos van al servidor, que es quien decide de verdad: el chequeo
/// del teléfono solo sirve para guiar y para no enviar fotos inútiles.
///
/// Para teléfonos de gama baja: resolución media, ML Kit en modo rápido sin
/// contornos ni puntos, y se descartan cuadros mientras se procesa uno.
class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key});

  /// Abre el escáner y devuelve las fotos, o null si la persona cancela.
  static Future<FacePhotos?> open(BuildContext context) {
    return Navigator.of(context).push<FacePhotos>(
      MaterialPageRoute(builder: (_) => const FaceScanScreen()),
    );
  }

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

enum _Step { center, blink, turn, done }

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  static const _timeLimit = Duration(seconds: 40);
  // Ángulo (grados) que se considera "de frente" y "cabeza girada".
  static const _maxFrontalYaw = 12.0;
  static const _minTurnedYaw = 25.0;
  // Tiempo que la cara debe quedarse quieta en posición antes de capturar.
  static const _holdStill = Duration(milliseconds: 700);

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableClassification: true, // probabilidad de ojos abiertos
      minFaceSize: 0.25,
    ),
  );

  CameraController? _camera;
  String? _cameraError;
  bool _processing = false;
  bool _capturing = false;

  _Step _step = _Step.center;
  String _hint = 'Preparando la cámara…';
  bool _faceOk = false;
  DateTime? _readySince;
  bool _sawEyesClosed = false;
  Uint8List? _front;
  late DateTime _deadline;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  /// Libera la cámara al salir de la app: en equipos con poca RAM es clave.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _openCamera();
    }
  }

  void _start() {
    _step = _Step.center;
    _front = null;
    _sawEyesClosed = false;
    _readySince = null;
    _timedOut = false;
    _deadline = DateTime.now().add(_timeLimit);
    if (_camera == null) _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'Este teléfono no tiene cámara.');
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await camera.initialize();
      if (!mounted) {
        camera.dispose();
        return;
      }
      await camera.startImageStream(_onFrame);
      setState(() {
        _camera = camera;
        _cameraError = null;
        _hint = 'Ubica tu rostro dentro del óvalo';
      });
    } on CameraException catch (e) {
      setState(() {
        _cameraError = e.code.contains('Access')
            ? 'Necesitamos permiso para usar la cámara.'
            : 'No se pudo abrir la cámara.';
      });
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null || image.planes.length != 1) return null;
    final rotation = InputImageRotationValue.fromRawValue(
      camera.description.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _onFrame(CameraImage image) async {
    // Si aún se procesa el cuadro anterior, este se descarta.
    if (_processing || _capturing || _step == _Step.done || _timedOut) return;
    if (DateTime.now().isAfter(_deadline)) {
      setState(() {
        _timedOut = true;
        _hint = 'Se acabó el tiempo';
      });
      return;
    }
    final input = _toInputImage(image);
    if (input == null) return;

    _processing = true;
    try {
      final faces = await _detector.processImage(input);
      // La imagen llega acostada; tras rotarla, alto y ancho se intercambian.
      final rotated = (_camera?.description.sensorOrientation ?? 0) % 180 != 0;
      final frameWidth = (rotated ? image.height : image.width).toDouble();
      final frameHeight = (rotated ? image.width : image.height).toDouble();
      if (mounted) _evaluate(faces, frameWidth, frameHeight);
    } catch (_) {
      // Un cuadro que falla no importa: llega otro enseguida.
    } finally {
      _processing = false;
    }
  }

  void _evaluate(List<Face> faces, double frameWidth, double frameHeight) {
    String hint;
    var ok = false;

    if (faces.isEmpty) {
      hint = 'Ubica tu rostro dentro del óvalo';
    } else if (faces.length > 1) {
      hint = 'Solo debe aparecer una persona';
    } else {
      final face = faces.first;
      final box = face.boundingBox;
      final size = box.width / frameWidth;
      final dx = (box.center.dx / frameWidth - 0.5).abs();
      final dy = (box.center.dy / frameHeight - 0.5).abs();
      final yaw = face.headEulerAngleY ?? 0;
      final roll = face.headEulerAngleZ ?? 0;
      final leftEye = face.leftEyeOpenProbability ?? 1;
      final rightEye = face.rightEyeOpenProbability ?? 1;

      if (size < 0.30) {
        hint = 'Acércate un poco';
      } else if (size > 0.85) {
        hint = 'Aléjate un poco';
      } else if (dx > 0.18 || dy > 0.2) {
        hint = 'Centra tu rostro en el óvalo';
      } else {
        switch (_step) {
          case _Step.center:
            if (yaw.abs() > _maxFrontalYaw || roll.abs() > 12) {
              hint = 'Mira de frente a la cámara';
            } else if (leftEye < 0.5 || rightEye < 0.5) {
              hint = 'Mantén los ojos abiertos';
            } else {
              hint = 'No te muevas…';
              ok = true;
            }
          case _Step.blink:
            // Primero se ven los ojos cerrados y luego abiertos de nuevo.
            if (leftEye < 0.25 && rightEye < 0.25) {
              _sawEyesClosed = true;
            } else if (_sawEyesClosed && leftEye > 0.6 && rightEye > 0.6) {
              HapticFeedback.selectionClick();
              _step = _Step.turn;
              _readySince = null;
            }
            hint = _step == _Step.blink
                ? 'Parpadea'
                : 'Gira la cabeza despacio hacia un lado';
          case _Step.turn:
            if (yaw.abs() < _minTurnedYaw) {
              hint = 'Gira la cabeza despacio hacia un lado';
            } else {
              hint = 'Así, quieto…';
              ok = true;
            }
          case _Step.done:
            hint = 'Listo';
        }
      }
    }

    // Se captura solo si la cara se mantiene en posición un momento.
    if (ok) {
      _readySince ??= DateTime.now();
      final hold = _step == _Step.turn ? _holdStill ~/ 2 : _holdStill;
      if (DateTime.now().difference(_readySince!) >= hold) _capture();
    } else {
      _readySince = null;
    }

    if (hint != _hint || ok != _faceOk) {
      setState(() {
        _hint = hint;
        _faceOk = ok;
      });
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _capturing) return;
    _capturing = true;
    try {
      final photo = await (await camera.takePicture()).readAsBytes();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (_step == _Step.center) {
        setState(() {
          _front = photo;
          _step = _Step.blink;
          _sawEyesClosed = false;
          _readySince = null;
          _faceOk = false;
          _hint = 'Parpadea';
        });
      } else if (_step == _Step.turn && _front != null) {
        setState(() => _step = _Step.done);
        await camera.stopImageStream();
        if (mounted) Navigator.of(context).pop(FacePhotos(_front!, photo));
      }
    } on CameraException {
      _readySince = null; // se reintenta con el siguiente cuadro
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final scheme = Theme.of(context).colorScheme;
    final ovalColor = _faceOk ? Colors.greenAccent : Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            _FullScreenPreview(camera: camera)
          else if (_cameraError == null)
            const Center(child: CircularProgressIndicator()),
          // RepaintBoundary: el óvalo no se redibuja con cada cuadro de la cámara.
          RepaintBoundary(
            child: CustomPaint(painter: _OvalMaskPainter(color: ovalColor)),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Cancelar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                _StepDots(step: _step),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _cameraError ?? _hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (_timedOut)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: FilledButton(
                      onPressed: () => setState(_start),
                      child: const Text('Intentar de nuevo'),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Busca buena luz y quítate gafas oscuras o gorra.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.surfaceContainerHighest),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista previa que llena la pantalla sin deformarse (recorta lo que sobra).
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final size = camera.value.previewSize;
    if (size == null) return CameraPreview(camera);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize viene en horizontal; la app está en vertical.
          width: size.height,
          height: size.width,
          child: CameraPreview(camera),
        ),
      ),
    );
  }
}

/// Oscurece todo menos un óvalo en el centro, donde va la cara.
class _OvalMaskPainter extends CustomPainter {
  _OvalMaskPainter({required this.color});

  final Color color;

  static Rect ovalRect(Size size) {
    final width = size.width * 0.72;
    final height = math.min(width * 1.32, size.height * 0.6);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.48),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final oval = ovalRect(size);
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.6));
    canvas.drawOval(
      oval,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_OvalMaskPainter old) => old.color != color;
}

/// Tres puntos que muestran el avance: de frente, parpadeo, giro.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    const labels = ['De frente', 'Parpadeo', 'Giro'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Icon(
                  i < step.index ? Icons.check_circle : Icons.circle_outlined,
                  color: i <= step.index ? Colors.greenAccent : Colors.white54,
                  size: 20,
                ),
                Text(
                  labels[i],
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
