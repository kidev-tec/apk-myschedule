import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/paywall_flag.dart';
import '../../core/update/update_service.dart';
import '../../theme/app_theme.dart';

class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key});

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> {
  DateTime _focusedDay = DateTime.now();
  List<Appointment> _appointments = [];
  bool _loading = true;

  final ValueNotifier<bool> _updateBanner = ValueNotifier(false);
  bool _downloading = false;

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
    UpdateService.check().then((info) {
      if (info != null && mounted) _updateBanner.value = true;
    });
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final start =
          DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day);
      final end = start.add(const Duration(days: 1));
      final resp = await api.dio.get('/appointments', queryParameters: {
        'from': start.toIso8601String(),
        'to': end.toIso8601String(),
      });
      final list = resp.data is List
          ? resp.data as List
          : (resp.data as Map<String, dynamic>)['appointments'] as List? ?? [];
      _appointments =
          list.map((j) => Appointment.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[agenda] falha ao carregar: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _prevDay() => setState(() {
        _focusedDay = _focusedDay.subtract(const Duration(days: 1));
        _loadAppointments();
      });

  void _nextDay() => setState(() {
        _focusedDay = _focusedDay.add(const Duration(days: 1));
        _loadAppointments();
      });

  void _today() => setState(() {
        _focusedDay = DateTime.now();
        _loadAppointments();
      });

  /// Visão mensal: bottom sheet com grid do mês, marca dias com agendamentos
  /// e permite pular pro dia tocado. Carrega o mês inteiro numa query.
  Future<void> _openMonthView() async {
    setState(() => _loading = true);
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
    Map<DateTime, List<Appointment>> byDay = {};
    try {
      final api = ApiClient();
      final resp = await api.dio.get('/appointments', queryParameters: {
        'from': monthStart.toIso8601String(),
        'to': monthEnd.toIso8601String(),
      });
      final rawList = resp.data is List
          ? resp.data as List
          : (resp.data as Map<String, dynamic>)['appointments'] as List? ?? [];
      final all = rawList
          .map((j) => Appointment.fromJson(j as Map<String, dynamic>))
          .toList();
      for (final a in all) {
        final d = DateTime(a.startsAt.year, a.startsAt.month, a.startsAt.day);
        (byDay[d] ??= []).add(a);
      }
    } catch (e) {
      debugPrint('[agenda] falha na view mensal: $e');
    }
    if (mounted) setState(() => _loading = false);

    if (!mounted) return;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MonthPicker(
        initialMonth: monthStart,
        eventsByDay: byDay,
        selectedDay: _focusedDay,
      ),
    );
    if (picked != null) {
      setState(() => _focusedDay = picked);
      _loadAppointments();
    }
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
            Text('Minha Agenda', style: Theme.of(context).textTheme.titleLarge),
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
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Hoje',
            onPressed: _today,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Agenda completa (mês)',
            onPressed: _openMonthView,
          ),
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
                                          strokeWidth: 2,
                                          color: Colors.white))
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
                  child: _appointments.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _appointments.length,
                          itemBuilder: (_, i) =>
                              _buildAppointmentCard(_appointments[i], timeFmt),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/booking'),
        icon: const Icon(Icons.add),
        label: const Text('Marcar horário'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: _buildDayNavigator(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_available,
                size: 80, color: AppColors.pinkMid),
            const SizedBox(height: 16),
            Text(
              'Nada agendado pra hoje',
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.pinkSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              timeFmt.format(a.startsAt),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.primary),
            ),
          ),
        ),
        title:
            Text(a.clientName, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text('${a.serviceName} • ${_statusLabel(a.status)}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _handleAppointmentAction(v, a),
          itemBuilder: (_) => [
            if (a.status == 'pending')
              const PopupMenuItem(value: 'confirm', child: Text('Confirmar')),
            const PopupMenuItem(value: 'edit', child: Text('Remarcar')),
            const PopupMenuItem(value: 'done', child: Text('Concluir')),
            const PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
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
              onPressed: _prevDay,
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.pinkSoft,
                  foregroundColor: AppColors.primary),
            ),
            Text(
              DateFormat('dd/MM').format(_focusedDay),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            IconButton.filled(
              onPressed: _nextDay,
              icon: const Icon(Icons.chevron_right),
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.pinkSoft,
                  foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
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

  Future<void> _handleAppointmentAction(String action, Appointment a) async {
    final api = ApiClient();
    try {
      switch (action) {
        case 'cancel':
          await api.dio.patch('/appointments/${a.id}',
              data: {'status': 'canceled'});
          break;
        case 'done':
          await api.dio.patch('/appointments/${a.id}',
              data: {'status': 'done'});
          break;
        case 'confirm':
          await api.dio.patch('/appointments/${a.id}',
              data: {'status': 'confirmed'});
          break;
        case 'edit':
          // remarcar: abre o wizard reaproveitando cliente+serviço
          if (!mounted) return;
          final changed = await context
              .push<bool>('/booking', extra: {'reschedule': a});
          if (changed != true) {
            await _loadAppointments();
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
  final String serviceName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;

  Appointment({
    required this.id,
    required this.clientName,
    required this.serviceName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'],
        clientName: j['client_name'] ?? j['clientName'] ?? '',
        serviceName: j['service_name'] ?? j['serviceName'] ?? '',
        startsAt: DateTime.parse(j['starts_at'] ?? j['startsAt']),
        endsAt: DateTime.parse(j['ends_at'] ?? j['endsAt']),
        status: j['status'] ?? 'pending',
      );
}

/// Calendário mensal em bottom sheet: dias com eventos têm bolinha na cor
/// primária; tocar num dia fecha e navega a agenda diária pra ele.
class _MonthPicker extends StatefulWidget {
  final DateTime initialMonth;
  final Map<DateTime, List<Appointment>> eventsByDay;
  final DateTime selectedDay;

  const _MonthPicker({
    required this.initialMonth,
    required this.eventsByDay,
    required this.selectedDay,
  });

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late DateTime _month =
      DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
  static const _weekdays = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta, 1));

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat("MMMM 'de' yyyy", 'pt_BR');
    final firstWeekday = (_month.weekday % 7); // domingo = 0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final sel0 = DateTime(widget.selectedDay.year, widget.selectedDay.month,
        widget.selectedDay.day);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftMonth(-1)),
                Text(monthFmt.format(_month).capitalize(),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shiftMonth(1)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: _weekdays
                  .map((w) => Expanded(
                        child: Center(
                          child: Text(w,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            ...List.generate((firstWeekday + daysInMonth + 6) ~/ 7, (week) {
              return Row(
                children: List.generate(7, (col) {
                  final dayNum = week * 7 + col - firstWeekday + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 44));
                  }
                  final day = DateTime(_month.year, _month.month, dayNum);
                  final hasEvents =
                      (widget.eventsByDay[day]?.isNotEmpty ?? false);
                  final isToday = day == today0;
                  final isSelected = day == sel0;
                  return Expanded(
                    child: SizedBox(
                      height: 44,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => Navigator.pop(context, day),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.primary
                                    : isToday
                                        ? AppColors.primary
                                            .withValues(alpha: 0.15)
                                        : null,
                              ),
                              child: Text(
                                '$dayNum',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: isToday || isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isSelected ? Colors.white : null,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: hasEvents
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
