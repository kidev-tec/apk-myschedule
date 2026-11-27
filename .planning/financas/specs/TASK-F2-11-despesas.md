# TASK-F2-11 — Despesas (app)

- **Status:** Done
- **O QUE É:** tela de despesas: lançar (paga ou a pagar), listar com totais, pagar e estornar.
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias)
- **RF-IDs:** RF-F06 · Depende de api TASK-F2-02.

## O QUE CRIAR (`lib/features/finance/`)
- Rota `/finance/expenses` → `expenses_page.dart`; card "Despesas" na `FinanceHomePage`.
- Topo: Pagas, A pagar, Vencidas (vermelho). Filtro: mês (setas ‹ ›) e status (Todas / Pagas / A pagar).
- Lista: categoria (ícone), descrição, data/vencimento, valor; a pagar com botão **Pagar**; estornar com confirmação.
- `expense_sheet.dart`: valor (campo maquininha), categoria (chips), "Já paguei" (padrão ligado) → forma + data; desligado → vencimento. "Outros" exige descrição.
- Categorias com rótulos PT-BR: Materiais, Aluguel, Taxas, Energia e água, Marketing, Outros.

## TESTES DERIVADOS
- Sheet: "Outros" sem descrição desabilita; desligar "Já paguei" troca forma por vencimento; envia centavos/categoria/paid corretos.
- Página: totais e lista vindos da API; Pagar abre forma de pagamento e recarrega; estorno pede confirmação.

## CRITÉRIO DE ACEITE
1. Lanço despesa paga e a pagar. 2. Pago uma a pagar. 3. Analyze/format limpos. 4. Validado no emulador.
