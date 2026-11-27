# TASK-F4-11 — Fluxo projetado e comprovante (app)

- **Status:** Done
- **O QUE É:** tela de fluxo de caixa projetado e comprovante de recebimento compartilhável.
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias)
- **RF-IDs:** RF-F11, RF-F12 · Depende de api TASK-F4-01 e F4-02.

## SEM DEPENDÊNCIA NOVA
- Imagem do comprovante: widget renderizado com `RepaintBoundary.toImage` → PNG.
- Arquivo temporário: `path_provider` (já no projeto). Compartilhar: `share_plus` (já no projeto) — WhatsApp, e-mail etc. pelo menu do sistema.

## O QUE CRIAR (`lib/features/finance/`)
- **Fluxo projetado** (`/finance/cashflow`, card em Finanças):
  - chips 7 / 15 / 30 / 60 dias (padrão 30);
  - totais: A entrar, A sair, Saldo do período; aviso "não inclui o dinheiro que você já tem";
  - bloco **Atrasados** (a receber e a pagar vencidos) com atalhos para "A receber" e "Despesas";
  - lista dos dias com movimento: data, entradas/saídas (cliente+serviço / despesa) e saldo acumulado (vermelho se negativo).
- **Comprovante** (`receipt_sheet.dart`):
  - botão **Comprovante** em cada recebimento não estornado do bloco Pagamento e da lista do caixa;
  - prévia do comprovante (logo/nome do negócio, nº, data, cliente, serviço, valor, forma, sinal/saldo);
  - **Compartilhar** (imagem PNG via `share_plus`) e **Copiar texto**.

## TESTES DERIVADOS
- Fluxo: totais e dias vindos da API; trocar a janela envia `days`; saldo negativo em vermelho; atrasados aparecem só quando > 0.
- Comprovante: mostra os campos da API (com e sem cliente/atendimento); texto copiado traz número, valor e forma; compartilhar chama o serviço de compartilhamento (injetável no teste).

## CRITÉRIO DE ACEITE
1. Vejo a projeção de 30 dias e os atrasados. 2. Gero e compartilho o comprovante de um recebimento. 3. Analyze/format limpos. 4. Validado no emulador.
