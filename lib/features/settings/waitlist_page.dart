import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/utils/phone_br.dart';
import '../../theme/app_theme.dart';
import '../../core/widgets/home_action.dart';

/// F5 — Lista de espera: quem quer vaga em um dia específico.
///
/// O cliente entra pelo link de agendamento ("Entrar na lista de espera") ou
/// o prestador adiciona aqui (pedido por telefone/WhatsApp). Quando abre uma
/// vaga, "Avisar" abre o WhatsApp com a mensagem pronta e marca como avisado.
class WaitlistPage extends ConsumerStatefulWidget {
  const WaitlistPage({super.key, this.api, this.initialDay, this.openUrl});

  final ApiClient? api;

  /// Dia inicial (ex.: tocou na notificação "Vaga abriu").
  final DateTime? initialDay;

  /// Abre o link do WhatsApp (injetável nos testes).
  final Future<void> Function(Uri url)? openUrl;

  @override
  ConsumerState<WaitlistPage> createState() => _WaitlistPageState();
}

class _WaitlistPageState extends ConsumerState<WaitlistPage> {
  late DateTime _day = _dateOnly(widget.initialDay ?? DateTime.now());
  List<Map<String, dynamic>>? _entries;
  String? _error;
  bool _loading = true;

  late final ApiClient _api = widget.api ?? ApiClient();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  String get _dateStr => DateFormat('yyyy-MM-dd').format(_day);
  bool get _isPast => _day.isBefore(_dateOnly(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r =
          await _api.dio.get('/waitlist', queryParameters: {'date': _dateStr});
      if (!mounted) return;
      setState(() {
        _entries = (r.data['waitlist'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanError(e);
        _loading = false;
      });
    }
  }

  Future<void> _changeDay(int days) async {
    setState(() => _day = _day.add(Duration(days: days)));
    await _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _day = _dateOnly(picked));
    await _load();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: error ? AppColors.error : null));
  }

  Future<bool> _mark(String id, String status) async {
    try {
      await _api.dio.patch('/waitlist/$id', data: {'status': status});
      await _load();
      return true;
    } catch (e) {
      _snack(humanError(e), error: true);
      return false;
    }
  }

  /// Abre o WhatsApp com a mensagem da vaga e marca como avisado.
  Future<void> _notify(Map<String, dynamic> e) async {
    final name = (e['client_name'] as String).split(' ').first;
    final weekday = DateFormat('EEEE', 'pt_BR').format(_day);
    final msg = 'Olá, $name! Abriu um horário no dia '
        '${DateFormat('dd/MM').format(_day)} ($weekday). '
        'Você ainda tem interesse? Me responda por aqui que eu agendo 🙂';
    final url = Uri.parse('https://wa.me/${ensureDdi55(e['phone'] as String)}'
        '?text=${Uri.encodeComponent(msg)}');
    try {
      await (widget.openUrl ??
          (u) => launchUrl(u, mode: LaunchMode.externalApplication))(url);
    } catch (_) {
      _snack('Não foi possível abrir o WhatsApp.', error: true);
      return;
    }
    await _mark(e['id'] as String, 'notified');
  }

  Future<void> _remove(Map<String, dynamic> e) async {
    try {
      await _api.dio.delete('/waitlist/${e['id']}');
      _snack('${e['client_name']} saiu da lista de espera.');
      await _load();
    } catch (err) {
      _snack(humanError(err), error: true);
    }
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddSheet(api: _api, day: _day, dateStr: _dateStr),
    );
    if (added == null) return;
    _snack('$added entrou na lista de espera.');
    await _load();
  }

  String _statusLabel(String s) => switch (s) {
        'waiting' => 'aguardando',
        'notified' => 'avisado',
        'served' => 'atendido',
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('EEEE, dd/MM', 'pt_BR').format(_day);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Lista de espera'), actions: const [HomeAction()]),
      floatingActionButton: _isPast
          ? null
          : FloatingActionButton.extended(
              key: const Key('waitlist-add'),
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    tooltip: 'Dia anterior',
                    onPressed: () => _changeDay(-1),
                    icon: const Icon(Icons.chevron_left)),
                TextButton(
                  key: const Key('waitlist-day'),
                  onPressed: _pickDay,
                  child: Text('${title[0].toUpperCase()}${title.substring(1)}',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                    tooltip: 'Próximo dia',
                    onPressed: () => _changeDay(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Clientes que querem um horário neste dia. Eles entram pelo '
              'seu link de agendamento ou você adiciona aqui. Quando abrir '
              'uma vaga, toque em Avisar.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _load, child: const Text('Tentar novamente')),
          ]),
        ),
      );
    }
    final entries = _entries ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ninguém na espera para esse dia.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          for (final e in entries) _tile(e),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> e) {
    final status = e['status'] as String;
    final id = e['id'] as String;
    return Card(
      key: Key('waitlist-$id'),
      child: ListTile(
        leading: Icon(
          status == 'served'
              ? Icons.check_circle
              : status == 'notified'
                  ? Icons.notifications_active
                  : Icons.hourglass_top,
          color: status == 'waiting'
              ? AppColors.primaryOf(context)
              : AppColors.success,
        ),
        title: Text(e['client_name'] as String),
        subtitle: Text(
            '${phoneForDisplay(e['phone'] as String)} · ${_statusLabel(status)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == 'waiting')
              TextButton(
                key: Key('waitlist-notify-$id'),
                onPressed: () => _notify(e),
                child: const Text('Avisar'),
              )
            else if (status == 'notified')
              TextButton(
                key: Key('waitlist-served-$id'),
                onPressed: () => _mark(id, 'served'),
                child: const Text('Atendido'),
              ),
            PopupMenuButton<String>(
              key: Key('waitlist-menu-$id'),
              tooltip: 'Mais opções',
              onSelected: (v) => switch (v) {
                'notify' => _notify(e),
                'waiting' => _mark(id, 'waiting'),
                _ => _remove(e),
              },
              itemBuilder: (_) => [
                if (status != 'waiting')
                  const PopupMenuItem(
                      value: 'notify', child: Text('Avisar de novo')),
                if (status != 'waiting')
                  const PopupMenuItem(
                      value: 'waiting', child: Text('Voltar para aguardando')),
                const PopupMenuItem(
                    value: 'remove', child: Text('Remover da lista')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Adicionar à espera: escolhe um cliente cadastrado ou digita nome e
/// WhatsApp. Fecha devolvendo o nome de quem entrou.
class _AddSheet extends StatefulWidget {
  const _AddSheet(
      {required this.api, required this.day, required this.dateStr});

  final ApiClient api;
  final DateTime day;
  final String dateStr;

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  List<Map<String, dynamic>> _clients = const [];
  String _query = '';
  bool _newClient = false;
  bool _saving = false;
  String? _error;
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.api.dio.get('/clients').then((r) {
      if (!mounted) return;
      setState(() =>
          _clients = (r.data as List).cast<Map<String, dynamic>>().toList());
    }, onError: (Object _) {
      // sem a lista: ainda dá pra adicionar digitando nome e WhatsApp
      if (mounted) setState(() => _newClient = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> body, String name) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await widget.api.dio
          .post('/waitlist', data: {...body, 'desired_date': widget.dateStr});
      if (!mounted) return;
      Navigator.of(context).pop((r.data as Map)['client_name'] ?? name);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = humanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    final found = _clients
        .where((c) =>
            (c['name'] as String).toLowerCase().contains(q) ||
            (digits.isNotEmpty &&
                (c['phone_e164'] as String? ?? '').contains(digits)))
        .take(30)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                'Adicionar à espera de ${DateFormat('dd/MM').format(widget.day)}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const Key('waitlist-add-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('Já é cliente')),
                ButtonSegment(value: true, label: Text('Cliente novo')),
              ],
              selected: {_newClient},
              onSelectionChanged: (s) => setState(() {
                _newClient = s.first;
                _error = null;
              }),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    key: const Key('waitlist-add-error'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            const SizedBox(height: 12),
            if (_newClient) ...[
              TextField(
                key: const Key('waitlist-new-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('waitlist-new-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'WhatsApp (com DDD)'),
                onChanged: (v) {
                  final m = maskPhoneBr(v);
                  if (m != v) {
                    _phone.value = TextEditingValue(
                        text: m,
                        selection: TextSelection.collapsed(offset: m.length));
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('waitlist-new-save'),
                onPressed: _saving
                    ? null
                    : () => _save({
                          'name': _name.text.trim(),
                          'phone': _phone.text,
                        }, _name.text.trim()),
                child: const Text('Adicionar à lista'),
              ),
            ] else ...[
              TextField(
                key: const Key('waitlist-search'),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Buscar por nome ou celular'),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: found.isEmpty
                    ? const Center(child: Text('Nenhum cliente encontrado.'))
                    : ListView(
                        children: [
                          for (final c in found)
                            ListTile(
                              key: Key('waitlist-pick-${c['id']}'),
                              enabled: !_saving,
                              title: Text(c['name'] as String),
                              subtitle: Text(phoneForDisplay(
                                  c['phone_e164'] as String? ?? '')),
                              onTap: () => _save(
                                  {'client_id': c['id']}, c['name'] as String),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
