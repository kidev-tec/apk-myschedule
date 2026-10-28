import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/local_cache.dart';
import '../../core/storage/connectivity_provider.dart';
import '../../core/storage/sync_queue.dart';
import '../../core/utils/phone_br.dart';
import '../../core/api/paywall_flag.dart';
import '../../core/update/update_service.dart';
import '../../theme/app_theme.dart';
import 'booking_wizard.dart' as booking show Appointment;
import 'booking_logic.dart' as booking_logic show buildRescheduleMessage;

/// B6/DI: provider do ApiClient pra agenda — testes sobrescrevem com mock.
final agendaApiProvider = Provider<ApiClient>((ref) => ApiClient());

class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key, this.onCheckUpdate});

  /// Checagem de update pós-frame (injetável; testes passam noop).
  final Future<void> Function()? onCheckUpdate;

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> {
  DateTime _focusedDay = DateTime.now();
  List<Appointment> _appointments = [];
  bool _loading = true;
  // B6: visão corrente — dia (default), semana ou mês (via bottom sheet)
  _AgendaView _view = _AgendaView.dia;
  // Exibição dos agendamentos: lista (padrão) ou grade de 2 colunas.
  _AgendaLayout _layout = _AgendaLayout.lista;
  // Visão semana: dias recolhidos pelo usuário (aberto por padrão).
  final Set<DateTime> _collapsedDays = {};

  final ValueNotifier<bool> _updateBanner = ValueNotifier(false);
  bool _downloading = false;
  DateTime? _offlineSync;

  Future<void> _doUpdate() async {
    final info = UpdateService.lastCheck;
    if (info == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      await UpdateService.downloadAndInstall(info);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha ao atualizar: $e'),
            backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _downloading = false);
  }

  @override
  void initState() {
    super.initState();
    (widget.onCheckUpdate ??
        () => UpdateService.check().then((info) {
              if (info != null && mounted) _updateBanner.value = true;
            }))();
    _loadAppointments();
    // Offline fase 2: voltou a rede → replay da fila de escritas.
    _connRemove =
        ref.read(connectivityProvider.notifier).addListener(_onOnline);
  }

  void Function()? _connRemove;
  bool _syncing = false;

  @override
  void dispose() {
    _connRemove?.call();
    super.dispose();
  }

  void _onOnline(bool online) {
    if (!online || _syncing) return;
    _syncing = true;
    final queue = ref.read(syncQueueProvider.notifier);
    if (queue.count == 0) {
      _syncing = false;
      return;
    }
    queue.replay(ref.read(agendaApiProvider).dio).then((failures) {
      if (!mounted) return;
      if (failures.isEmpty) {
        if (queue.count == 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Agendamentos offline sincronizados!'),
              backgroundColor: Colors.green));
          _loadAppointments();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${failures.length} agendamento(s) não sincronizaram: ${failures.first.error}'),
            backgroundColor: AppColors.error));
        _loadAppointments();
      }
    }).whenComplete(() => _syncing = false);
  }

  Future<void> _loadAppointments() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(agendaApiProvider);
      // B6: janela conforme a visão — dia = 1 dia; semana = dom..sáb da semana
      // do dia focado; mês = dia 1 até o dia 1 do mês seguinte.
      final windowStart = _windowStart();
      final end = switch (_view) {
        _AgendaView.mes => DateTime(windowStart.year, windowStart.month + 1, 1),
        _AgendaView.semana => windowStart.add(const Duration(days: 7)),
        _AgendaView.dia => windowStart.add(const Duration(days: 1)),
      };
      final resp = await api.dio.get('/appointments', queryParameters: {
        'from': windowStart.toIso8601String(),
        'to': end.toIso8601String(),
      });
      final list = resp.data is List
          ? resp.data as List
          : (resp.data as Map<String, dynamic>)['appointments'] as List? ?? [];
      _appointments = list
          .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
          .toList();
      // Offline-first: cacheia a janela carregada (chave = visão+dia focado).
      try {
        await LocalCache.putBoxByDay(list, _cacheKeyForWindow());
      } catch (_) {
        // cache é best-effort
      }
    } catch (e) {
      debugPrint('[agenda] falha ao carregar (tentando cache offline): $e');
      // Offline-first: sem rede, serve a última janela cacheada desse dia.
      try {
        final cached = LocalCache.getListByDay(_cacheKeyForWindow());
        _appointments = cached
            .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
            .toList();
        _offlineSync = LocalCache.lastSync(_cacheKeyForWindow());
      } catch (_) {
        _offlineSync = null;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Início da janela visível: dia focado, domingo da semana ou dia 1 do mês.
  DateTime _windowStart() {
    final start = switch (_view) {
      _AgendaView.semana =>
        _focusedDay.subtract(Duration(days: _focusedDay.weekday % 7)),
      _AgendaView.mes => DateTime(_focusedDay.year, _focusedDay.month, 1),
      _AgendaView.dia => _focusedDay,
    };
    return DateTime(start.year, start.month, start.day);
  }

  /// Chave de cache da janela visível (dia/semana/mês do dia focado).
  String _cacheKeyForWindow() {
    final start = _windowStart();
    return 'appointments_${_view.name}_${start.year}-${start.month}-${start.day}';
  }

  /// Setas do rodapé: andam um mês, uma semana ou um dia, conforme a visão.
  void _shiftWindow(int delta) => setState(() {
        _focusedDay = switch (_view) {
          _AgendaView.mes =>
            DateTime(_focusedDay.year, _focusedDay.month + delta, 1),
          _AgendaView.semana => DateTime(
              _focusedDay.year, _focusedDay.month, _focusedDay.day + 7 * delta),
          _AgendaView.dia => _focusedDay.add(Duration(days: delta)),
        };
        // Semana nova começa com todos os dias abertos.
        _collapsedDays.clear();
        _loadAppointments();
      });

  void _today() => setState(() {
        _focusedDay = DateTime.now();
        _loadAppointments();
      });

  bool get _isToday {
    final now = DateTime.now();
    final sameMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;
    // No mês, "hoje" = estar no mês corrente.
    return _view == _AgendaView.mes
        ? sameMonth
        : sameMonth && _focusedDay.day == now.day;
  }

  /// B6: alterna dia/semana/mês preservando a data em foco.
  void _switchView(_AgendaView v) {
    setState(() => _view = v);
    _loadAppointments();
  }

  /// Mês: tocar num dia abre a visão dia daquela data.
  void _openDay(DateTime day) {
    setState(() {
      _view = _AgendaView.dia;
      _focusedDay = day;
    });
    _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR');
    final timeFmt = DateFormat('HH:mm', 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('AGENVA', style: Theme.of(context).textTheme.titleLarge),
            Text(
              dateFmt.format(_focusedDay).capitalize(),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          // "Hoje" só aparece quando estás deslocado do dia corrente —
          // em hoje seria um 3º caminho redundante (1 ação dominante por tela).
          if (!_isToday)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: 'Hoje',
              onPressed: _today,
            ),
          // B6: botão de mês no AppBar removido — redundante com o seletor
          // Dia/Semana/Mês (feedback Rafael 18/09). O "Mês" do seletor abre
          // o mesmo bottom sheet.
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configurações',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Banner de atualização (updater): nova versão disponível
                ValueListenableBuilder<bool>(
                  valueListenable: _updateBanner,
                  builder: (_, show, __) => !show
                      ? const SizedBox.shrink()
                      : Material(
                          color: Colors.deepOrange,
                          child: SafeArea(
                            top: false,
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.system_update,
                                  color: Colors.white),
                              title: const Text('Nova versão disponível',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              trailing: _downloading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : TextButton(
                                      onPressed: _doUpdate,
                                      child: const Text('Atualizar',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                    ),
                            ),
                          ),
                        ),
                ),
                // Banner de paywall (RF-14): aparece quando a API devolve 402
                ValueListenableBuilder<String?>(
                  valueListenable: PaywallFlag.lastMessage,
                  builder: (_, msg, __) => msg == null
                      ? const SizedBox.shrink()
                      : Material(
                          color: AppColors.error,
                          child: SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_outline,
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(msg,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            // Offline-first: banner quando servindo do cache
                            if (_offlineSync != null)
                              Material(
                                color: Colors.amber.shade700,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.cloud_off,
                                          color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Modo offline — dados de '
                                          '${DateFormat('HH:mm').format(_offlineSync!)}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // B6: seletor Dia / Semana / Mês (foco preservado)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: SegmentedButton<_AgendaView>(
                                segments: const [
                                  ButtonSegment(
                                      value: _AgendaView.dia,
                                      label: Text('Dia')),
                                  ButtonSegment(
                                      value: _AgendaView.semana,
                                      label: Text('Semana')),
                                  ButtonSegment(
                                      value: _AgendaView.mes,
                                      label: Text('Mês')),
                                ],
                                selected: {_view},
                                onSelectionChanged: (sel) =>
                                    _switchView(sel.first),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Ações no topo (antes eram FABs sobre a lista):
                            // marcar horário + bloquear horário (RF-A01).
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  FilledButton.icon(
                                    onPressed: _openBooking,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Marcar horário'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          AppColors.primaryOf(context),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    onPressed: _showBlockSheet,
                                    tooltip: 'Bloquear horário',
                                    icon: const Icon(Icons.lock_outline),
                                  ),
                                  // Lista/grade não se aplicam ao mês.
                                  if (_view != _AgendaView.mes) ...[
                                    const Spacer(),
                                    if (_view == _AgendaView.semana &&
                                        _appointments.isNotEmpty)
                                      _buildCollapseAllButton(),
                                    _buildLayoutToggle(_AgendaLayout.lista,
                                        Icons.view_agenda_outlined, 'Lista'),
                                    _buildLayoutToggle(_AgendaLayout.grade,
                                        Icons.grid_view_outlined, 'Grade'),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _view == _AgendaView.mes
                                  ? _MonthGrid(
                                      month: _windowStart(),
                                      appointments: _appointments,
                                      onDayTap: _openDay,
                                    )
                                  : _appointments.isEmpty
                                      ? _buildEmptyState(context)
                                      : _view == _AgendaView.semana
                                          ? _buildWeekList(timeFmt)
                                          : _layout == _AgendaLayout.grade
                                              ? _buildGrid(
                                                  _appointments, timeFmt)
                                              : ListView.builder(
                                                  padding:
                                                      const EdgeInsets.all(16),
                                                  itemCount:
                                                      _appointments.length,
                                                  itemBuilder: (_, i) =>
                                                      _buildAppointmentCard(
                                                          _appointments[i],
                                                          timeFmt),
                                                ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _buildDayNavigator(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    // B6: mensagem de vazio contextual por visão
    final title = _view == _AgendaView.semana
        ? 'Nada agendado pra semana'
        : 'Nada agendado pra hoje';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available,
                size: 80, color: AppColors.midOf(context)),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Toque em "Marcar horário" pra começar',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.neutral),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment a, DateFormat timeFmt) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          key: Key('hora-${a.id}'),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _timeBackground(a),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              timeFmt.format(a.startsAt),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: _timeForeground(a)),
            ),
          ),
        ),
        title: Text(
            a.isBlock ? (a.canceledReason ?? 'Bloqueado') : a.clientName,
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text.rich(
            a.isBlock
                ? TextSpan(text: '🔒 Bloqueado • ${_statusLabel(a.status)}')
                : _statusSubtitle(a),
            style: a.isBlock
                ? const TextStyle(fontStyle: FontStyle.italic)
                : null),
        trailing: _buildActionsMenu(a),
      ),
    );
  }

  /// Menu "⋮" de ações do agendamento (compartilhado entre lista e grade).
  Widget _buildActionsMenu(Appointment a) {
    return a.isBlock
        ? PopupMenuButton<String>(
            onSelected: (v) => _handleAppointmentAction(v, a),
            itemBuilder: (_) => [
              // Horário já passou: sem ações (nada a liberar).
              if (!_isPast(a))
                const PopupMenuItem(
                    value: 'cancel', child: Text('Liberar horário')),
            ],
          )
        : PopupMenuButton<String>(
            onSelected: (v) => _handleAppointmentAction(v, a),
            itemBuilder: (_) => [
              if (a.status == 'pending')
                const PopupMenuItem(value: 'confirm', child: Text('Confirmar')),
              if (a.status == 'pending' && !_isPast(a))
                const PopupMenuItem(
                    value: 'askConfirm',
                    child: Text('Pedir confirmação no WhatsApp')),
              const PopupMenuItem(value: 'edit', child: Text('Remarcar')),
              // Passou do horário: sem concluir/cancelar (decisão de
              // produto — ações de agendamento só com antecedência).
              if (!_isPast(a)) ...[
                const PopupMenuItem(value: 'done', child: Text('Concluir')),
                const PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
              ],
            ],
          );
  }

  /// Botão do alternador lista/grade; destacado quando é o layout atual.
  Widget _buildLayoutToggle(_AgendaLayout layout, IconData icon, String label) {
    final selected = _layout == layout;
    return IconButton(
      onPressed: () => setState(() => _layout = layout),
      tooltip: label,
      isSelected: selected,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? AppColors.softOf(context) : null,
        foregroundColor:
            selected ? AppColors.primaryOf(context) : AppColors.neutral,
      ),
    );
  }

  /// Grade de 2 colunas. [embedded] = dentro da lista da semana (sem
  /// scroll próprio; quem rola é a lista de dias).
  Widget _buildGrid(List<Appointment> items, DateFormat timeFmt,
      {bool embedded = false}) {
    return GridView.builder(
      padding: embedded ? EdgeInsets.zero : const EdgeInsets.all(16),
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 124,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildAppointmentTile(items[i], timeFmt),
    );
  }

  /// Card compacto da grade: horário + menu no topo, cliente e serviço abaixo.
  Widget _buildAppointmentTile(Appointment a, DateFormat timeFmt) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  key: Key('hora-${a.id}'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _timeBackground(a),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    timeFmt.format(a.startsAt),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: _timeForeground(a)),
                  ),
                ),
                const Spacer(),
                _buildActionsMenu(a),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                a.isBlock ? (a.canceledReason ?? 'Bloqueado') : a.clientName,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text.rich(
                a.isBlock
                    ? TextSpan(text: '🔒 ${_statusLabel(a.status)}')
                    : _statusSubtitle(a),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: a.isBlock ? FontStyle.italic : null),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayNavigator() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filled(
              onPressed: () => _shiftWindow(-1),
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.softOf(context),
                  foregroundColor: AppColors.primaryOf(context)),
            ),
            if (_view == _AgendaView.semana)
              Expanded(child: _buildWeekStrip())
            else if (_view == _AgendaView.dia)
              // Dia: tocar na data abre o seletor de dias do mês.
              TextButton.icon(
                onPressed: _pickDayOfMonth,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_drop_down),
                label: Text(DateFormat('dd/MM').format(_focusedDay)),
                style: TextButton.styleFrom(
                  foregroundColor:
                      Theme.of(context).textTheme.titleMedium?.color,
                  textStyle: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              )
            else
              Text(
                _view == _AgendaView.mes
                    ? DateFormat("MMMM 'de' yyyy", 'pt_BR')
                        .format(_focusedDay)
                        .capitalize()
                    : DateFormat('dd/MM').format(_focusedDay),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            IconButton.filled(
              onPressed: () => _shiftWindow(1),
              icon: const Icon(Icons.chevron_right),
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.softOf(context),
                  foregroundColor: AppColors.primaryOf(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// Abre o wizard de agendamento e, ao voltar, recarrega a lista. Se o
  /// wizard devolver o agendamento criado, foca no dia dele pra que apareça.
  Future<void> _openBooking() async {
    final created = await context.push<booking.Appointment?>('/agenda/booking');
    if (!mounted) return;
    if (created != null) {
      setState(() => _focusedDay = created.startsAt);
    }
    _loadAppointments();
  }

  /// Visão dia: popup acima do rodapé com os dias do mês em foco.
  Future<void> _pickDayOfMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => Dialog(
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.fromLTRB(16, 24, 16, 72),
        child: _DayOfMonthPicker(
          month: DateTime(_focusedDay.year, _focusedDay.month, 1),
          selectedDay: _focusedDay,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _focusedDay = picked);
      _loadAppointments();
    }
  }

  /// Rodapé da semana: os 7 dias (dom..sáb) da semana em foco; o dia em
  /// foco aparece como "dd/MM" destacado. Tocar num dia foca nele e deixa
  /// só ele aberto na lista da semana.
  Widget _buildWeekStrip() {
    final theme = Theme.of(context);
    final start = _windowStart();
    final focus =
        DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day);
    return Row(
      key: const Key('week-strip'),
      children: List.generate(7, (i) {
        final day = start.add(Duration(days: i));
        final selected = day == focus;
        return Expanded(
          flex: selected ? 2 : 1,
          child: InkWell(
            key: Key('week-strip-${DateFormat('yyyy-MM-dd').format(day)}'),
            onTap: () => _focusWeekDay(day),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.softOf(context) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selected ? DateFormat('dd/MM').format(day) : '${day.day}',
                maxLines: 1,
                style: (selected
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium)
                    ?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primaryOf(context) : null,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// B6: lista da semana — agrupa por dia com cabeçalho ("segunda, 15"),
  /// dias do mais recente para o mais antigo; horário crescente dentro do dia.
  Widget _buildWeekList(DateFormat timeFmt) {
    final dayFmt = DateFormat('EEEE, d', 'pt_BR');
    final byDay = <DateTime, List<Appointment>>{};
    for (final a in _appointments) {
      final d = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
      (byDay[d] ??= []).add(a);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final items = byDay[day]!
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        final collapsed = _collapsedDays.contains(day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho do dia: toque (ou seta) recolhe/mostra os agendamentos.
            InkWell(
              onTap: () => _toggleDay(day),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Row(
                  children: [
                    Text(
                      dayFmt.format(day).capitalize(),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: () => _toggleDay(day),
                      tooltip: collapsed ? 'Mostrar' : 'Recolher',
                      visualDensity: VisualDensity.compact,
                      color: AppColors.primaryOf(context),
                      icon: Icon(
                          collapsed ? Icons.expand_more : Icons.expand_less),
                    ),
                    const Spacer(),
                    _buildStatusSemaphore(items),
                  ],
                ),
              ),
            ),
            if (!collapsed && _layout == _AgendaLayout.grade)
              _buildGrid(items, timeFmt, embedded: true)
            else if (!collapsed)
              ...items.map((a) => _buildAppointmentCard(a, timeFmt)),
          ],
        );
      },
    );
  }

  /// Semana: foca [day] e recolhe os demais dias (mesma janela, sem refetch).
  void _focusWeekDay(DateTime day) {
    final start = _windowStart();
    setState(() {
      _focusedDay = day;
      _collapsedDays
        ..clear()
        ..addAll(List.generate(7, (i) => start.add(Duration(days: i)))
            .where((d) => d != day));
    });
  }

  /// Dias da semana que têm agendamento (os que aparecem na lista).
  Set<DateTime> get _weekDaysWithAppointments => _appointments
      .map((a) => DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day))
      .toSet();

  /// Semana: se algum dia está aberto recolhe todos; senão expande todos.
  Widget _buildCollapseAllButton() {
    final allCollapsed = _collapsedDays.containsAll(_weekDaysWithAppointments);
    return IconButton(
      onPressed: () => setState(() {
        if (allCollapsed) {
          _collapsedDays.clear();
        } else {
          _collapsedDays.addAll(_weekDaysWithAppointments);
        }
      }),
      tooltip: allCollapsed ? 'Expandir todos' : 'Recolher todos',
      icon: Icon(allCollapsed ? Icons.unfold_more : Icons.unfold_less),
      color: AppColors.neutral,
    );
  }

  void _toggleDay(DateTime day) {
    setState(() {
      if (!_collapsedDays.remove(day)) {
        _collapsedDays.add(day);
      }
    });
  }

  /// Classificação visual do status. Remarcar cancela a linha original com
  /// motivo "remarcado" (API B5) — ela aparece como remarcada, não cancelada.
  _StatusKind _statusKind(Appointment a) {
    if (a.isBlock) return _StatusKind.outro;
    if (a.status == 'done') return _StatusKind.concluido;
    if (a.status == 'confirmed') return _StatusKind.confirmado;
    if (a.status == 'canceled') {
      return a.canceledReason == 'remarcado'
          ? _StatusKind.remarcado
          : _StatusKind.cancelado;
    }
    return _StatusKind.outro;
  }

  static Color? _statusColor(_StatusKind k) => switch (k) {
        _StatusKind.concluido => AppColors.agenvaBlue,
        _StatusKind.confirmado => AppColors.success,
        _StatusKind.cancelado => AppColors.error,
        _StatusKind.remarcado => AppColors.warning,
        _StatusKind.outro => null,
      };

  /// Fundo do horário na cor do status (demais status: tom do tema).
  Color _timeBackground(Appointment a) =>
      _statusColor(_statusKind(a))?.withValues(alpha: 0.18) ??
      AppColors.softOf(context);

  Color _timeForeground(Appointment a) => switch (_statusKind(a)) {
        // amarelo puro some no fundo claro: texto em âmbar escuro
        _StatusKind.remarcado => const Color(0xFF8A5A00),
        final k => _statusColor(k) ?? AppColors.primaryOf(context),
      };

  /// "Serviço • Status"; concluído leva um check azul antes do status.
  InlineSpan _statusSubtitle(Appointment a) => TextSpan(
        text: '${a.serviceName} • ',
        children: [
          if (_statusKind(a) == _StatusKind.concluido)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(Icons.check_circle,
                    key: Key('check-concluido-${a.id}'),
                    size: 15,
                    color: AppColors.agenvaBlue),
              ),
            ),
          TextSpan(text: _displayStatus(a)),
        ],
      );

  String _displayStatus(Appointment a) =>
      _statusKind(a) == _StatusKind.remarcado
          ? 'Remarcado'
          : _statusLabel(a.status);

  /// Semáforo do dia: bolinhas azul/verde/vermelha/amarela com a quantidade
  /// de concluídos, confirmados, cancelados e remarcados (só as que têm 1+).
  Widget _buildStatusSemaphore(List<Appointment> items) {
    final counts = <_StatusKind, int>{};
    for (final a in items) {
      final k = _statusKind(a);
      if (k != _StatusKind.outro) counts[k] = (counts[k] ?? 0) + 1;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final k in const [
          _StatusKind.concluido,
          _StatusKind.confirmado,
          _StatusKind.cancelado,
          _StatusKind.remarcado,
        ])
          if ((counts[k] ?? 0) > 0)
            Tooltip(
              message: switch (k) {
                _StatusKind.concluido => 'Concluídos',
                _StatusKind.confirmado => 'Confirmados',
                _StatusKind.cancelado => 'Cancelados',
                _ => 'Remarcados',
              },
              child: Container(
                key: Key('semaforo-${k.name}'),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(left: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _statusColor(k),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${counts[k]}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: k == _StatusKind.remarcado
                        ? AppColors.neutral
                        : Colors.white,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'confirmed':
        return 'Confirmado';
      case 'done':
        return 'Concluído';
      case 'canceled':
        return 'Cancelado';
      case 'noshow':
        return 'Não compareceu';
      default:
        return status;
    }
  }

  /// Agendamento cujo horário já passou: sem cancelar/concluir/pedir
  /// confirmação (decisão de produto 21/09 — ação só com antecedência).
  bool _isPast(Appointment a) => a.startsAt.isBefore(DateTime.now());

  /// Ao cancelar, abre o WhatsApp do cliente com mensagem pronta.
  /// O cliente não tem app — WhatsApp é o canal onde ele já está.
  Future<void> _notifyCancelOnWhatsapp(Appointment a) async {
    final when = DateFormat('dd/MM "às" HH:mm', 'pt_BR').format(a.startsAt);
    final msg = Uri.encodeComponent(
        'Oi ${a.clientName}! Tive que remanejar teu horário de $when. '
        'Me chama pra combinarmos outro horário! 🙂');
    final phone = ensureDdi55(a.clientPhone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Avisar o cliente?'),
        content: Text(
            'Vou abrir teu WhatsApp com uma mensagem pronta pra ${a.clientName} avisando do cancelamento de $when.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não precisa')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir WhatsApp')),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// RF-B01: pede confirmação do cliente — abre o WhatsApp com mensagem pronta
  /// contendo data/hora + link pessoal de confirmação (token HMAC do agendamento).
  Future<void> _askConfirmationOnWhatsapp(Appointment a) async {
    final when = DateFormat('dd/MM "às" HH:mm', 'pt_BR').format(a.startsAt);
    final link = await _confirmationLink(a);
    final msg = Uri.encodeComponent(
        'Oi ${a.clientName}! Confirmando teu horário de $when. '
        'Pode confirmar tua presença aqui? $link 🙂');
    final phone = ensureDdi55(a.clientPhone);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pedir confirmação?'),
        content: Text(
            'Vou abrir teu WhatsApp com uma mensagem pra ${a.clientName} confirmar se vem em $when.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Agora não')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir WhatsApp')),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// Link público de confirmação: /p/<slug>/confirm/<id>?token=HMAC.
  /// O slug/token são gerados pela API no endpoint dedicado (RF-B01).
  Future<String> _confirmationLink(Appointment a) async {
    try {
      final api = ref.read(agendaApiProvider);
      final res = await api.dio.get('/appointments/${a.id}/confirm-link');
      return (res.data as Map<String, dynamic>)['link'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// RF-C01: após remarcar, oferece avisar o cliente com a NOVA data/hora.
  /// B-remarque: recebe o appointment NOVO do wizard (resposta do PATCH) —
  /// sem GET /appointments/:id (endpoint inexistente na API).
  Future<void> _notifyRescheduledOnWhatsapp(
      Appointment a, booking.Appointment? novo) async {
    final whenText = booking_logic
        .buildRescheduleMessage(a.clientName, novo)
        .replaceFirst('Oi ${a.clientName}! ', '');
    if (!mounted) return;
    final msg = Uri.encodeComponent(
        booking_logic.buildRescheduleMessage(a.clientName, novo));
    final phone = ensureDdi55(a.clientPhone);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Avisar o cliente?'),
        content: Text(
            'Vou abrir teu WhatsApp com uma mensagem pro ${a.clientName} com o novo horário ($whenText).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não precisa')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abrir WhatsApp')),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// RF-A01..A03: sheet de bloqueio de horário. Cria appointment
  /// source='block' ocupando o intervalo escolhido do dia focado.
  Future<void> _showBlockSheet() async {
    final api = ref.read(agendaApiProvider);
    final day = _focusedDay;
    TimeOfDay start = const TimeOfDay(hour: 12, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 13, minute: 0);
    final reasonCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          // barra de gestos + teclado (padrão do commit 888d475)
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bloquear horário',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  '${DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(day)} — clientes não verão este intervalo.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: start);
                      if (t != null) setSheet(() => start = t);
                    },
                    child: Text('Início ${start.format(ctx)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t =
                          await showTimePicker(context: ctx, initialTime: end);
                      if (t != null) setSheet(() => end = t);
                    },
                    child: Text('Fim ${end.format(ctx)}'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional, só você vê)',
                  hintText: 'ex.: dentista',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: const Text('Bloquear'),
                onPressed: () {
                  if (start.hour * 60 + start.minute >=
                      end.hour * 60 + end.minute) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('O fim deve ser depois do início')));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      // find-or-create do par cliente/serviço técnico do bloqueio
      final blockIds = await _ensureBlockClientAndService(api);
      final startDt =
          DateTime(day.year, day.month, day.day, start.hour, start.minute);
      final endDt =
          DateTime(day.year, day.month, day.day, end.hour, end.minute);
      await api.dio.post('/appointments', data: {
        'clientId': blockIds['clientId'],
        'serviceId': blockIds['serviceId'],
        'startsAt': startDt.toIso8601String(),
        'endsAt': endDt.toIso8601String(),
        'source': 'block',
        if (reasonCtrl.text.trim().isNotEmpty)
          'canceledReason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Horário bloqueado 🔒')));
        await _loadAppointments();
      }
    } catch (e) {
      debugPrint('[agenda] falha ao bloquear: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não consegui bloquear: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  /// RF-A: o schema exige clientId+serviceId; bloqueio usa par técnico
  /// reutilizável (cliente '— bloqueio —', serviço 'Bloqueio', preço 0).
  Future<Map<String, String>> _ensureBlockClientAndService(
      ApiClient api) async {
    final clientsRes = await api.dio.get('/clients');
    final clients = (clientsRes.data['clients'] as List? ?? []);
    final existingClient = clients.firstWhere(
      (c) => (c is Map) && c['name'] == '— bloqueio —',
      orElse: () => null,
    );
    String clientId;
    if (existingClient != null) {
      clientId = existingClient['id'] as String;
    } else {
      final created =
          await api.dio.post('/clients', data: {'name': '— bloqueio —'});
      clientId = (created.data['client'] as Map)['id'] as String;
    }

    final servicesRes = await api.dio.get('/services');
    final services = (servicesRes.data['services'] as List? ?? []);
    final existingService = services.firstWhere(
      (s) => (s is Map) && s['name'] == 'Bloqueio',
      orElse: () => null,
    );
    String serviceId;
    if (existingService != null) {
      serviceId = existingService['id'] as String;
    } else {
      final created = await api.dio.post('/services',
          data: {'name': 'Bloqueio', 'duration_min': 60, 'price_cents': 0});
      serviceId = (created.data['service'] as Map)['id'] as String;
    }
    return {'clientId': clientId, 'serviceId': serviceId};
  }

  Future<void> _handleAppointmentAction(String action, Appointment a) async {
    final api = ref.read(agendaApiProvider);
    try {
      switch (action) {
        case 'cancel':
          await api.dio
              .patch('/appointments/${a.id}', data: {'status': 'canceled'});
          // fora da caixa: avisa o cliente pelo WhatsApp que ele já tem
          if (mounted && a.clientPhone.isNotEmpty && !a.isBlock) {
            await _notifyCancelOnWhatsapp(a);
          }
          break;
        case 'done':
          await api.dio
              .patch('/appointments/${a.id}', data: {'status': 'done'});
          break;
        case 'confirm':
          await api.dio
              .patch('/appointments/${a.id}', data: {'status': 'confirmed'});
          break;
        case 'askConfirm':
          await _askConfirmationOnWhatsapp(a);
          return;
        case 'edit':
          // remarcar: abre o wizard reaproveitando cliente+serviço
          if (!mounted) return;
          // B3: converte pro model do wizard (classes distintas)
          final target = booking.Appointment(
            id: a.id,
            startsAt: a.startsAt,
            endsAt: a.endsAt,
            status: a.status,
            clientId: a.clientId,
            serviceId: a.serviceId,
          );
          final changed = await context.push<booking.Appointment?>(
              '/agenda/booking',
              extra: {'reschedule': target});
          if (!mounted) {
            return;
          }
          await _loadAppointments();
          if (!mounted) {
            return;
          }
          if (changed != null) {
            // RF-C01: remarcou — oferece avisar o cliente no WhatsApp.
            // B-remarque: `changed` é a NOVA linha (id novo da API);
            // null = retorno sem agendamento (cancelamento/offline).
            if (mounted && a.clientPhone.isNotEmpty) {
              await _notifyRescheduledOnWhatsapp(a, changed);
            }
          }
          return;
      }
      if (mounted) await _loadAppointments();
    } catch (e) {
      debugPrint('[agenda] falha em $action: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não consegui $action: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }
}

class Appointment {
  final String id;
  final String clientName;
  final String clientPhone;
  final String serviceName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  // RF-A: 'app' | 'public_link' | 'block' — block = bloqueio de horário
  final String source;
  // RF-A02: motivo do bloqueio (mesma coluna de canceled_reason)
  final String? canceledReason;
  // B3: FKs pro modo remarcar (wizard pré-preenche cliente/serviço)
  final String? clientId;
  final String? serviceId;

  bool get isBlock => source == 'block';

  Appointment({
    required this.id,
    required this.clientName,
    required this.clientPhone,
    required this.serviceName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.source = 'app',
    this.canceledReason,
    this.clientId,
    this.serviceId,
  });

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'],
        clientName: j['client_name'] ?? j['clientName'] ?? '',
        clientPhone: j['client_phone'] ?? j['clientPhone'] ?? '',
        serviceName: j['service_name'] ?? j['serviceName'] ?? '',
        startsAt: DateTime.parse(j['starts_at'] ?? j['startsAt']).toLocal(),
        endsAt: DateTime.parse(j['ends_at'] ?? j['endsAt']).toLocal(),
        status: j['status'] ?? 'pending',
        source: j['source'] ?? 'app',
        canceledReason: j['canceled_reason'] ?? j['canceledReason'],
        clientId: j['client_id'] ?? j['clientId'],
        serviceId: j['service_id'] ?? j['serviceId'],
      );
}

/// Calendário mensal em bottom sheet: dias com eventos têm bolinha na cor
/// primária; tocar num dia fecha e navega a agenda diária pra ele.
/// Visão mês: calendário ocupando a tela, com os agendamentos de cada dia
/// listados dentro da célula (nome do cliente, em ordem de horário).
class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<Appointment> appointments;
  final ValueChanged<DateTime> onDayTap;

  const _MonthGrid({
    required this.month,
    required this.appointments,
    required this.onDayTap,
  });

  static const _weekdays = [
    'DOM.',
    'SEG.',
    'TER.',
    'QUA.',
    'QUI.',
    'SEX.',
    'SÁB.'
  ];
  static const _minCellHeight = 96.0;
  static const _dayNumberHeight = 30.0;
  static const _chipHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = <DateTime, List<Appointment>>{};
    for (final a in appointments) {
      final d = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
      (byDay[d] ??= []).add(a);
    }
    for (final list in byDay.values) {
      list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    final firstWeekday = month.weekday % 7; // domingo = 0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = (firstWeekday + daysInMonth + 6) ~/ 7;

    return Column(
      children: [
        if (appointments.isEmpty)
          // Empty state do mês: texto discreto, o calendário continua visível.
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Nada agendado neste mês',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.neutral, fontStyle: FontStyle.italic)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: _weekdays
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.neutral)),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final cellHeight = (constraints.maxHeight / rows) < _minCellHeight
                ? _minCellHeight
                : constraints.maxHeight / rows;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: List.generate(rows, (week) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(7, (col) {
                      final dayNum = week * 7 + col - firstWeekday + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return Expanded(child: SizedBox(height: cellHeight));
                      }
                      final day = DateTime(month.year, month.month, dayNum);
                      return Expanded(
                        child: _buildDay(
                            context, day, byDay[day] ?? const [], cellHeight),
                      );
                    }),
                  );
                }),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDay(BuildContext context, DateTime day, List<Appointment> events,
      double height) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    // Quantos nomes cabem; o excedente vira "+N".
    final fit = ((height - _dayNumberHeight - 4) / _chipHeight).floor();
    final overflow = events.length > fit;
    final shown = overflow ? events.take(fit - 1).toList() : events;

    return InkWell(
      onTap: () => onDayTap(day),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(top: 2, bottom: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? AppColors.primaryOf(context) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? Colors.white : null,
                ),
              ),
            ),
            ...shown.map((a) => _buildChip(context, a)),
            if (overflow)
              Text('+${events.length - shown.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10, color: AppColors.primaryOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, Appointment a) {
    final canceled = a.status == 'canceled';
    final label =
        a.isBlock ? '🔒 ${a.canceledReason ?? 'Bloqueado'}' : a.clientName;
    return Container(
      height: _chipHeight - 2,
      margin: const EdgeInsets.only(bottom: 2, left: 2, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        // softOf já é translúcida; cancelado fica num cinza neutro.
        color: canceled
            ? AppColors.neutral.withValues(alpha: 0.12)
            : AppColors.softOf(context),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          color: canceled ? AppColors.neutral : AppColors.primaryOf(context),
          decoration: canceled ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// Seletor compacto dos dias de um mês (popup da visão dia).
class _DayOfMonthPicker extends StatelessWidget {
  final DateTime month;
  final DateTime selectedDay;

  const _DayOfMonthPicker({required this.month, required this.selectedDay});

  static const _weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstWeekday = month.weekday % 7; // domingo = 0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = (firstWeekday + daysInMonth + 6) ~/ 7;
    final now = DateTime.now();

    return Padding(
      key: const Key('day-picker'),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat("MMMM 'de' yyyy", 'pt_BR').format(month).capitalize(),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: _weekdays
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: AppColors.neutral)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          ...List.generate(rows, (week) {
            return Row(
              children: List.generate(7, (col) {
                final dayNum = week * 7 + col - firstWeekday + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 40));
                }
                final day = DateTime(month.year, month.month, dayNum);
                final selected = dayNum == selectedDay.day;
                final isToday = day.year == now.year &&
                    day.month == now.month &&
                    day.day == now.day;
                return Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context, day),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.primaryOf(context) : null,
                        border: isToday && !selected
                            ? Border.all(color: AppColors.primaryOf(context))
                            : null,
                      ),
                      child: Text(
                        '$dayNum',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }
}

/// B6: visões da agenda (dia, semana e mês).
enum _AgendaView { dia, semana, mes }

enum _AgendaLayout { lista, grade }

enum _StatusKind { concluido, confirmado, cancelado, remarcado, outro }

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
