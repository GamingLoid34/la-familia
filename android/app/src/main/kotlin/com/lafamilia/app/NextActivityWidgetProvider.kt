package com.lafamilia.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Hemskärms-widget (ROADMAP Etapp 13): nästa aktivitet + rutinstatus
 * i dagens färg. Datat skrivs från Flutter via home_widget-paketet
 * (WidgetService) varje gång familjedatat ändras.
 */
class NextActivityWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val header = prefs.getString("header", "LA FAMILIA") ?: "LA FAMILIA"
        val title = prefs.getString("title", "Öppna appen för att synka") ?: ""
        val time = prefs.getString("time", "") ?: ""
        val routine = prefs.getString("routine", "") ?: ""
        val accentHex = prefs.getString("accentColor", "#4E9D68") ?: "#4E9D68"
        val accent = try {
            Color.parseColor(accentHex)
        } catch (_: IllegalArgumentException) {
            Color.parseColor("#4E9D68")
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_activity)
            views.setTextViewText(R.id.widget_header, header)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_time, time)
            views.setTextViewText(R.id.widget_routine, routine)
            views.setInt(R.id.widget_accent, "setBackgroundColor", accent)
            views.setTextColor(R.id.widget_header, accent)
            views.setTextColor(R.id.widget_time, accent)
            views.setViewVisibility(
                R.id.widget_time,
                if (time.isEmpty()) View.GONE else View.VISIBLE
            )
            views.setViewVisibility(
                R.id.widget_routine,
                if (routine.isEmpty()) View.GONE else View.VISIBLE
            )

            // Tryck på widgeten → öppna appen.
            val launchIntent =
                context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pending = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
