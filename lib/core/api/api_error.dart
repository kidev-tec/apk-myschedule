import 'package:dio/dio.dart';

/// Mensagem de erro pra mostrar ao usuário (leigo), em PT-BR.
///
/// Usa o `error` que a API devolve no body; sem ele, uma mensagem genérica.
/// Nunca expõe a exceção crua (DioException, status code, URL).
String humanError(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    if (e.response == null) {
      return 'Sem conexão com o servidor. Verifique a internet.';
    }
    return 'Algo deu errado no servidor. Tente novamente.';
  }
  return 'Algo deu errado. Tente novamente.';
}
