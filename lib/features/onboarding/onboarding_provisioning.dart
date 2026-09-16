import 'package:dio/dio.dart';

/// Garante que user+business existem no Postgres antes de o onboarding
/// escrever perfil/serviços/horários.
///
/// O sync no login é fire-and-forget com catch silencioso — se falhou
/// (crash "ref after disposed" no A15), /me responde 404 e TODO o
/// onboarding falha. Aqui: tenta PATCH /me; em 404, POST /auth/sync
/// (idempotente) e refaz o PATCH.
///
/// Lança DioException se qualquer passo falhar de verdade (não-404 ou
/// sync que não resolve o 404).
Future<void> ensureProvisioned(
  Dio dio, {
  required String segmentId,
}) async {
  try {
    await dio.patch('/me', data: {'business_type': segmentId});
    return;
  } on DioException catch (e) {
    if (e.response?.statusCode != 404) rethrow;
  }

  await dio.post('/auth/sync', data: {'segment': segmentId});
  // Refaz o PATCH que falhou com 404 — agora o user existe.
  await dio.patch('/me', data: {'business_type': segmentId});
}
