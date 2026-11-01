import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/push/push_events.dart';

/// Sino da central de notificações (topo da agenda) com bolinha de não
/// lidas. Recarrega a contagem ao abrir, quando chega push e quando o app
/// volta pro primeiro plano. [onOpen] abre a tela de notificações.
class NotificationBell extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function() onOpen;

  const NotificationBell({super.key, required this.api, required this.onOpen});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushEvents.instance.notificationsChanged.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushEvents.instance.notificationsChanged.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await widget.api.dio.get('/notifications/unread-count');
      final n = (r.data is Map ? r.data['unread'] : null) as int? ?? 0;
      if (mounted) setState(() => _unread = n);
    } catch (e) {
      debugPrint('[notificações] contagem indisponível: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: _unread == 0
          ? 'Notificações'
          : 'Notificações ($_unread não lida${_unread > 1 ? 's' : ''})',
      onPressed: () async {
        await widget.onOpen();
        _refresh(); // voltou da lista: atualiza a bolinha
      },
      icon: Badge(
        key: const Key('notification-badge'),
        isLabelVisible: _unread > 0,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child:
            Icon(_unread > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}
