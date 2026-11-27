# TASK-F2-12 — Caixa do dia (app)

- **Status:** Done
- **O QUE É:** abrir, movimentar e fechar o caixa com conferência.
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias)
- **RF-IDs:** RF-F05 · Depende de api TASK-F2-03.

## O QUE CRIAR (`lib/features/finance/`)
- Rota `/finance/cash` → `cash_page.dart`; card "Caixa do dia" na `FinanceHomePage` (mostra "Aberto desde HH:mm" ou "Fechado").
- **Fechado:** botão **Abrir caixa** → saldo inicial (troco). Abaixo, histórico dos últimos caixas (data, esperado, contado, sobra/falta).
- **Aberto:** resumo — saldo inicial, entradas em dinheiro, saídas em dinheiro, **esperado em dinheiro**; recebido por outras formas (informativo); lista de movimentos; botões **Suprimento**, **Sangria** e **Fechar caixa**.
- **Fechar:** campo "Quanto tem no caixa?" → mostra a diferença ao vivo ("Sobra R$ X" verde / "Falta R$ X" vermelho / "Confere"); confirmar fecha.

## TESTES DERIVADOS
- Estado fechado mostra Abrir e histórico; abrir envia `opening_cents`.
- Aberto mostra esperado; sangria acima do esperado mostra o erro da API.
- Fechar: diferença ao vivo para sobra/falta/confere; envia `counted_cents`.

## CRITÉRIO DE ACEITE
1. Abro, recebo em dinheiro, faço sangria, fecho e vejo a diferença. 2. Analyze/format limpos. 3. Validado no emulador.
