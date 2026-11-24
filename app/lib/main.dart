import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'design.dart';
import 'face_scan.dart';
import 'legal_documents.dart';
import 'legal_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo vertical: simplifica la rotación de la cámara para el detector.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FaceLoginApp());
}

class FaceLoginApp extends StatelessWidget {
  const FaceLoginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Login',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF3F51B5),
          foregroundColor: Colors.white,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      home: const StartScreen(),
    );
  }
}

/// Revisa si hay sesión guardada y decide a qué pantalla ir.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    Api.restoreSession().then((user) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              user == null ? const LoginScreen() : HomeScreen(user: user),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BezierBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIconBadge(
                  icon: Icons.face_retouching_natural,
                  size: 96,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Face Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verificando tu sesión…',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icono + texto explicativo. Va dentro de una BezierCard.
class ScanInfo extends StatelessWidget {
  const ScanInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.face_retouching_natural, size: 40, color: scheme.primary),
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Se abrirá la cámara. Mira de frente, parpadea y gira la cabeza '
            'cuando te lo indique. Las fotos se toman solas.',
          ),
        ),
      ],
    );
  }
}

/// Encabezado centrado (icono en círculo + título + subtítulo) para la
/// zona índigo del fondo.
class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader({
    required this.title,
    required this.subtitle,
    this.icon = Icons.face,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          AppIconBadge(icon: icon, size: 72),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(e.toString())),
          ],
        ),
      ),
    );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  // Por defecto se entra con el rostro; si el reconocimiento falla, se
  // sugiere entrar con usuario y PIN (sin escáner).
  bool _useUsername = false;

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_useUsername) {
      await _loginWithPin();
      return;
    }
    setState(() => _error = null);
    final photos = await FaceScanScreen.open(context);
    if (photos == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final user = await Api.identify(photos);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 401) {
        setState(() {
          _useUsername = true;
          final msg = e.message.replaceAll(RegExp(r'\.+$'), '');
          _error = '$msg. Entra con tu usuario y PIN.';
        });
      } else {
        setState(() => _error = e.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithPin() async {
    setState(() => _error = null);
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Escribe tu usuario.');
      return;
    }
    if (_pin.text.length != 4) {
      setState(() => _error = 'Escribe tu PIN de 4 dígitos.');
      return;
    }
    setState(() => _busy = true);
    try {
      final user = await Api.loginPin(username, _pin.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(user: user)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BezierBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            children: [
              const _ScreenHeader(
                title: 'Face Login',
                subtitle: 'Entra con tu rostro o con tu usuario y PIN',
              ),
              const SizedBox(height: 26),
              if (_error != null)
                AppInlineNotice(
                  message: _error!,
                  onRetry: _busy ? null : _login,
                ),
              BezierCard(
                child: _useUsername ? _buildPinForm() : const ScanInfo(),
              ),
              const SizedBox(height: 24),
              PrimaryActionButton(
                label: _useUsername ? 'Entrar' : 'Entrar con mi rostro',
                icon: _useUsername
                    ? Icons.login
                    : Icons.face_retouching_natural,
                loading: _busy,
                onPressed: _login,
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _useUsername = !_useUsername),
                    icon: Icon(
                      _useUsername ? Icons.face : Icons.keyboard_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _useUsername
                          ? 'Entrar con mi rostro'
                          : 'Usar usuario y PIN',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Crear cuenta'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: LegalLinksText(
                  prefix: '',
                  onTermsTap: () => LegalScreen.openTerms(context),
                  onPrivacyTap: () => LegalScreen.openPrivacy(context),
                  style: const TextStyle(
                    color: Color(0xFF37474F),
                    fontSize: 13,
                  ),
                  linkColor: Color(0xFF1A237E),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formulario usuario + PIN (va dentro de la tarjeta Bézier).
  Widget _buildPinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Entra con tu usuario y tu PIN de 4 dígitos.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _username,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          textInputAction: TextInputAction.next,
          autocorrect: false,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pin,
          decoration: const InputDecoration(
            labelText: 'PIN (4 dígitos)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            counterText: '',
          ),
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          textInputAction: TextInputAction.done,
          onSubmitted: _busy ? null : (_) => _loginWithPin(),
        ),
      ],
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _acceptedTerms = false;
  bool _aiImprovement = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _error = null);
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Escribe tu usuario.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      setState(() => _error = 'El PIN debe tener 4 dígitos.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = 'Debes aceptar los términos y la privacidad.');
      return;
    }
    final photos = await FaceScanScreen.open(context);
    if (photos == null || !mounted) return;
    setState(() => _busy = true);
    final consent = ConsentInfo(
      termsAccepted: true,
      termsVersion: legalVersion,
      aiImprovementOptIn: _aiImprovement,
      consentAt: DateTime.now().toUtc(),
    );
    try {
      await Api.register(username, _pin.text, photos, consent);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada. Ya puedes entrar.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BezierBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  ),
                  const Expanded(child: _RegisterProgress()),
                ],
              ),
              const SizedBox(height: 16),
              const _ScreenHeader(
                title: 'Crear cuenta',
                subtitle: 'Elige tu usuario, un PIN y registra tu rostro',
                icon: Icons.person_add_alt_1,
              ),
              const SizedBox(height: 24),
              if (_error != null) AppInlineNotice(message: _error!),
              BezierCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ScanInfo(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'Usuario',
                        helperText: 'De 3 a 30: letras, números o _',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pin,
                      decoration: const InputDecoration(
                        labelText: 'PIN (4 dígitos)',
                        helperText:
                            'Lo usarás para entrar sin escanear tu rostro',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _busy ? null : (_) => _register(),
                    ),
                    const SizedBox(height: 12),
                    ConsentCheckbox(
                      value: _acceptedTerms,
                      enabled: !_busy,
                      onChanged: (value) =>
                          setState(() => _acceptedTerms = value ?? false),
                      label: LegalLinksText(
                        onTermsTap: () => LegalScreen.openTerms(context),
                        onPrivacyTap: () => LegalScreen.openPrivacy(context),
                        linkColor: const Color(0xFF1A237E),
                      ),
                    ),
                    ConsentCheckbox(
                      value: _aiImprovement,
                      enabled: !_busy,
                      onChanged: (value) =>
                          setState(() => _aiImprovement = value ?? false),
                      label: const Text(
                        'Opcional: autorizo usar una copia seudonimizada de mi plantilla biométrica para mejorar la IA.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryActionButton(
                label: 'Registrar mi rostro',
                icon: Icons.face_retouching_natural,
                loading: _busy,
                onPressed: _register,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterProgress extends StatelessWidget {
  const _RegisterProgress();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _ProgressStep(icon: Icons.edit_outlined, label: 'Datos', active: true),
        Expanded(child: Divider(color: Colors.white54, height: 2)),
        _ProgressStep(
          icon: Icons.face_outlined,
          label: 'Rostro',
          active: false,
        ),
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: active ? Colors.white : Colors.white24,
          child: Icon(
            icon,
            size: 16,
            color: active ? const Color(0xFF3F51B5) : Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _aiImprovement = false;
  bool _savingConsent = false;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    final consent = await Api.loadConsent();
    if (!mounted) return;
    setState(() => _aiImprovement = consent?.aiImprovementOptIn ?? false);
  }

  Future<void> _toggleAiConsent(bool value) async {
    setState(() => _savingConsent = true);
    try {
      await Api.updateAiConsent(value);
      if (!mounted) return;
      setState(() => _aiImprovement = value);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final names = user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = names.take(2).map((part) => part[0]).join().toUpperCase();

    return Scaffold(
      body: BezierBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bienvenido',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hola, ${user.fullName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              BezierCard(
                child: Column(
                  children: [
                    const AppIconBadge(icon: Icons.verified_user, size: 72),
                    const SizedBox(height: 16),
                    const Text(
                      'Acceso biométrico activo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '@${user.username}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    const AppStatusChip(
                      icon: Icons.lock_outline,
                      label: 'Sesión segura',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              BezierCard(
                child: Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Consejo: mantén buena luz al escanear tu rostro para un reconocimiento más rápido.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              BezierCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Privacidad y permisos',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LegalLinksText(
                      prefix: '',
                      onTermsTap: () => LegalScreen.openTerms(context),
                      onPrivacyTap: () => LegalScreen.openPrivacy(context),
                      linkColor: const Color(0xFF1A237E),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.smart_toy_outlined, color: scheme.primary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Mejorar IA con embeddings seudonimizados. Puedes revocarlo aquí.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        Switch(
                          value: _aiImprovement,
                          onChanged: _savingConsent
                              ? null
                              : (value) => _toggleAiConsent(value),
                        ),
                      ],
                    ),
                    if (_savingConsent)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: const BezierButtonShape(),
                  ),
                  onPressed: () async {
                    await Api.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
