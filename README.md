# Minha Agenda — App

App Flutter do **Minha Agenda**: agenda profissional para profissionais da beleza — login, onboarding guiado, agenda do dia, clientes, serviços e link público de agendamento.

Repositório irmão (backend): [minha-agenda-api](https://github.com/rdz2211/minha-agenda-api)

## Stack

- **Flutter** (Dart SDK >= 3.4) — Material 3, tema próprio (fonte Marcellus)
- **Estado:** Riverpod 2 (code-gen com `riverpod_annotation` + `riverpod_generator`)
- **Navegação:** GoRouter 14
- **HTTP:** Dio (+ `http_mock_adapter` nos testes)
- **Auth:** Firebase Auth (email/senha e Google Sign-In)
- **Localização:** pt_BR via `flutter_localizations` + intl
- **Qualidade:** `flutter_lints`, testes widget/unitários com coverage

## Rodando

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1   # emulador → API local
```

### Configuração da API

A URL da API é injetada em tempo de build via `--dart-define` (ver `lib/core/api/api_config.dart`):

```bash
# emulador Android (10.0.2.2 = localhost do host)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/v1

# celular real na rede Wi-Fi (IP da máquina)
flutter run --dart-define=API_BASE_URL=http://192.168.1.X:3000/v1

# produção
flutter build apk --release --dart-define=API_BASE_URL=https://api-agenva.kidev.tec.br/v1
```

Padrão (sem dart-define): `http://10.0.2.2:3000/v1`.

As credenciais Firebase (API key / project id) também entram via `--dart-define` no `main.dart`; o `google-services.json` fica em `android/app/` (fora do git).

## Testes

```bash
flutter test                 # todos os testes
flutter test --coverage      # gera coverage/
```

## Estrutura

```
lib/
├── main.dart            # bootstrap (Firebase + ProviderScope)
├── core/
│   ├── api/             # ApiConfig (dart-define) + ApiClient (Dio)
│   └── update/          # verificação de atualização (/v1/version)
├── theme/               # tema visual (Marcellus, cores da marca)
└── features/
    ├── auth/            # login email/senha + Google, /auth/sync
    ├── onboarding/      # 3 passos: negócio → serviços → horários
    ├── agenda/          # agenda do dia/semana
    ├── clients/         # clientes
    ├── services/        # serviços oferecidos
    ├── settings/        # configurações, termos, atualização
    └── terms/           # termos de uso / EULA
```

## Fluxo principal

Login (Firebase) → `/auth/sync` na API (cria user + business com trial de 30 dias no 1º acesso) → onboarding de 3 passos → agenda do dia.

## Licença

Ver [LICENSE](LICENSE).
