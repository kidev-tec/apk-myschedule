package com.minhaagenda.minha_agenda_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * Canal "Agendamentos" (id igual ao enviado pela API no push). Importância
     * alta = aparece no topo e usa o som/vibração PADRÃO do aparelho: o modo
     * do celular decide (normal toca, vibrar vibra, silencioso fica quieto) e
     * o usuário pode ajustar o canal nas configurações do Android.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "agendamentos",
            "Agendamentos",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Novos agendamentos pelo link e lembretes"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
