package com.example.technical_challenge_test

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

class ChallengeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, ChallengeWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            for (appWidgetId in appWidgetIds) {
                updateWidget(context, appWidgetManager, appWidgetId)
            }
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences("ChallengeWidgetData", Context.MODE_PRIVATE)
            val question = prefs.getString("widget_question", "No question available today.")
            val topic = prefs.getString("widget_topic", "Technical Challenge")
            val difficulty = prefs.getString("widget_difficulty", "Easy")

            val views = RemoteViews(context.packageName, R.layout.challenge_widget_layout)

            views.setTextViewText(R.id.widget_topic, "🏷️ $topic")
            views.setTextViewText(R.id.widget_difficulty, difficulty)
            views.setTextViewText(R.id.widget_question, question)

            // Dynamic difficulty text color
            val difficultyColor = when (difficulty?.lowercase()) {
                "easy" -> Color.parseColor("#A6E3A1") // Vibrant Pastel Green
                "medium" -> Color.parseColor("#FAB387") // Vibrant Amber
                "hard" -> Color.parseColor("#F38BA8") // Vibrant Coral Red
                else -> Color.parseColor("#89B4FA")
            }
            views.setTextColor(R.id.widget_difficulty, difficultyColor)

            // Launch MainActivity with target_screen extra pointing directly to "challenge" tab
            val intent = Intent(context, MainActivity::class.java).apply {
                putExtra("target_screen", "challenge")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
