import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/api/api_client.dart';
import 'package:minha_agenda/core/segment/segment_preset.dart';
import 'package:minha_agenda/features/settings/theme_page.dart';
import 'package:minha_agenda/main.dart' show segmentPresetProvider;
import 'package:minha_agenda/theme/theme_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DioAdapter adapter;
  late ApiClient api;
  final patches = <dynamic>[];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    patches.clear();
    final dio = Dio(BaseOptions(baseUrl: 'http://mock.local'));
    adapter = DioAdapter(dio: dio);
    api = ApiClient(adapter: adapter);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PATCH') patches.add(o.data);
      h.next(o);
    }));
    adapter.onPatch('/me', (s) => s.reply(200, {'ok': true}),
        data: Matchers.any);
  });

  Future<ProviderContainer> pump(WidgetTester tester, {Color? current}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      segmentPresetProvider.overrideWith((_) => SegmentPreset.byId('barber')),
      themeColorProvider.overrideWith((_) => current),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/theme', routes: [
      GoRoute(path: '/theme', builder: (_, __) => ThemePage(api: api)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('salvar aplica a cor enviada mesmo se a seleção mudar',
      (tester) async {
    final pending = Completer<void>();
    api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) async {
      if (o.method == 'PATCH') await pending.future;
      h.next(o);
    }));
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Roxo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar tema'));
    await tester.pump();
    await tester.tap(find.byTooltip('Azul AGENVA'));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(patches.single, {'theme_color': '#5E35B1'});
    expect(c.read(themeColorProvider), const Color(0xFF5E35B1));
  });

  testWidgets('sair da página durante o salvamento não acessa ref descartado',
      (tester) async {
    final pending = Completer<void>();
    api.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) async {
      if (o.method == 'PATCH') await pending.future;
      h.next(o);
    }));
    await pump(tester);
    await tester.tap(find.text('Salvar tema'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    final messages = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = original);
    pending.complete();
    await tester.pumpAndSettle();
    debugPrint = original;
    expect(messages.where((m) => m.contains('[tema] falha')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao salvar preserva a mensagem da API e a cor atual',
      (tester) async {
    adapter.onPatch('/me', (s) => s.reply(422, {'error': 'Cor indisponível'}),
        data: Matchers.any);
    final c = await pump(tester, current: const Color(0xFF5E35B1));
    await tester.tap(find.byTooltip('Azul AGENVA'));
    await tester.tap(find.text('Salvar tema'));
    await tester.pumpAndSettle();
    expect(find.text('Cor indisponível'), findsOneWidget);
    expect(c.read(themeColorProvider), const Color(0xFF5E35B1));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Salvar tema'))
            .onPressed,
        isNotNull);
  });

  testWidgets('mostra a cor do segmento e a paleta', (tester) async {
    await pump(tester);
    expect(find.text('Cor do segmento (Barbearia)'), findsOneWidget);
    for (final o in themePalette) {
      expect(find.byTooltip(o.name), findsOneWidget);
    }
  });

  testWidgets('escolher cor e salvar: PATCH /me + tema do app muda',
      (tester) async {
    final c = await pump(tester);
    await tester.tap(find.byTooltip('Roxo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar tema'));
    await tester.pumpAndSettle();

    expect(patches.single, {'theme_color': '#5E35B1'});
    expect(c.read(themeColorProvider), const Color(0xFF5E35B1));
  });

  testWidgets('voltar pra cor do segmento envia null', (tester) async {
    final c = await pump(tester, current: const Color(0xFF5E35B1));
    await tester.tap(find.text('Cor do segmento (Barbearia)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar tema'));
    await tester.pumpAndSettle();

    expect(patches.single, {'theme_color': null});
    expect(c.read(themeColorProvider), isNull);
  });
}
