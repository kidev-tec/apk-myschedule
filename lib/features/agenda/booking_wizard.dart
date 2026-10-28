import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/sync_queue.dart';
import '../../core/utils/phone_br.dart';
import '../../theme/app_theme.dart';
import 'booking_logic.dart' as logic;

/// Provider do ApiClient — DI pra testes de integração sobrescreverem
/// a rede com http_mock_adapter. Em prod, resolve pro default (network real).
final wizardApiProvider = Provider<ApiClient>((ref) => ApiClient());

class BookingWizardPage extends ConsumerStatefulWidget {
  /// B3: agendamento a remarcar. Nulo = fluxo normal (POST).
  final Appointment? reschedule;

  /// Relógio (injetável em teste). Padrão: [DateTime.now].
  final DateTime Function() clock;
  const BookingWizardPage(
      {super.key, this.reschedule, this.clock = DateTime.now});

  @override
  ConsumerState<BookingWizardPage> createState() => _BookingWizardPageState();
}

class _BookingWizardPageState extends ConsumerState<BookingWizardPage> {
  late final PageController _pageController;
  int _step = 0;

  List<Client> _clients = [];
  List<Service> _services = [];
  List<WorkingHour> _workingHours = [];
  List<Appointment> _existingAppointments = [];
  late DateTime _selectedDate;

  /// Observações do prestador (só ele vê). Aparece após escolher o horário.
  final _notesCtrl = TextEditingController();

  Client? _selectedClient;
  Service? _selectedService;
  DateTime? _selectedSlot;

  bool _loading = true;

  // F4 — histórico do cliente selecionado
  Map<String, dynamic>? _clientHistory;
  bool _historyLoading = false;

  Future<void> _loadHistory(String clientId) async {
    setState(() => _historyLoading = true);
    try {
      final r = await ref
          .read(wizardApiProvider)
          .dio
          .get('/clients/$clientId/history');
      if (mounted) setState(() => _clientHistory = r.data);
    } catch (_) {
      if (mounted) setState(() => _clientHistory = null);
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  /// Painel resumido do histórico — "esse cliente veio 12x, sempre corta
  /// degradê". Aparece logo após selecionar o cliente no passo 1.
  Widget _buildHistoryPanel() {
    if (_selectedClient == null) return const SizedBox.shrink();
    if (_historyLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final h = _clientHistory;
    if (h == null) return const SizedBox.shrink();
    final total = h['total'] as int? ?? 0;
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Primeira visita deste cliente 👋',
            style: TextStyle(fontSize: 13)),
      );
    }
    final canceled = h['canceled'] as int? ?? 0;
    final lastVisit = h['last_visit'] as String?;
    final last = lastVisit != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(lastVisit))
        : '—';
    final recent = (h['recent'] as List? ?? [])
        .take(3)
        .map((a) => '${a['service_name']} — '
            '${DateFormat('dd/MM').format(DateTime.parse(a['starts_at']))}'
            '${a['status'] == 'canceled' ? ' (cancelado)' : ''}')
        .toList();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '$total visita${total > 1 ? 's' : ''} · última em $last'
                '${canceled > 0 ? ' · $canceled cancelamento(s)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...recent.map(
                  (s) => Text('• $s', style: const TextStyle(fontSize: 12))),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // B3: modo remarcar — abre direto no passo do horário, com a data
    // original e cliente/serviço pré-preenchidos após o carregamento.
    final r = widget.reschedule;
    if (r != null) {
      _step = 2;
      // Atrasado (dia anterior a hoje) abre em hoje: não se remarca pro passado.
      final original =
          DateTime(r.startsAt.year, r.startsAt.month, r.startsAt.day);
      _selectedDate = original.isBefore(_today) ? _today : original;
      _notesCtrl.text = r.notes ?? '';
    } else {
      _selectedDate = _today;
    }
    _pageController = PageController(initialPage: _step);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    final api = ref.read(wizardApiProvider);
    try {
      final results = await Future.wait([
        api.dio.get('/clients'),
        api.dio.get('/services'),
        api.dio.get('/working-hours'),
        api.dio.get('/appointments', queryParameters: {
          'from': DateTime.now()
              .subtract(const Duration(days: 30))
              .toUtc()
              .toIso8601String(),
          'to': DateTime.now()
              .add(const Duration(days: 90))
              .toUtc()
              .toIso8601String(),
        }),
      ]);
      List<dynamic> listOf(dynamic data, [String? key]) {
        if (data is List) return data;
        if (data is Map<String, dynamic>) return data[key] as List? ?? [];
        return [];
      }

      _clients = listOf(results[0].data)
          .map((j) => Client.fromJson(j as Map<String, dynamic>))
          .toList();
      _services = listOf(results[1].data)
          .map((j) => Service.fromJson(j as Map<String, dynamic>))
          .toList();
      _workingHours = listOf(results[2].data)
          .map((j) => WorkingHour.fromJson(j as Map<String, dynamic>))
          .toList();
      _existingAppointments = listOf(results[3].data, 'appointments')
          .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[wizard] falha ao carregar dados: $e');
    }
    // B3: modo remarcar — casa as FKs do agendamento com os registros
    // carregados (clients/services) pra pré-selecionar.
    final r = widget.reschedule;
    if (r != null) {
      _selectedClient = _clients.where((c) => c.id == r.clientId).firstOrNull;
      _selectedService =
          _services.where((s) => s.id == r.serviceId).firstOrNull;
      // pré-seleciona o horário atual, que continua válido (excludeId)
      _selectedSlot = _generateSlots(_selectedDate)
          .where((s) => _sameHM(s, r.startsAt))
          .firstOrNull;
    }
    if (mounted) setState(() => _loading = false);
  }

  DateTime get _today {
    final n = widget.clock();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _sameHM(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  List<DateTime> _generateSlots(DateTime date) {
    return logic.generateSlots(
      date: date,
      workingHours: _workingHours,
      appointments: _existingAppointments,
      durationMin: _selectedService?.durationMin ?? 60,
      excludeId: widget.reschedule?.id, // B3: não colidir consigo mesmo
      notBefore: widget.clock(), // horário que já passou não é oferecido
    );
  }

  void _nextStep() {
    if (_step < 2) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _createAppointment();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Future<Appointment?> _createAppointment() async {
    if (_selectedClient == null ||
        _selectedService == null ||
        _selectedSlot == null) {
      return null;
    }

    setState(() => _loading = true);
    final isReschedule = widget.reschedule != null;
    // B3: modo remarcar → PATCH no existente (API valida overlap ignorando
    // o próprio id); modo normal → POST. Mesmo body de startsAt/endsAt.
    final op = PendingOp(
      id: 'appt-${_selectedSlot!.millisecondsSinceEpoch}',
      method: isReschedule ? 'PATCH' : 'POST',
      path: isReschedule
          ? '/appointments/${widget.reschedule!.id}'
          : '/appointments',
      body: isReschedule
          ? {
              // remarcar: envia sempre (vazio apaga)
              'notes': _notesCtrl.text.trim(),
              'startsAt': _selectedSlot!.toUtc().toIso8601String(),
              'endsAt': _selectedSlot!
                  .add(Duration(minutes: _selectedService!.durationMin))
                  .toUtc()
                  .toIso8601String(),
            }
          : {
              'clientId': _selectedClient!.id,
              'serviceId': _selectedService!.id,
              if (_notesCtrl.text.trim().isNotEmpty)
                'notes': _notesCtrl.text.trim(),
              'startsAt': _selectedSlot!.toUtc().toIso8601String(),
              'endsAt': _selectedSlot!
                  .add(Duration(minutes: _selectedService!.durationMin))
                  .toUtc()
                  .toIso8601String(),
            },
      queuedAt: DateTime.now(),
      description: isReschedule
          ? 'Remarcar ${_selectedClient!.name} às ${DateFormat('HH:mm').format(_selectedSlot!)}'
          : 'Agendamento de ${_selectedClient!.name} às ${DateFormat('HH:mm').format(_selectedSlot!)}',
    );
    try {
      final api = ref.read(wizardApiProvider);
      if (isReschedule) {
        final res = await api.dio.patch(op.path, data: op.body);
        if (mounted) {
          // B-remarque: API devolve a NOVA linha (cancela a antiga e cria
          // outra com id novo) — devolve pro chamador montar a mensagem
          // do WhatsApp com o horário real (sem GET fantasma /:id).
          final novo = _appointmentFrom(res.data);
          context.pop(novo);
          return novo;
        }
      } else {
        final res = await api.dio.post('/appointments', data: op.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Horário marcado!'),
                backgroundColor: Colors.green),
          );
          // Devolve o criado pra agenda recarregar e focar no dia dele.
          if (context.canPop()) {
            context.pop(_appointmentFrom(res.data));
          } else {
            context.go('/agenda');
          }
        }
      }
    } on DioException catch (e) {
      // Offline-first fase 2: falha de CONEXÃO enfileira; erro de negócio
      // (409 conflito, 400 validação) mostra a mensagem humana na hora.
      if (!mounted) {
        return null;
      }
      final queued =
          await ref.read(syncQueueProvider.notifier).enqueueIfOffline(e, op);
      if (mounted) {
        if (queued) {
          context.go('/agenda');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Sem internet — horário salvo no celular e vai sincronizar sozinho'),
                backgroundColor: Colors.orange),
          );
        } else {
          final msg = e.response?.data is Map<String, dynamic>
              ? (e.response!.data as Map<String, dynamic>)['error'] as String?
              : null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(msg ?? 'Falha: ${e.message}'),
                backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Falha: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
    return null; // falha/offline: sem appointment novo
  }

  /// Lê `{appointment: {...}}` da resposta da API; null se vier inválida
  /// (a agenda recarrega a lista de qualquer forma).
  Appointment? _appointmentFrom(dynamic data) {
    final j = data is Map<String, dynamic> ? data['appointment'] : null;
    if (j is! Map<String, dynamic>) return null;
    try {
      return Appointment.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reschedule != null
            ? 'Remarcar'
            : [
                'Escolhe o cliente',
                'Escolhe o serviço',
                'Escolhe o horário'
              ][_step]),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _prevStep)
            : null,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _step = i),
        children: [
          _buildClientStep(),
          _buildServiceStep(),
          _buildSlotStep(),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('wizard-save'),
                  onPressed: _canProceed() ? _nextStep : null,
                  child: Text(_step == 2
                      ? (widget.reschedule != null
                          ? 'Salvar novo horário'
                          : 'Confirmar agendamento')
                      : 'Continuar'),
                ),
              ),
            ),
    );
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _selectedClient != null;
      case 1:
        return _selectedService != null;
      case 2:
        return _selectedSlot != null;
      default:
        return false;
    }
  }

  String _query = '';

  Future<void> _openAddClientSheet() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: _query.trim());
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? duplicateError;
    Client? duplicate;

    final created = await showModalBottomSheet<Client>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (!formKey.currentState!.validate()) return;
              setSheetState(() {
                saving = true;
                duplicateError = null;
              });
              try {
                final api = ref.read(wizardApiProvider);
                final resp = await api.dio.post('/clients', data: {
                  'name': nameCtrl.text.trim(),
                  'phone_e164': normalizePhoneBr(phoneCtrl.text),
                  if (emailCtrl.text.trim().isNotEmpty)
                    'email': emailCtrl.text.trim(),
                });
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, Client.fromJson(resp.data));
                }
              } on DioException catch (e) {
                final status = e.response?.statusCode;
                final data = e.response?.data;
                if (status == 409 && data is Map<String, dynamic>) {
                  setSheetState(() {
                    saving = false;
                    duplicateError =
                        data['error'] as String? ?? 'Cliente já existe';
                    final ex = data['existing'];
                    if (ex is Map<String, dynamic>) {
                      duplicate = Client.fromJson(ex);
                    }
                  });
                } else {
                  final msg =
                      data is Map<String, dynamic> ? data['error'] : null;
                  setSheetState(() => saving = false);
                  if (sheetContext.mounted) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                      content:
                          Text(msg is String ? msg : 'Falha ao criar cliente'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              } catch (e) {
                setSheetState(() => saving = false);
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(
                    content: Text('Falha ao criar cliente: $e'),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            }

            return Padding(
              // viewInsets (teclado) + padding.bottom (barra de gestos) —
              // sem os dois o botão some atrás da barra no A15.
              padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(sheetContext).viewInsets.bottom +
                      MediaQuery.of(sheetContext).padding.bottom +
                      24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Adicionar cliente',
                        style: Theme.of(sheetContext).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Nome é obrigatório'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp *',
                        hintText: '(14) 99999-9999',
                        helperText: 'Com DDD — o 55 do Brasil entra sozinho',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) => normalizePhoneBr(v ?? '').isEmpty
                          ? 'Telefone inválido (informe DDD)'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail (opcional)',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    if (duplicateError != null) ...[
                      const SizedBox(height: 12),
                      Text(duplicateError!,
                          style: const TextStyle(color: AppColors.error)),
                      if (duplicate != null)
                        TextButton.icon(
                          icon: const Icon(Icons.person_search),
                          label: Text('Usar ${duplicate!.name}'),
                          onPressed: () =>
                              Navigator.pop(sheetContext, duplicate),
                        ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving ? null : save,
                        child: saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Criar e usar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (created != null && mounted) {
      setState(() {
        _clients = [..._clients, created];
        _selectedClient = created;
        // limpa a busca: a lista volta completa com o selecionado visível
        _query = '';
      });
    }
  }

  Widget _buildClientStep() {
    final filtered = _clients
        .where((c) =>
            _query.trim().isEmpty ||
            c.name.toLowerCase().contains(_query.trim().toLowerCase()) ||
            c.phoneE164.contains(_query.trim()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar cliente',
              hintText: 'Nome ou telefone',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        // F4: histórico do cliente selecionado
        _buildHistoryPanel(),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_off,
                      size: 64, color: AppColors.neutral),
                  const SizedBox(height: 16),
                  Text(
                      _query.trim().isEmpty
                          ? 'Nenhum cliente ainda'
                          : 'Nenhum cliente encontrado',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Adicionar cliente'),
                    onPressed: _openAddClientSheet,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Adicionar cliente'),
                      onPressed: _openAddClientSheet,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final selected = _selectedClient?.id == c.id;
                      return Card(
                        color: selected ? AppColors.softOf(context) : null,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryOf(context),
                            child: Text(c.name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(c.name),
                          subtitle: Text(c.phoneE164),
                          trailing: selected
                              ? Icon(Icons.check_circle,
                                  color: AppColors.primaryOf(context))
                              : null,
                          onTap: () {
                            setState(() => _selectedClient = c);
                            _loadHistory(c.id);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildServiceStep() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _services.length,
      itemBuilder: (_, i) {
        final s = _services[i];
        final selected = _selectedService?.id == s.id;
        final priceFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
        return Card(
          color: selected ? AppColors.softOf(context) : null,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryOf(context),
              child: const Icon(Icons.content_cut, color: Colors.white),
            ),
            title: Text(s.name),
            subtitle: Text(
                '${s.durationMin} min • ${priceFmt.format(s.priceCents / 100)}'),
            trailing: selected
                ? Icon(Icons.check_circle, color: AppColors.primaryOf(context))
                : null,
            onTap: () => setState(() => _selectedService = s),
          ),
        );
      },
    );
  }

  Widget _buildSlotStep() {
    final slots = _generateSlots(_selectedDate);
    final dateFmt = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR');
    final timeFmt = DateFormat('HH:mm', 'pt_BR');

    return Column(
      children: [
        // Date picker
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.softOf(context).withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  // não navega pra dias passados
                  onPressed: _selectedDate.isAfter(_today)
                      ? () => setState(() => _selectedDate =
                          _selectedDate.subtract(const Duration(days: 1)))
                      : null),
              Text(dateFmt.format(_selectedDate).capitalize(),
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _selectedDate =
                      _selectedDate.add(const Duration(days: 1)))),
            ],
          ),
        ),
        if (slots.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.block, size: 64, color: AppColors.neutral),
                  const SizedBox(height: 16),
                  Text('Sem horários livres neste dia',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Tenta outro dia ou ajusta teus horários de trabalho',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.neutral)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: slots.length,
              itemBuilder: (_, i) {
                final slot = slots[i];
                final selected = _selectedSlot == slot;
                return InkWell(
                  onTap: () => setState(() => _selectedSlot = slot),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryOf(context)
                          : AppColors.softOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected
                              ? AppColors.primaryOf(context)
                              : Colors.transparent,
                          width: 2),
                    ),
                    child: Center(
                      child: Text(
                        timeFmt.format(slot),
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.primaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        // Observações: só depois de escolher o horário; privadas do prestador.
        if (_selectedSlot != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('wizard-notes'),
              controller: _notesCtrl,
              minLines: 1,
              maxLines: 3,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Detalhes / Observações',
                helperText: 'Só você vê — o cliente não recebe.',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
          ),
      ],
    );
  }
}

class Client {
  final String id;
  final String name;
  final String phoneE164;
  final String? email;

  Client(
      {required this.id,
      required this.name,
      required this.phoneE164,
      this.email});

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: j['id'],
        name: j['name'],
        phoneE164: j['phone_e164'] ?? j['phoneE164'] ?? '',
        email: j['email'],
      );
}

class Service {
  final String id;
  final String name;
  final int durationMin;
  final int priceCents;

  Service(
      {required this.id,
      required this.name,
      required this.durationMin,
      required this.priceCents});

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'],
        name: j['name'],
        durationMin: j['duration_min'] ?? j['durationMin'],
        priceCents: j['price_cents'] ?? j['priceCents'],
      );
}

class WorkingHour {
  final int weekday;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  WorkingHour(
      {required this.weekday, required this.startTime, required this.endTime});

  factory WorkingHour.fromJson(Map<String, dynamic> j) => WorkingHour(
        weekday: j['weekday'],
        startTime: TimeOfDay(
            hour: int.parse(j['start_time']?.split(':')[0] ?? '0'),
            minute: int.parse(j['start_time']?.split(':')[1] ?? '0')),
        endTime: TimeOfDay(
            hour: int.parse(j['end_time']?.split(':')[0] ?? '0'),
            minute: int.parse(j['end_time']?.split(':')[1] ?? '0')),
      );
}

class Appointment {
  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  // B3: FKs pro modo remarcar (pré-selecionar cliente/serviço no wizard)
  final String? clientId;
  final String? serviceId;

  /// Observações do prestador (privadas).
  final String? notes;

  Appointment(
      {required this.id,
      required this.startsAt,
      required this.endsAt,
      required this.status,
      this.clientId,
      this.serviceId,
      this.notes});

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'],
        startsAt: DateTime.parse(j['starts_at'] ?? j['startsAt']).toLocal(),
        endsAt: DateTime.parse(j['ends_at'] ?? j['endsAt']).toLocal(),
        status: j['status'] ?? 'pending',
        clientId: j['client_id'] ?? j['clientId'],
        serviceId: j['service_id'] ?? j['serviceId'],
        notes: j['notes'] as String?,
      );
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
