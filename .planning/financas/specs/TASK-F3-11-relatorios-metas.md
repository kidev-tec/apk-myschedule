# TASK-F3-11 — Resumo, relatórios e meta (app)

- **Status:** Done
- **O QUE É:** resumo do mês na tela Finanças, tela de relatórios por período e meta mensal.
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias)
- **RF-IDs:** RF-F07 a RF-F10 · Depende de api TASK-F3-01 e F3-02.

## O QUE CRIAR (`lib/features/finance/`)
- **Finanças (topo):** card do mês — Recebido, Despesas, Resultado e a **meta** (barra de progresso com %; sem meta: "Definir meta"). Toque abre Relatórios.
- **Relatórios** (`/finance/reports`):
  - seletor Dia / Semana / Mês / Período (datas), com ‹ › para andar; semana de segunda a domingo;
  - cards Recebido, Despesas, Resultado (verde/vermelho), Em aberto;
  - gráfico de barras simples por dia (recebido × despesas) **desenhado com widgets do Flutter** — sem biblioteca nova (dependência nova é decisão bloqueada);
  - Recebido por forma de pagamento;
  - Ticket médio (por atendimento e por cliente) e quantidade de atendimentos concluídos;
  - Por serviço: nome, quantidade e total, ordenado pelo total.
- **Meta:** diálogo para definir/alterar/remover a meta do mês (valor maquininha); mostra quanto falta e quanto precisa por dia.

## TESTES DERIVADOS
- Cálculo dos períodos (dia, semana seg–dom, mês, navegação ‹ ›) — teste de unidade puro.
- Relatórios mostram os valores da API; trocar período envia `from`/`to` certos.
- Meta: definir envia `target_cents`; remover chama DELETE; barra mostra o %.

## CRITÉRIO DE ACEITE
1. Vejo o mês na tela Finanças com a meta. 2. Navego por dia/semana/mês/período. 3. Analyze/format limpos. 4. Validado no emulador.
