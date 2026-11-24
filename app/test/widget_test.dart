import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_login_app/design.dart';
import 'package:face_login_app/legal_documents.dart';
import 'package:face_login_app/legal_screen.dart';
import 'package:face_login_app/main.dart';

void main() {
  testWidgets(
    'La pantalla de login muestra el botón de entrar y enlaces legales',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      expect(find.text('Entrar con mi rostro'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
      final legalLinks = tester.widget<LegalLinksText>(
        find.byType(LegalLinksText),
      );
      expect(legalLinks.linkColor, const Color(0xFF1A237E));
      expect(legalLinks.style?.color, const Color(0xFF37474F));
    },
  );

  testWidgets('El formulario PIN valida antes de entrar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Usar usuario y PIN'));
    await tester.pump();
    expect(find.text('Entrar'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Escribe tu usuario.'), findsOneWidget);
  });

  testWidgets(
    'El registro exige aceptar términos y la opción de IA empieza apagada',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      expect(find.text('Datos'), findsOneWidget);
      expect(find.text('Rostro'), findsOneWidget);
      expect(
        tester.widget<LegalLinksText>(find.byType(LegalLinksText)).linkColor,
        const Color(0xFF1A237E),
      );

      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));
      expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isFalse);
      expect(tester.widget<Checkbox>(checkboxes.at(1)).value, isFalse);

      await tester.enterText(find.byType(TextField).at(0), 'usuario1');
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(find.text('Registrar mi rostro'), findsOneWidget);
      expect(find.textContaining('Opcional: autorizo'), findsOneWidget);

      await tester.tap(find.text('Registrar mi rostro'));
      await tester.pump();
      expect(
        find.text('Debes aceptar los términos y la privacidad.'),
        findsOneWidget,
      );

      await tester.tap(checkboxes.at(0));
      await tester.pump();
      expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isTrue);
      expect(tester.widget<Checkbox>(checkboxes.at(1)).value, isFalse);
    },
  );

  testWidgets('La política de privacidad muestra versión y secciones', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LegalScreen(document: LegalDocument.privacy)),
    );
    expect(find.text(privacyTitle), findsOneWidget);
    expect(find.text('Versión $legalVersion'), findsOneWidget);
    expect(find.text('1. Responsable del tratamiento'), findsOneWidget);
    expect(privacySections.last.title, '13. Contacto');
  });
}
