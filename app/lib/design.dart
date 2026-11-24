import 'package:flutter/gestures.dart';
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

    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.65, -0.72),
        radius: 0.65,
        colors: [Colors.white.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);

    // Onda clara 1: banda translúcida cuyo borde superior es una cúbica.
    final wave1 = Path()
      ..moveTo(0, h * 0.14)
      ..cubicTo(w * 0.28, h * 0.22, w * 0.55, h * 0.10, w, h * 0.18)
      ..lineTo(w, h * 0.32)
      ..lineTo(0, h * 0.32)
      ..close();
    canvas.drawPath(
      wave1,
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );

    // Onda clara 2: más abajo y más tenue, para el efecto de capas.
    final wave2 = Path()
      ..moveTo(0, h * 0.24)
      ..cubicTo(w * 0.35, h * 0.17, w * 0.62, h * 0.31, w, h * 0.23)
      ..lineTo(w, h * 0.38)
      ..lineTo(0, h * 0.38)
      ..close();
    canvas.drawPath(
      wave2,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );

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
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x1A1A237E),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipPath(
        clipper: const BezierCardClipper(),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
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
      ..cubicTo(
        x + w,
        y + h - r * 0.3,
        x + w - r * 0.12,
        y + h,
        x + w - r,
        y + h,
      )
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

class AppIconBadge extends StatelessWidget {
  const AppIconBadge({super.key, required this.icon, this.size = 68});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7986CB), Color(0xFF3949AB)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x471A237E),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.46),
    );
  }
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.icon,
    required this.label,
    this.active = true,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    super.key,
    required this.message,
    this.isError = true,
    this.onRetry,
  });

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : Colors.green.shade700;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final Widget content = loading
        ? const SizedBox.square(
            key: ValueKey(true),
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Colors.white,
            ),
          )
        : Row(
            key: const ValueKey(false),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 20),
              if (icon != null) const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
    return SizedBox(
      width: expanded ? double.infinity : null,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          shape: const BezierButtonShape(),
          elevation: 2,
          shadowColor: const Color(0x331A237E),
        ),
        onPressed: loading ? null : onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: content,
        ),
      ),
    );
  }
}

class LegalLinksText extends StatelessWidget {
  const LegalLinksText({
    super.key,
    required this.onTermsTap,
    required this.onPrivacyTap,
    this.prefix = 'Acepto ',
    this.style,
    this.linkColor,
    this.textAlign = TextAlign.start,
  });

  final VoidCallback onTermsTap;
  final VoidCallback onPrivacyTap;
  final String prefix;
  final TextStyle? style;
  final Color? linkColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? TextStyle(color: scheme.onSurface, fontSize: 13);
    final link = TextStyle(
      color: linkColor ?? const Color(0xFF1A237E),
      fontSize: base.fontSize,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationThickness: 1.5,
    );
    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: 'Términos y Condiciones',
            style: link,
            recognizer: TapGestureRecognizer()..onTap = onTermsTap,
          ),
          const TextSpan(text: ' y '),
          TextSpan(
            text: 'Política de Privacidad',
            style: link,
            recognizer: TapGestureRecognizer()..onTap = onPrivacyTap,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Checkbox(
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9, bottom: 4),
            child: label,
          ),
        ),
      ],
    );
  }
}
