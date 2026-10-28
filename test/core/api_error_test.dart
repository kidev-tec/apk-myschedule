import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_agenda/core/api/api_error.dart';

void main() {
  final req = RequestOptions(path: '/x');

  DioException resposta(int status, dynamic data) => DioException(
        requestOptions: req,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: req, statusCode: status, data: data),
      );

  test('usa o campo error da API (mensagem humana em PT-BR)', () {
    expect(humanError(resposta(400, {'error': 'Este horário já passou'})),
        'Este horário já passou');
  });

  test('resposta sem error → mensagem genérica, nunca a exceção crua', () {
    final msg = humanError(resposta(500, '<html>'));
    expect(msg, 'Algo deu errado no servidor. Tenta de novo.');
    expect(msg, isNot(contains('DioException')));
  });

  test('sem conexão → avisa que não conectou', () {
    final e = DioException(
        requestOptions: req, type: DioExceptionType.connectionError);
    expect(humanError(e), 'Sem conexão com o servidor. Confere a internet.');
  });

  test('timeout → avisa que não conectou', () {
    final e = DioException(
        requestOptions: req, type: DioExceptionType.receiveTimeout);
    expect(humanError(e), 'Sem conexão com o servidor. Confere a internet.');
  });

  test('erro que não é da rede → mensagem genérica', () {
    expect(humanError(StateError('x')), 'Algo deu errado. Tenta de novo.');
  });
}
