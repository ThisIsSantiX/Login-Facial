import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'design.dart';
import 'face_scan.dart';

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
        // Transiciones simples: menos trabajo para GPUs débiles.
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        }),
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => user == null ? const LoginScreen() : HomeScreen(user: user),
      ));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: BezierBackground(
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: Colors.white),
          ),
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
    ..showSnackBar(SnackBar(content: Text(e.toString())));
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
        // Falló la autenticación biométrica: sugiere entrar con usuario+PIN.
        setState(() => _useUsername = true);
        final msg = e.message.replaceAll(RegExp(r'\.+$'), '');
        showError(context, '$msg. Entra con tu usuario y PIN.');
      } else {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithPin() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      showError(context, 'Escribe tu usuario.');
      return;
    }
    if (_pin.text.length != 4) {
      showError(context, 'Escribe tu PIN de 4 dígitos.');
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
      if (mounted) showError(context, e);
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
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              const _ScreenHeader(
                title: 'Face Login',
                subtitle: 'Entra con tu rostro o con tu usuario y PIN',
              ),
              const SizedBox(height: 28),
              BezierCard(
                child: _useUsername ? _buildPinForm() : const ScanInfo(),
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(shape: const BezierButtonShape()),
                onPressed: _busy ? null : _login,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_useUsername ? 'Entrar' : 'Entrar con mi rostro'),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _useUsername = !_useUsername),
                    child: Text(
                      _useUsername
                          ? 'Entrar con mi rostro'
                          : 'Usar usuario y PIN',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            ),
                    child: const Text('Crear cuenta'),
                  ),
                ],
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
        const SizedBox(height: 16),
        TextField(
          controller: _username,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          textInputAction: TextInputAction.next,
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pin,
          decoration: const InputDecoration(
            labelText: 'PIN (4 dígitos)',
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

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      showError(context, 'Escribe tu usuario.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
      showError(context, 'El PIN debe tener 4 dígitos.');
      return;
    }
    final photos = await FaceScanScreen.open(context);
    if (photos == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.register(username, _pin.text, photos);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada. Ya puedes entrar.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BezierBackground(
        child: Stack(
          children: [
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                children: [
                  const _ScreenHeader(
                    title: 'Crear cuenta',
                    subtitle:
                        'Elige tu usuario, un PIN de 4 dígitos y registra tu rostro',
                    icon: Icons.person_add_alt_1,
                  ),
                  const SizedBox(height: 28),
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
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pin,
                          decoration: const InputDecoration(
                            labelText: 'PIN (4 dígitos)',
                            helperText:
                                'Lo usarás para entrar sin escanear tu rostro',
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    style:
                        FilledButton.styleFrom(shape: const BezierButtonShape()),
                    onPressed: _busy ? null : _register,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Registrar mi rostro'),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topLeft,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Volver',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Api.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: BezierBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_user, size: 72, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Hola, ${user.fullName}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('@${user.username}'),
            ],
          ),
        ),
      ),
    );
  }
}
