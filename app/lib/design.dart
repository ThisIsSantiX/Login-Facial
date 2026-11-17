import 'package:flutter/material.dart';

/// Fondo decorativo con degradado y ondas Bézier.
///
/// Es estático: se pinta una sola vez dentro de un RepaintBoundary, así que
/// no gasta CPU ni batería en equipos de gama baja.
class BezierBackground extends StatelessWidget {
  const BezierBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: CustomPaint(painter: _BezierBackgroundPainter()),
        ),
        child,
      ],
    );
  }
}

class _BezierBackgroundPainter extends CustomPainter {
  const _BezierBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Degradado: índigo arriba (zona del encabezado) que se disuelve en
    // fondo claro antes de las tarjetas y el botón.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF3F51B5),
          Color(0xFF5C6BC0),
          Color(0xFFEDF0FB),
          Color(0xFFFDFDFF),
        ],
        stops: [0.0, 0.20, 0.34, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Onda clara 1: banda translúcida cuyo borde superior es una cúbica.
    final wave1 = Path()
      ..moveTo(0, h * 0.14)
      ..cubicTo(w * 0.28, h * 0.22, w * 0.55, h * 0.10, w, h * 0.18)
      ..lineTo(w, h * 0.32)
      ..lineTo(0, h * 0.32)
      ..close();
    canvas.drawPath(wave1, Paint()..color = Colors.white.withValues(alpha: 0.20));

    // Onda clara 2: más abajo y más tenue, para el efecto de capas.
    final wave2 = Path()
      ..moveTo(0, h * 0.24)
      ..cubicTo(w * 0.35, h * 0.17, w * 0.62, h * 0.31, w, h * 0.23)
      ..lineTo(w, h * 0.38)
      ..lineTo(0, h * 0.38)
      ..close();
    canvas.drawPath(wave2, Paint()..color = Colors.white.withValues(alpha: 0.16));

    // Acento índigo abajo, muy tenue, para cerrar la composición.
    final wave3 = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.3, h * 0.82, w * 0.55, h * 0.95, w, h * 0.87)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      wave3,
      Paint()..color = const Color(0xFF3F51B5).withValues(alpha: 0.07),
    );
  }

  @override
  bool shouldRepaint(covariant _BezierBackgroundPainter old) => false;
}

/// Recorte con esquinas asimétricas hechas con curvas cúbicas.
class BezierCardClipper extends CustomClipper<Path> {
  const BezierCardClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final big = 28.0; // esquina superior izquierda e inferior derecha
    final small = 12.0; // esquina superior derecha e inferior izquierda
    return Path()
      ..moveTo(big, 0)
      ..lineTo(w - small, 0)
      ..cubicTo(w - small * 0.15, 0, w, small * 0.15, w, small)
      ..lineTo(w, h - big)
      ..cubicTo(w, h - big * 0.15, w - big * 0.15, h, w - big, h)
      ..lineTo(small, h)
      ..cubicTo(small * 0.15, h, 0, h - small * 0.15, 0, h - small)
      ..lineTo(0, big)
      ..cubicTo(0, big * 0.15, big * 0.15, 0, big, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Tarjeta con el recorte Bézier (sustituye al Card plano).
class BezierCard extends StatelessWidget {
  const BezierCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipPath(
      clipper: const BezierCardClipper(),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

/// Forma orgánica (asimétrica) para el botón principal.
class BezierButtonShape extends OutlinedBorder {
  const BezierButtonShape({super.side = BorderSide.none});

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final x = rect.left;
    final y = rect.top;
    final w = rect.width;
    final h = rect.height;
    final r = h / 2;
    return Path()
      ..moveTo(x + r, y)
      ..lineTo(x + w - r, y)
      // Derecha: curva suave casi redondeada.
      ..cubicTo(x + w - r * 0.12, y, x + w, y + r * 0.3, x + w, y + r)
      ..cubicTo(x + w, y + h - r * 0.3, x + w - r * 0.12, y + h, x + w - r, y + h)
      ..lineTo(x + r, y + h)
      // Izquierda: entrada más pronunciada (asimetría Bézier).
      ..cubicTo(x + r * 0.3, y + h, x, y + h - r * 0.55, x, y + r)
      ..cubicTo(x, y + r * 0.45, x + r * 0.3, y, x + r, y)
      ..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      BezierButtonShape(side: side ?? this.side);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side == BorderSide.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => BezierButtonShape(side: side.scale(t));
}
