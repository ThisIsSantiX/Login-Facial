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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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
  bool _opening = false;
  bool _processing = false;
  bool _capturing = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

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
    _pulseController.dispose();
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

  void _reset() {
    _step = _Step.center;
    _front = null;
    _sawEyesClosed = false;
    _readySince = null;
    _timedOut = false;
    _faceOk = false;
    _cameraError = null;
    _hint = _camera == null
        ? 'Preparando la cámara…'
        : 'Ubica tu rostro dentro del óvalo';
    _deadline = DateTime.now().add(_timeLimit);
    if (_pulseController.isAnimating) _pulseController.reset();
  }

  void _start() {
    _reset();
    if (_camera == null) _openCamera();
  }

  void _retry() {
    setState(_reset);
    if (_camera == null) _openCamera();
  }

  Future<void> _openCamera() async {
    if (_opening || _camera != null) return;
    setState(() {
      _opening = true;
      _cameraError = null;
      _hint = 'Preparando la cámara…';
    });
    CameraController? camera;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'Este teléfono no tiene cámara.');
        }
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      camera = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await camera.initialize();
      final opened = camera;
      if (!mounted) {
        await opened.dispose();
        return;
      }
      await opened.startImageStream(_onFrame);
      if (!mounted) {
        await opened.dispose();
        return;
      }
      setState(() {
        _camera = opened;
        _cameraError = null;
        _hint = 'Ubica tu rostro dentro del óvalo';
      });
    } catch (e) {
      await camera?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraError = e is CameraException
            ? e.code.contains('Access')
                  ? 'Necesitamos permiso para usar la cámara.'
                  : 'No se pudo abrir la cámara. Inténtalo de nuevo.'
            : 'No se pudo abrir la cámara. Inténtalo de nuevo.';
      });
    } finally {
      _opening = false;
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

    if (ok && !_faceOk) _pulseController.forward(from: 0);
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
    final showError = _cameraError != null || _timedOut;

    return Scaffold(
      backgroundColor: const Color(0xFF070A18),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null && camera.value.isInitialized)
            _FullScreenPreview(camera: camera)
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A237E), Color(0xFF070A18)],
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99070A18),
                  Colors.transparent,
                  Color(0xB3070A18),
                ],
              ),
            ),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) => CustomPaint(
                painter: _OvalMaskPainter(
                  color: ovalColor,
                  progress: _pulseController.value,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Cancelar',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Escaneo facial',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Sigue las instrucciones',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: Colors.white70,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Seguro',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (!showError) _StepDots(step: _step),
                const Spacer(),
                if (showError)
                  _ScannerNotice(
                    icon: _cameraError != null
                        ? Icons.videocam_off_outlined
                        : Icons.timer_off_outlined,
                    title: _cameraError != null
                        ? 'No pudimos abrir la cámara'
                        : 'Tiempo agotado',
                    message: _cameraError ?? 'No detectamos tu rostro a tiempo. Revisa la luz e inténtalo de nuevo.',
                    color: _cameraError != null ? scheme.error : Colors.amber,
                    onRetry: _retry,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        key: ValueKey(_hint),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          _hint,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wb_sunny_outlined,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Busca buena luz y quítate gafas oscuras o gorra.',
                          style: TextStyle(
                            color: scheme.surfaceContainerHighest,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
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
  _OvalMaskPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

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
    if (progress > 0) {
      canvas.drawOval(
        oval.inflate(8 + 14 * progress),
        Paint()
          ..color = color.withValues(alpha: (1 - progress) * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_OvalMaskPainter old) =>
      old.color != color || old.progress != progress;
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Centrar', 'Parpadeo', 'Giro'];
    const icons = [
      Icons.face_outlined,
      Icons.remove_red_eye_outlined,
      Icons.rotate_right_outlined,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Container(
                width: 18,
                height: 2,
                color: i <= step.index ? Colors.greenAccent : Colors.white24,
              ),
            _StepDot(
              icon: icons[i],
              label: labels[i],
              done: i < step.index,
              current: i == step.index,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.icon,
    required this.label,
    required this.done,
    required this.current,
  });

  final IconData icon;
  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final Color background = done
        ? Colors.greenAccent
        : current
        ? Colors.white
        : Colors.white24;
    final Color foreground = done
        ? Colors.black
        : current
        ? const Color(0xFF1A237E)
        : Colors.white70;
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: background,
          child: Icon(done ? Icons.check : icon, size: 15, color: foreground),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: current || done ? Colors.white : Colors.white60,
            fontSize: 10,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ScannerNotice extends StatelessWidget {
  const _ScannerNotice({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: const StadiumBorder(),
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Intentar de nuevo'),
          ),
        ],
      ),
    );
  }
}
