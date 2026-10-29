import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/cep/cep_service.dart';
import 'package:minha_agenda/features/clients/client_profile_fields.dart';

void main() {
  testWidgets('CEP ignora resposta antiga e mantém a busca atual pendente',
      (tester) async {
    final first = Completer<CepAddress?>();
    final second = Completer<CepAddress?>();
    final data = ClientProfileData();
    addTearDown(data.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Form(
                    child: ClientProfileFields(
      data: data,
      cepService: CepService(
          lookupOverride: (zip) =>
              zip == '17012000' ? first.future : second.future),
    ))))));
    final zip = find.byKey(const Key('client-zip'));
    await tester.ensureVisible(zip);
    await tester.enterText(zip, '17012000');
    await tester.pump();
    await tester.enterText(zip, '01001000');
    await tester.pump();
    first.complete(const CepAddress(
        street: 'Antiga', district: '', city: 'Bauru', state: 'SP'));
    await tester.pump();
    expect(data.city.text, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    second.complete(const CepAddress(
        street: 'Nova', district: '', city: 'São Paulo', state: 'SP'));
    await tester.pumpAndSettle();
    expect(data.city.text, 'São Paulo');
    expect(data.street.text, 'Nova');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('CEP editado para incompleto invalida a resposta pendente',
      (tester) async {
    final pending = Completer<CepAddress?>();
    final data = ClientProfileData();
    addTearDown(data.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Form(
                    child: ClientProfileFields(
      data: data,
      cepService: CepService(lookupOverride: (_) => pending.future),
    ))))));
    final zip = find.byKey(const Key('client-zip'));
    await tester.ensureVisible(zip);
    await tester.enterText(zip, '17012000');
    await tester.pump();
    await tester.enterText(zip, '1701200');
    await tester.pump();
    pending.complete(const CepAddress(
        street: 'Antiga', district: '', city: 'Bauru', state: 'SP'));
    await tester.pumpAndSettle();
    expect(data.city.text, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
