# TASK-F1-11 — Pagamento no agendamento (app)

- **Status:** Done
- **O QUE É:** mostrar valor/recebido/saldo/situação no agendamento e permitir receber (sinal, parcial, quitação) e estornar.
- **EXECUTION MODE:** Interactive (checkpoint visual com o Ezequias no emulador)
- **RF-IDs:** RF-F01, RF-F02, RF-F03
- **SPEC:** `api/.planning/financas/SPEC.md` (aprovada 2026-11-27). Depende de api TASK-F1-02 e F1-03.

## PRE-CONDITIONS (verificadas em 2026-11-27)
- Modelo `Appointment` em `lib/features/agenda/agenda_page.dart` (~l.1611), já lê `service_price_cents`.
- Detalhe do agendamento: `_AppointmentDetailsSheet` (~l.1954); ações no menu do card (~l.826).
- Escrita offline passa por `lib/core/storage/sync_queue.dart`.

## O QUE CRIAR
- `lib/features/finance/`:
  - `money.dart` — formatar centavos em R$ e converter texto mascarado ↔ centavos (sem `double`).
  - `payment_models.dart` — `PaymentMethod` (pix, cash, debit, credit, payment_link, other → rótulos PT-BR), `AppointmentPayments`, `Payment`.
  - `finance_api.dart` — `getAppointmentPayments`, `createPayment`, `voidPayment`, `updatePrice` (Dio do `api_client.dart`).
  - `receive_payment_sheet.dart` — valor (padrão = saldo), forma (chips), parcelas 1–12 só para crédito, data, observação; valida valor ≤ saldo antes de enviar.
  - `payment_status_chip.dart` — Em aberto / Parcial / Pago (some quando `none`).
- `Appointment` passa a ler `price_cents`, `paid_cents`, `balance_cents`, `payment_status` (fallback para `service_price_cents` se a API antiga não mandar).
- `_AppointmentDetailsSheet`: bloco **Pagamento** (valor, recebido, saldo, lista de recebimentos com estorno por confirmação), botões **Receber** e **Editar valor**.
- Card da agenda: `payment_status_chip` discreto.
- Recebimentos são **somente online** no F1 (não enfileirar): sem conexão o painel mostra o `humanError` padrão ("Sem conexão com o servidor. Verifique a internet.").
- Ponto de entrada: bloco "Pagamento" no painel de detalhes (ícone de observações do card); o painel recarrega a agenda ao fechar se houve mudança.

## TESTES DERIVADOS
- `money_test.dart`: "R$ 1.234,56" ↔ 123456; "0,05" ↔ 5; vazio → null.
- `receive_payment_sheet_test.dart`: parcelas só aparecem para crédito; valor > saldo desabilita Salvar; envia centavos e método corretos (http_mock_adapter).
- `payment_status_chip_test.dart`: cada situação com rótulo; `none` não renderiza.
- Detalhe: estorno pede confirmação e recarrega a situação; erro 422 da API vira snackbar com a mensagem do body.
- `Appointment.fromJson` com e sem os campos novos.

## CRITÉRIO DE ACEITE
1. Recebo sinal e depois o saldo; chip muda de Em aberto → Parcial → Pago.
2. Crédito pede parcelas; outras formas não.
3. Estorno volta a situação anterior.
4. `flutter analyze --fatal-infos --fatal-warnings` e `dart format` limpos; cobertura ≥ gate.
5. Validado visualmente pelo Ezequias no emulador.

## ARMADILHAS
- Após `await` em `ConsumerState`, checar `mounted`; ler estado por `ref.read(provider)`.
- Não mexer no `dependency_overrides` do `firebase_core_platform_interface`.
