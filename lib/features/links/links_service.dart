import '../../core/api/api_client.dart';

/// Vínculo estabelecimento ↔ profissional (API 0026, `/v1/links`).
///
/// [counterpart] é o outro lado: para o estabelecimento, o profissional
/// (nome, código P-); para o profissional, o estabelecimento (nome, cidade).
class ProfessionalLink {
  final String id;
  final String status; // pending | active
  final String requestedBy; // professional | aggregator
  final bool awaitingMe;
  final bool showOnLink;
  final int position;
  final String name;
  final String? businessName;
  final String? proCode;
  final String? city;
  final String? logoUrl;

  const ProfessionalLink({
    required this.id,
    required this.status,
    required this.requestedBy,
    required this.awaitingMe,
    required this.showOnLink,
    required this.position,
    required this.name,
    this.businessName,
    this.proCode,
    this.city,
    this.logoUrl,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  factory ProfessionalLink.fromJson(Map<String, dynamic> j) {
    final c = (j['counterpart'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ProfessionalLink(
      id: j['id'] as String,
      status: j['status'] as String? ?? 'pending',
      requestedBy: j['requested_by'] as String? ?? 'professional',
      awaitingMe: j['awaiting_me'] == true,
      showOnLink: j['show_on_link'] != false,
      position: (j['position'] as num?)?.toInt() ?? 0,
      name: c['name'] as String? ?? '',
      businessName: c['business_name'] as String?,
      proCode: c['pro_code'] as String?,
      city: c['city'] as String?,
      logoUrl: c['logo_url'] as String?,
    );
  }

  ProfessionalLink copyWith({bool? showOnLink, int? position}) =>
      ProfessionalLink(
        id: id,
        status: status,
        requestedBy: requestedBy,
        awaitingMe: awaitingMe,
        showOnLink: showOnLink ?? this.showOnLink,
        position: position ?? this.position,
        name: name,
        businessName: businessName,
        proCode: proCode,
        city: city,
        logoUrl: logoUrl,
      );
}

/// Chamadas da API de vínculos. Erros sobem como DioException (a tela usa
/// `humanError` para mostrar a mensagem em PT-BR que a API manda).
class LinksService {
  final ApiClient _api;
  LinksService([ApiClient? api]) : _api = api ?? ApiClient();

  Future<List<ProfessionalLink>> list({required bool asAggregator}) async {
    final r = await _api.dio.get('/links', queryParameters: {
      'as': asAggregator ? 'aggregator' : 'professional',
    });
    return [
      for (final j in (r.data['links'] as List))
        ProfessionalLink.fromJson((j as Map).cast<String, dynamic>()),
    ];
  }

  /// Código E- (profissional pede para entrar) ou P- (estabelecimento convida).
  Future<void> create(String code) =>
      _api.dio.post('/links', data: {'code': code.trim()});

  Future<void> accept(String id) => _api.dio.post('/links/$id/accept');
  Future<void> reject(String id) => _api.dio.post('/links/$id/reject');
  Future<void> cancel(String id) => _api.dio.post('/links/$id/cancel');

  /// Encerra um vínculo ativo. Devolve quantos agendamentos futuros vindos
  /// pelo estabelecimento continuam na agenda do profissional (D2).
  Future<int> end(String id) async {
    final r = await _api.dio.post('/links/$id/end');
    return (r.data is Map ? (r.data['future_appointments'] as num?) : null)
            ?.toInt() ??
        0;
  }

  Future<void> update(String id, {bool? showOnLink, int? position}) =>
      _api.dio.patch('/links/$id', data: {
        if (showOnLink != null) 'show_on_link': showOnLink,
        if (position != null) 'position': position,
      });
}
