import 'package:dio/dio.dart';

/// Endereço devolvido pela busca de CEP.
class CepAddress {
  final String street;
  final String district;
  final String city;
  final String state;
  const CepAddress({
    required this.street,
    required this.district,
    required this.city,
    required this.state,
  });
}

class CepException implements Exception {
  final String message;
  const CepException(this.message);
  @override
  String toString() => message;
}

/// Busca de CEP no ViaCEP (gratuito, sem chave). Chamada direta do app —
/// não passa pela API do AGENVA nem leva o token do usuário.
class CepService {
  final Dio _dio;
  final Future<CepAddress?> Function(String cep)? _override;

  /// [dio]: injetável em teste. [lookupOverride]: substitui a busca inteira.
  CepService(
      {Dio? dio, Future<CepAddress?> Function(String cep)? lookupOverride})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://viacep.com.br/ws',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _override = lookupOverride;

  /// null = CEP incompleto ou inexistente. Falha de rede → [CepException].
  Future<CepAddress?> lookup(String raw) async {
    final cep = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return null;
    if (_override != null) return _override(cep);
    try {
      final r = await _dio.get('/$cep/json/');
      final j = r.data;
      if (j is! Map || j['erro'] != null) return null;
      return CepAddress(
        street: (j['logradouro'] ?? '') as String,
        district: (j['bairro'] ?? '') as String,
        city: (j['localidade'] ?? '') as String,
        state: (j['uf'] ?? '') as String,
      );
    } on DioException {
      throw const CepException(
          'Não foi possível buscar o CEP agora. Preencha o endereço manualmente.');
    }
  }
}
