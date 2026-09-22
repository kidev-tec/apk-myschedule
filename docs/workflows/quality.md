# Qualidade — App Flutter

## Gates

1. `flutter analyze` — 0 issues (--fatal-infos no CI)
2. `flutter test` — suíte verde
3. Coverage: crescer por feature nova (serviços novos com teste próprio)

## Padrões

- Mocks de rede com http_mock_adapter (DioAdapter) injetado no ApiClient
- setMockInitialValues({}) + initializeDateFormatting(pt_BR) no setUpAll de widget tests
- Testes widget data-dependent: navegação de data DINÂMICA (nunca N cliques fixos)
- Serviço novo = arquivo de serviço + arquivo de teste 1:1
- Regression-first: bug corrigido tem teste primeiro

## Anti vibe-code

- Sem `test('funciona')` — descrição = comportamento + critério
- flutter analyze zerado é pré-condição de commit, não aspiração
- git diff HEAD~1 pós-commit: diff = intuito
