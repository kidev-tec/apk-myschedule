import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'core/api/api_client.dart';
import 'core/segment/segment_preset.dart';
import 'core/storage/onboarding_store.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/agenda/agenda_page.dart';
import 'features/agenda/booking_wizard.dart';
import 'features/clients/clients_page.dart';
import 'features/clients/client_form_page.dart';
import 'features/services/services_page.dart';
import 'features/services/service_form_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/working_hours_page.dart';
import 'features/settings/push_init_service.dart';
import 'features/terms/terms_page.dart';
import 'theme/app_theme.dart';

/// Segmento ativo do negócio (persistido; null = beauty default).
final segmentPresetProvider = StateProvider<SegmentPreset?>((ref) => null);

/// FutureProvider que carrega o segmento do negócio UMA VEZ no bootstrap.
/// Usado no main() para aguardar o tema ANTES de runApp — elimina flash de cor errada.
final segmentBootstrapProvider = FutureProvider<SegmentPreset?>((ref) async {
  try {
    final dio = ApiClient().dio;
    final r = await dio.get('/me');
    final id = r.data['business_type'] as String?;
    debugPrint('[tema bootstrap] GET /me → business_type=$id');
    if (id != null) return SegmentPreset.byId(id);
  } catch (e) {
    debugPrint('[tema bootstrap] falhou: $e');
  }
  return null; // default beauty
});

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final isAuthenticated = authState.isAuthenticated;
      final isAuthRoute = state.matchedLocation == '/login';
      final isOnboardingRoute = state.matchedLocation == '/onboarding';

      // Se não autenticado e não está em rota de auth -> login
      if (!isAuthenticated && !isAuthRoute && !isOnboardingRoute) {
        return '/login';
      }

      // Se autenticado e está em login -> onboarding (1ª vez) ou agenda
      if (isAuthenticated && isAuthRoute) {
        // Onboarding só na PRIMEIRA vez — flag persistida sobrevive a restart
        final done = await OnboardingStore.isComplete();
        return done ? '/agenda' : '/onboarding';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/terms',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TermsPage(isPrivacy: extra?['isPrivacy'] == true);
        },
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/agenda',
        builder: (_, __) => const AgendaPage(),
        routes: [
          GoRoute(
            path: 'booking',
            builder: (_, __) => const BookingWizardPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/clients',
        builder: (_, __) => const ClientsPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const ClientFormPage(),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (_, state) =>
                ClientFormPage(clientId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/working-hours',
        builder: (_, __) => const WorkingHoursPage(),
      ),
      GoRoute(
        path: '/services',
        builder: (_, __) => const ServicesPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, __) => const ServiceFormPage(),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (_, state) =>
                ServiceFormPage(serviceId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsPage(),
      ),
    ],
  );
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);

  // Push (FCM)
  FirebaseMessaging.onBackgroundMessage(
      PushInitService.firebaseMessagingBackgroundHandler);
  PushInitService().init(
    onForegroundMessage: (title, body) {
      debugPrint('[push:fg] $title — $body');
    },
  );

  // Bootstrap do tema: carrega segmento ANTES de runApp pra evitar flash rosa
  final container = ProviderContainer();
  final segment = await container.read(segmentBootstrapProvider.future);
  if (segment != null) {
        container.read(segmentPresetProvider.notifier).state = segment;
        debugPrint('[tema bootstrap] segmento aplicado: ${segment.id} (0x${segment.primary.value.toRadixString(16)})');
      } else {
        debugPrint('[tema bootstrap] usando default beauty');
      }

  runApp(UncontrolledProviderScope(container: container, child: const MinhaAgendaApp()));
}

class MinhaAgendaApp extends ConsumerWidget {
  const MinhaAgendaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AGENVA',
      debugShowCheckedModeBanner: false,
      // Conteúdo nunca fica atrás da barra de gestos (home/voltar) nem da
      // status bar — vale pra todas as telas que não usam SafeArea própria.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: mq.padding.bottom + 8),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: buildAppTheme(ref.watch(segmentPresetProvider)),
      darkTheme: buildAppTheme(ref.watch(segmentPresetProvider))
          .copyWith(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
    );
  }
}
