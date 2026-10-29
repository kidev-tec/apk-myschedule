import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:minha_agenda/core/cep/cep_service.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://viacep.com.br/ws'));
    adapter = DioAdapter(dio: dio);
  });

  test('CEP encontrado → rua, bairro, cidade e UF', () async {
    adapter.onGet(
        '/17012000/json/',
        (s) => s.reply(200, {
              'cep': '17012-000',
              'logradouro': 'Rua Batista de Carvalho',
              'bairro': 'Centro',
              'localidade': 'Bauru',
              'uf': 'SP',
            }));
    final r = await CepService(dio: dio).lookup('17012-000');
    expect(r, isNotNull);
    expect(r!.street, 'Rua Batista de Carvalho');
    expect(r.district, 'Centro');
    expect(r.city, 'Bauru');
    expect(r.state, 'SP');
  });

  test('CEP inexistente (ViaCEP responde erro: true) → null', () async {
    adapter.onGet('/99999999/json/', (s) => s.reply(200, {'erro': true}));
    expect(await CepService(dio: dio).lookup('99999-999'), isNull);
  });

  test('CEP com menos de 8 dígitos → null sem chamar a rede', () async {
    expect(await CepService(dio: dio).lookup('1701'), isNull);
  });

  test('falha de rede → lança CepException com mensagem humana', () async {
    adapter.onGet(
        '/17012000/json/',
        (s) => s.throws(
            0,
            DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.connectionError)));
    await expectLater(
        CepService(dio: dio).lookup('17012000'),
        throwsA(isA<CepException>()
            .having((e) => e.message, 'message', contains('CEP'))));
  });
}
