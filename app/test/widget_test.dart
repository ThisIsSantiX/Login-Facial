import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_login_app/main.dart';

void main() {
  testWidgets('La pantalla de login muestra el botón de entrar',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Entrar con mi rostro'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
