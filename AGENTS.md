# AGENTS.md — apk-myschedule (AGENVA App)

> Doc agêntico: lido por Hermes, Claude Code, Codex, Cursor. Sanitizado — sem segredos.
> Última atualização: 2026-09-16

## O que é

App Flutter do AGENVA (ex Minha Agenda): cliente Android do SaaS de agenda.
**Flutter + Riverpod (StateNotifier) + GoRouter + Dio**. Auth Firebase
(email/senha + Google). Compila APK debug/release via Gradle.

## Comandos

```bash
flutter pub get                    # deps
flutter analyze                    # DEVE zerar (--fatal-infos no CI)
flutter test                       # suíte (74+ testes)
flutter test --coverage            # lcov
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://<ip-da-api>:3200/v1   # APK debug
```

## Regras inegociáveis

- **Fluxo Git:** feat/* → PR base staging → merge main. Nunca push direto.
- **TDD:** código sem teste correspondente não é feature.
- **flutter analyze 100% limpo** (CI roda com --fatal-infos): infos pre-existing
  nos arquivos tocados devem ser zeradas antes do commit.
- **Pós-await em ConsumerState:** verificar mounted (do State) ANTES de usar context/ref.
- **Ler estado via ref.read(provider)** — NUNCA notifier.state (protected member, Riverpod).
- **const em Icons** dentro de builders; if de 1 linha usa chaves (curly_braces).
- **Mensagens de erro humanas em PT-BR** — extrair response.data[error] do DioException.
- Evidência real para fechar diagnóstico (nunca "deve ser").

## Arquitetura (mapa)

lib/
├── main.dart                  # bootstrap: Firebase.initializeApp (options via
│                              #   --dart-define), push FCM init, routerProvider
├── core/
│   ├── api/
│   │   ├── api_config.dart    # baseUrl via --dart-define API_BASE_URL
│   │   └── api_client.dart    # Dio + interceptors (Bearer do secure_storage,
│   │                          #   refresh em 401, paywall flag em 402)
│   ├── auth/auth_controller.dart  # StateNotifier de sessão
│   ├── segment/segment_preset.dart # 9 presets (cor+ícone+serviços) por segmento
│   ├── storage/onboarding_store.dart
│   └── update/update_service.dart  # checa /v1/version (updater)
├── features/
│   ├── auth/login_page.dart           # email/senha + Google
│   ├── onboarding/onboarding_page.dart # 3 passos (conta → serviços → horários)
│   ├── agenda/agenda_page.dart        # agenda do dia + booking wizard
│   ├── agenda/booking_wizard.dart     # wizard cliente → serviço → slot
│   ├── clients/                       # CRUD clientes (+ WhatsApp no cancelamento)
│   ├── services/                      # CRUD serviços
│   ├── settings/
│   │   ├── settings_page.dart         # cards: assinatura, segmento, logo, gcal, link
│   │   ├── logo_service.dart          # valida 2MB/PNG-JPG ANTES da rede; multipart
│   │   ├── device_token_service.dart  # POST /devices (nunca crasha)
│   │   ├── push_init_service.dart     # FCM: permissão, onMessage, onTokenRefresh
│   │   └── gcal_service.dart          # conectar/desconectar Google Calendar
│   └── terms/terms_page.dart          # termos + privacidade (LGPD)
└── theme/app_theme.dart               # buildAppTheme(preset) — cor por segmento

## Decisões de arquitetura vigentes

- **Portrait-only** (usuário leigo): AndroidManifest screenOrientation="portrait"
  + iOS Info.plist só Portrait (iPad mantém 4).
- **dependency_overrides CRÍTICO**: firebase_core_platform_interface 6.0.3
  corrige crash de splash (bug pigeon sem prefixo). NUNCA remover — se sumir,
  o app trava na splash com PlatformException(channel-error) no logcat.
- **Segmento é skin**: preset (cor/ícone/serviços) por tipo de negócio; API é agnóstica.
- **Push best-effort**: falha de registro/notificação nunca impede o app de abrir.
- **API base**: --dart-define=API_BASE_URL (compile-time). Debug default aponta
  para a API local na rede.

## Pitfalls (do histórico do projeto)

- **firebase_core_platform_interface 5.x tem bug de pigeon** (canais sem prefixo)
  → crash no Firebase.initializeApp = splash eterna. Fix é o override 6.0.3.
  Diagnosticar comparando strings pigeon nos kernel_blob de APKs novo vs antigo.
- **DateFormat(pt_BR)** exige await initializeDateFormatting(pt_BR, null)
  (main.dart faz; testes precisam repetir no setUpAll).
- **flutter_secure_storage** em teste: FlutterSecureStorage.setMockInitialValues({}).
- **NTFS não preserva +x** (gradlew, .husky) — build por clone ext4 ou
  GRADLE_USER_HOME local; commits com --no-verify se husky quebrado.
- **Gradle wrapper 9.3.1**: se ~/.gradle for symlink quebrado (volume NTFS
  desmontado), exportar GRADLE_USER_HOME pra um dir ext4 local.
- **Testes widget data-dependent**: navegação de data no booking wizard deve ser
  dinâmica (próxima segunda), nunca 3 cliques fixos — o calendário anda.
- **firebase_messaging**: manter versão compatível com firebase_core 3.x (^15.2.x);
  conflito de versão quebra o pub get inteiro.
- build_runner/riverpod_generator: regenerar (dart run build_runner build
  --delete-conflicting-outputs) antes do analyze se mudar providers gerados.

## Testing

- Framework: flutter test; mocks de rede com http_mock_adapter (DioAdapter)
  injetado no ApiClient(adapter: ...).
- Serviços novos têm teste próprio (logo_service_test, device_token_service_test).
- Widget tests precisam de: setMockInitialValues({}) + initializeDateFormatting
  + GoRouter mínimo no wrap.

## Envs / dart-define

| Var | Uso |
|---|---|
| API_BASE_URL | base da API (ex: http://192.168.1.192:3200/v1) |
| FIREBASE_API_KEY / APP_ID / SENDER_ID / PROJECT_ID | defaults do projeto no main.dart |

## Out of scope

- Migrar para Material 3 expressive / trocar Riverpod por Bloc
- Renomear applicationId (com.minhaagenda.minha_agenda_app) — quebra updates
  instalados; renomeação de marca é só label/assets
- iOS build local (CI roda; sem assinatura local)

## Decisões bloqueadas (o agente PARA e pergunta)

- Nova dependência de produção (pubspec)
- Renomear package/applicationId ou mudar assinatura
- Mudar navegação raiz (GoRouter) ou contrato com a API
- Baixar padrão do analyze (--fatal-infos) ou cobertura
- Assumir requisito de produto que não está na SPEC
