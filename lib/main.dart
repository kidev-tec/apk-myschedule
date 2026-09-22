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
import 'features/settings/time_offs_page.dart';
import 'features/settings/waitlist_page.dart';
import 'features/services/service_form_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/working_hours_page.dart';
import 'features/settings/push_init_service.dart';
import 'features/terms/terms_page.dart';
import 'theme/app_theme.dart';

/// Segmento ativo do negócio (persistido; null = beauty default).
final segmentPresetProvider = StateProvider<SegmentPreset?>((ref) => null);

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  bool segmentLoaded = false;

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

      // carrega o segmento do negócio uma vez por sessão (tema global)
      if (isAuthenticated && !segmentLoaded) {
        segmentLoaded = true;
        // fire-and-forget: tema default até chegar
        ApiClient().dio.get('/me').then((r) {
          final id = r.data['business_type'] as String?;
          debugPrint('[tema] GET /me → business_type=$id');
          if (id != null) {
            ref.read(segmentPresetProvider.notifier).state =
                SegmentPreset.byId(id);
          }
        }).catchError((_) {});
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
        path: '/time-offs',
        builder: (_, __) => const TimeOffsPage(),
      ),
      GoRoute(
        path: '/waitlist',
        builder: (_, __) => const WaitlistPage(),
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

  // Initialize Firebase (manual options p/ build de debug sem google-services.json;
  // em release, substituir pelas credenciais reais do projeto)
  //
  // CRÍTICO (18/09): no Android com google-services.json o plugin faz AUTO-INIT
  // do app [DEFAULT] no arranque do processo — chamar initializeApp(options:)
  // de novo lança [core/duplicate-app] e o app morre na splash. Fix: tentar
  // pegar o app default; só inicializa com options se ele ainda não existe
  // (iOS/build sem google-services).
  try {
    await Firebase.initializeApp();
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app' || e.code == 'no-options') {
      // auto-init já criou [DEFAULT] com as options do google-services — ok
      debugPrint('[firebase] app default já inicializado pelo plugin nativo');
    } else if (const bool.fromEnvironment('dart.product')) {
      rethrow;
    } else {
      // fallback: inicializa manual (debug sem google-services.json)
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY',
              defaultValue: 'AIzaSy...lrRg'),
          appId: String.fromEnvironment('FIREBASE_APP_ID',
              defaultValue: '1:581069825659:android:5b35631cb1d25900a0e4de'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID',
              defaultValue: '581069825659'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID',
              defaultValue: 'minha-agenda-6665a'),
        ),
      );
    }
  }

  // Ensure email/password auth is enabled (configured in Firebase Console)
  // FirebaseAuth.instance.setLanguageCode('pt-BR');

  // Push (FCM): handler de background + registro do token na API.
  // Best-effort — falha não impede o app de abrir.
  FirebaseMessaging.onBackgroundMessage(
      PushInitService.firebaseMessagingBackgroundHandler);
  PushInitService().init(
    onForegroundMessage: (title, body) {
      debugPrint('[push:fg] $title — $body');
    },
  );

  runApp(const ProviderScope(child: MinhaAgendaApp()));
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
