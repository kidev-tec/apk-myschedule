import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../theme/app_theme.dart';

class BookingWizardPage extends ConsumerStatefulWidget {
  const BookingWizardPage({super.key});

  @override
  ConsumerState<BookingWizardPage> createState() => _BookingWizardPageState();
}

class _BookingWizardPageState extends ConsumerState<BookingWizardPage> {
  final PageController _pageController = PageController();
  int _step = 0;

  List<Client> _clients = [];
  List<Service> _services = [];
  List<WorkingHour> _workingHours = [];
  List<Appointment> _existingAppointments = [];
  DateTime _selectedDate = DateTime.now();

  Client? _selectedClient;
  Service? _selectedService;
  DateTime? _selectedSlot;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    final api = ApiClient();
    try {
      final results = await Future.wait([
        api.dio.get('/clients'),
        api.dio.get('/services'),
        api.dio.get('/working-hours'),
        api.dio.get('/appointments', queryParameters: {
          'from': DateTime.now()
              .subtract(const Duration(days: 30))
              .toIso8601String(),
          'to': DateTime.now()
              .add(const Duration(days: 90))
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
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<DateTime> _generateSlots(DateTime date) {
    final weekday = date.weekday % 7; // 0=dom..6=sáb
    final dayHours = _workingHours.where((h) => h.weekday == weekday).toList();
    if (dayHours.isEmpty) return [];

    final slots = <DateTime>[];
    final dayAppointments = _existingAppointments
        .where((a) =>
            a.startsAt.year == date.year &&
            a.startsAt.month == date.month &&
            a.startsAt.day == date.day)
        .where((a) => a.status == 'pending' || a.status == 'confirmed')
        .toList();

    for (final wh in dayHours) {
      var cursor = DateTime(date.year, date.month, date.day, wh.startTime.hour,
          wh.startTime.minute);
      final end = DateTime(
          date.year, date.month, date.day, wh.endTime.hour, wh.endTime.minute);

      while (cursor
              .add(Duration(minutes: _selectedService?.durationMin ?? 60))
              .isBefore(end) ||
          cursor
              .add(Duration(minutes: _selectedService?.durationMin ?? 60))
              .isAtSameMomentAs(end)) {
        final slotEnd =
            cursor.add(Duration(minutes: _selectedService?.durationMin ?? 60));
        final overlaps = dayAppointments.any(
            (a) => a.startsAt.isBefore(slotEnd) && a.endsAt.isAfter(cursor));
        if (!overlaps) slots.add(cursor);
        cursor = cursor.add(const Duration(minutes: 15)); // step 15 min
      }
    }
    return slots;
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

  Future<void> _createAppointment() async {
    if (_selectedClient == null ||
        _selectedService == null ||
        _selectedSlot == null) {
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ApiClient();
      await api.dio.post('/appointments', data: {
        'client_id': _selectedClient!.id,
        'service_id': _selectedService!.id,
        'starts_at': _selectedSlot!.toIso8601String(),
        'ends_at': _selectedSlot!
            .add(Duration(minutes: _selectedService!.durationMin))
            .toIso8601String(),
        'source': 'app',
      });
      if (mounted) {
        context.go('/agenda');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Horário marcado!'), backgroundColor: Colors.green),
        );
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
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text([
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
                  onPressed: _canProceed() ? _nextStep : null,
                  child:
                      Text(_step == 2 ? 'Confirmar agendamento' : 'Continuar'),
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

  Widget _buildClientStep() {
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
            onChanged: (v) => setState(() {}), // filter handled in list
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _clients.length,
            itemBuilder: (_, i) {
              final c = _clients[i];
              final selected = _selectedClient?.id == c.id;
              return Card(
                color: selected ? AppColors.pinkSoft : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text(c.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(c.name),
                  subtitle: Text(c.phoneE164),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () => setState(() => _selectedClient = c),
                ),
              );
            },
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
          color: selected ? AppColors.pinkSoft : null,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.content_cut, color: Colors.white),
            ),
            title: Text(s.name),
            subtitle: Text(
                '${s.durationMin} min • ${priceFmt.format(s.priceCents / 100)}'),
            trailing: selected
                ? const Icon(Icons.check_circle, color: AppColors.primary)
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
          color: AppColors.pinkSoft.withValues(alpha: 0.3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1)))),
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
                      color: selected ? AppColors.primary : AppColors.pinkSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              selected ? AppColors.primary : Colors.transparent,
                          width: 2),
                    ),
                    child: Center(
                      child: Text(
                        timeFmt.format(slot),
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
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

  Appointment(
      {required this.id,
      required this.startsAt,
      required this.endsAt,
      required this.status});

  factory Appointment.fromJson(Map<String, dynamic> j) => Appointment(
        id: j['id'],
        startsAt: DateTime.parse(j['starts_at'] ?? j['startsAt']),
        endsAt: DateTime.parse(j['ends_at'] ?? j['endsAt']),
        status: j['status'] ?? 'pending',
      );
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
