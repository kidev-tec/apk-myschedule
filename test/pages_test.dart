import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:minha_agenda/features/clients/clients_page.dart';
import 'package:minha_agenda/features/services/services_page.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('pt', 'BR')],
    home: child,
  );
}

void main() {
  setUpAll(() {
    // FlutterSecureStorage: method channel não disponível em testes →
    // mock in-memory. O interceptor de token lê null e segue sem header.
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('ClientsPage: API falha → empty state com CTA', (tester) async {
    // Sem mock de rede: dio lança no GET /clients, página cai no catch e
    // mostra empty state — é exatamente o comportamento de erro esperado.
    await tester.pumpWidget(_wrap(const ClientsPage()));
    await tester.pump(); // loading spinner
    await tester.pumpAndSettle();

    expect(find.text('Nenhum cliente ainda'), findsOneWidget);
    expect(find.text('Toque em + pra adicionar o primeiro'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);
  });

  testWidgets('ClientsPage: renderiza AppBar com busca e FAB', (tester) async {
    await tester.pumpWidget(_wrap(const ClientsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets); // appbar + FAB
  });

  testWidgets('ServicesPage: API falha → empty state com CTA',
      (tester) async {
    await tester.pumpWidget(_wrap(const ServicesPage()));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Nenhum serviço ainda'), findsOneWidget);
    expect(find.text('Toque em + pra criar o primeiro'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.content_cut_outlined), findsOneWidget);
  });

  testWidgets('ServicesPage: renderiza AppBar', (tester) async {
    await tester.pumpWidget(_wrap(const ServicesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Serviços'), findsOneWidget);
  });
}
