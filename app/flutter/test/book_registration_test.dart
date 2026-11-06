import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/book_registration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('checks password confirmation and allows returning to login',
      (tester) async {
    var returned = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BookRegistration(
                uri: Uri.https('example.invalid', '/api/asystec/register'),
                onBack: () => returned = true,
                onRegistered: () => fail('Invalid input was accepted')))));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'soporte');
    await tester.enterText(fields.at(1), 'password-de-prueba');
    await tester.enterText(fields.at(2), 'diferente');
    await tester.tap(find.text('Crear cuenta'));
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    await tester.tap(find.text('Volver'));
    expect(returned, isTrue);
  });
}
