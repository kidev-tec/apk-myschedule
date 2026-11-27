# TASK-F1-12 — Área Finanças + "A receber" (app)

- **Status:** Done
- **O QUE É:** nova entrada "Finanças" no menu com a tela "A receber" (primeira tela do módulo; o resumo do mês chega na F3).
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias)
- **RF-IDs:** RF-F04
- **SPEC:** `api/.planning/financas/SPEC.md`. Depende de api TASK-F1-03 e apk TASK-F1-11.

## PRE-CONDITIONS
- Rotas em `lib/main.dart` (GoRouter, rotas de topo como `/clients`, `/services`).
- O "menu" do app é a tela Configurações (cards → `context.push`). Entradas: card "Finanças" em Configurações + atalho (carteira) no AppBar da agenda.

## O QUE CRIAR
- Rota `/finance` → `finance_home_page.dart` (por ora: cards "A receber" e "Receber avulso").
- Rota `/finance/receivables` → `receivables_page.dart`:
  - topo: total em aberto, atrasado (realizados/passados) e a receber (futuros);
  - filtro de período (chips: Até 60 dias [padrão], Atrasados, Próximos 7 dias, Este mês) e cliente;
  - lista agrupada em "Atrasados" e "Próximos": data, cliente, serviço, saldo, chip;
  - toque abre o `receive_payment_sheet` com o saldo; ao salvar, item sai da lista se ficar pago.
- "Receber avulso": mesmo sheet sem agendamento, cliente opcional (D7).
- Estado vazio: "Nada a receber no período."

## TESTES DERIVADOS
- Lista agrupa atrasados e próximos e mostra os totais vindos da API.
- Filtro de cliente envia `client_id`.
- Receber o saldo inteiro remove o item; parcial atualiza o saldo.
- Estado vazio renderiza a mensagem.
- Rota `/finance` acessível pelo menu.

## CRITÉRIO DE ACEITE
1. "Finanças" aparece no menu e abre a área.
2. "A receber" mostra totais e itens corretos (conferidos contra a API).
3. Receber pela lista atualiza a lista e a agenda.
4. Analyze/format limpos; cobertura ≥ gate.
5. Validado visualmente pelo Ezequias.

## ARMADILHAS
- Datas exibidas no fuso do business (não do aparelho) quando diferentes.
