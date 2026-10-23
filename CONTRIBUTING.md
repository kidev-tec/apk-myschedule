# Contribuindo

## Regra de ouro
PR revisado por Ezequias antes de qualquer merge. Sem exceção.

## Fluxo (feat → staging → main)
1. Branch a partir de `staging`: `feat/<escopo>-<resumo>` ou `fix/<resumo>`
2. TDD obrigatório — coverage mínima **100%** na API (statements/branches/functions/lines) e **30% de linhas** no app
3. `npm test && npm run lint` (API) ou `flutter test && flutter analyze` (app) verdes antes do PR
4. PR → `staging`, review do Ezequias, merge
5. `staging` → `main` só com release validado

## Commits
Conventional Commits, assinados (SSH/GPG). Nada de commit direto em `main`/`staging`.

## Coverage
Threshold bloqueante, não aspiracional: 100% na API e 30% de linhas no app
(gate do job Test no CI, igual para PRs em `staging` e `main`). Exceção de exclusão de arquivo
só em migrations geradas e código de bootstrap de plataforma.
