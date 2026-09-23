import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'onboarding_store.dart';

/// Decide se o usuário pula o assistente de onboarding.
///
/// Fonte de verdade = SERVIDOR (feedback Ezequias 22/09: desinstalar o app
/// apaga a flag local e forçava o assistente de novo com conta configurada).
/// `GET /me` devolve `onboarding_complete` (tem horários + serviço ativo).
///
/// Fallback: se a rede falhar (ou API velha sem o campo), usa a flag local
/// — 1ª instalação offline cai no assistente (honesto: sem consultar, não
/// há como saber).
Future<bool> resolveOnboardingComplete(ApiClient api) async {
  try {
    final me = await api.dio.get('/me');
    final server = me.data['onboarding_complete'] as bool?;
    if (server != null) {
      if (server) await OnboardingStore.markComplete();
      return server;
    }
  } on DioException catch (e) {
    // 404 = conta autenticada que o Postgres não conhece (sync falhou,
    // firebase órfão recreado, etc). NÃO cai na flag local: ela é global
    // por aparelho — se OUTRA conta já completou onboarding aqui, a flag
    // é true e o usuário novo pulava o assistente sem nunca ser
    // provisionado (bug visto com mmmarckos em 22/09). Onboarding é o
    // único caminho que provisiona (ensureProvisioned → /auth/sync).
    if (e.response?.statusCode == 404) {
      await OnboardingStore.reset();
      return false;
    }
    debugPrint('[onboarding] fallback na flag local: ${e.type}');
  } catch (e) {
    debugPrint('[onboarding] fallback na flag local: $e');
  }
  return OnboardingStore.isComplete();
}
