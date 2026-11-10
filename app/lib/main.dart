import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
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
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Explica en una tarjeta lo que va a pasar al escanear.
class ScanInfo extends StatelessWidget {
  const ScanInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.face_retouching_natural, size: 40, color: scheme.primary),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Se abrirá la cámara. Mira de frente, parpadea y gira la cabeza '
                'cuando te lo pida. Las fotos se toman solas.',
              ),
            ),
          ],
        ),
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
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_username.text.trim().isEmpty) {
      showError(context, 'Escribe tu usuario.');
      return;
    }
    final photos = await FaceScanScreen.open(context);
    if (photos == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final user = await Api.login(_username.text.trim(), photos);
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
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const ScanInfo(),
          const SizedBox(height: 24),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Entrar con mi rostro'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
            child: const Text('Crear cuenta'),
          ),
        ],
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
  final _fullName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_username.text.trim().isEmpty || _fullName.text.trim().isEmpty) {
      showError(context, 'Completa tu nombre y usuario.');
      return;
    }
    final photos = await FaceScanScreen.open(context);
    if (photos == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.register(
        _username.text.trim(),
        _fullName.text.trim(),
        photos,
      );
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
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const ScanInfo(),
          const SizedBox(height: 24),
          TextField(
            controller: _fullName,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              helperText: 'Letras, números o _ (3 a 30)',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          FilledButton(
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
      body: Center(
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
    );
  }
}
