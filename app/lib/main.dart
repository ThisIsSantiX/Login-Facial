import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'design.dart';
import 'face_scan.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Solo vertical: simplifica la rotaciÃ³n de la cÃ¡mara para el detector.
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
        // Transiciones simples: menos trabajo para GPUs dÃ©biles.
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        }),
      ),
      home: const StartScreen(),
    );
  }
}

/// Revisa si hay sesiÃ³n guardada y decide a quÃ© pantalla ir.
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

/// Explica en una tarjeta lo que va a pasar al escanear.
class ScanInfo extends StatelessWidget {
  const ScanInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BezierCard(
      child: Row(
        children: [
          Icon(Icons.face_retouching_natural, size: 40, color: scheme.primary),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Se abrirÃ¡ la cÃ¡mara. Mira de frente, parpadea y gira la cabeza '
              'cuando te lo pida. Las fotos se toman solas.',
            ),
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
  // sugiere entrar con usuario y PIN (sin escÃ¡ner).
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
        // FallÃ³ la autenticaciÃ³n biomÃ©trica: sugiere entrar con usuario+PIN.
        setState(() => _useUsername = true);
        showError(context, '${e.message}. Entra con tu usuario y PIN.');
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
      showError(context, 'Escribe tu PIN de 4 dÃ­gitos.');
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
      appBar: AppBar(
        title: const Text('Iniciar sesiÃ³n'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: BezierBackground(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_useUsername) ...[
              const SizedBox(height: 8),
              const Text(
                'Entra con tu usuario y tu PIN de 4 dÃ­gitos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _username,
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
                  labelText: 'PIN (4 dÃ­gitos)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  counterText: '',
                ),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                textInputAction: TextInputAction.done,
              ),
            ] else
              const ScanInfo(),
            const SizedBox(height: 24),
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
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => _useUsername = !_useUsername),
              child: Text(
                _useUsername ? 'Entrar solo con mi rostro' : 'Usar mi usuario',
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
      ),
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
      showError(context, 'El PIN debe tener 4 dÃ­gitos.');
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
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: BezierBackground(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const ScanInfo(),
            const SizedBox(height: 24),
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                helperText: 'Letras, nÃºmeros o _ (3 a 30)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pin,
              decoration: const InputDecoration(
                labelText: 'PIN (4 dÃ­gitos)',
                helperText: 'Lo usarÃ¡s para entrar sin escanear el rostro',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                counterText: '',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(shape: const BezierButtonShape()),
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
            tooltip: 'Cerrar sesiÃ³n',
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
