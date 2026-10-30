import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../theme/app_theme.dart';

/// Uma notificação da central (GET /notifications).
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: j['type'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        read: j['read'] == true,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );

  /// Dia do agendamento ligado à notificação (abre a agenda nele).
  DateTime? get appointmentDay {
    final s = data['starts_at'];
    return s is String ? DateTime.tryParse(s)?.toLocal() : null;
  }
}

/// Ícone e cor por tipo de notificação.
(IconData, Color) notificationStyle(String type) => switch (type) {
      'new_booking' => (Icons.event_available, Colors.green.shade700),
      'client_confirmed' => (Icons.check_circle, Colors.green.shade700),
      'client_canceled' => (Icons.cancel, Colors.red.shade700),
      'reminder' => (Icons.alarm, Colors.blue.shade700),
      'waitlist' => (Icons.hourglass_top, Colors.purple.shade600),
      _ => (Icons.notifications, Colors.blueGrey),
    };

/// Central de notificações: lista (mais novas primeiro, por dia), não lidas
/// em destaque, "marcar todas como lidas". Tocar marca como lida e, se a
/// notificação é de um agendamento, volta pra agenda no dia dele
/// (pop com o DateTime).
class NotificationsPage extends StatefulWidget {
  final ApiClient? api;
  final DateTime Function() clock;

  const NotificationsPage({super.key, this.api, this.clock = DateTime.now});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _pageSize = 30;

  late final ApiClient _api = widget.api ?? ApiClient();
  final List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  int get _unread => _items.where((n) => !n.read).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      more ? _loadingMore = true : _loading = true;
      _error = null;
    });
    try {
      final r = await _api.dio.get('/notifications', queryParameters: {
        'limit': _pageSize,
        if (more && _items.isNotEmpty)
          'before': _items.last.createdAt.toUtc().toIso8601String(),
      });
      final list = [
        for (final j in (r.data['notifications'] as List))
          AppNotification.fromJson(j as Map<String, dynamic>),
      ];
      if (!more) _items.clear();
      _items.addAll(list);
      _hasMore = list.length == _pageSize;
    } catch (e) {
      _error = humanError(e);
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      setState(() => n.read = true);
      // otimista: marca na hora; se a API falhar, volta a "não lida"
      _api.dio.post('/notifications/${n.id}/read').then((_) {},
          onError: (Object _) {
        if (mounted) setState(() => n.read = false);
      });
    }
    final day = n.appointmentDay;
    if (day != null && mounted) Navigator.of(context).pop(day);
  }

  Future<void> _readAll() async {
    final before = [for (final n in _items) n.read];
    setState(() {
      for (final n in _items) {
        n.read = true;
      }
    });
    try {
      await _api.dio.post('/notifications/read-all');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _items.length; i++) {
          _items[i].read = before[i];
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Não consegui marcar: ${humanError(e)}'),
          backgroundColor: AppColors.error));
    }
  }

  String _dayLabel(DateTime d) {
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    final s = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (_unread > 0)
            IconButton(
              key: const Key('notifications-read-all'),
              tooltip: 'Marcar todas como lidas',
              icon: const Icon(Icons.done_all),
              onPressed: _readAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _message(Icons.cloud_off, _error!, retry: true)
              : _items.isEmpty
                  ? _message(Icons.notifications_none,
                      'Nenhuma notificação ainda.\nAqui aparecem os agendamentos feitos pelo link, confirmações, cancelamentos e lembretes.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: _buildList(),
                      ),
                    ),
    );
  }

  List<Widget> _buildList() {
    final theme = Theme.of(context);
    final hm = DateFormat('HH:mm', 'pt_BR');
    final out = <Widget>[];
    String? lastLabel;
    for (final n in _items) {
      final label = _dayLabel(n.createdAt);
      if (label != lastLabel) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: AppColors.neutral)),
        ));
        lastLabel = label;
      }
      final (icon, color) = notificationStyle(n.type);
      out.add(Material(
        color: n.read ? null : AppColors.softOf(context).withValues(alpha: 0.5),
        child: ListTile(
          key: Key('notification-${n.id}'),
          onTap: () => _open(n),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          title: Text(n.title,
              style: TextStyle(
                  fontWeight: n.read ? FontWeight.w400 : FontWeight.w700)),
          subtitle: n.body.isEmpty ? null : Text(n.body),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(hm.format(n.createdAt), style: theme.textTheme.bodySmall),
              if (!n.read) ...[
                const SizedBox(height: 6),
                Container(
                  key: Key('notification-unread-${n.id}'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: AppColors.primaryOf(context),
                      shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ));
    }
    if (_hasMore) {
      out.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: _loadingMore
              ? const CircularProgressIndicator()
              : OutlinedButton(
                  key: const Key('notifications-more'),
                  onPressed: () => _load(more: true),
                  child: const Text('Carregar mais'),
                ),
        ),
      ));
    }
    return out;
  }

  Widget _message(IconData icon, String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: AppColors.neutral),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (retry) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: const Text('Tentar de novo')),
            ],
          ]),
        ),
      );
}
