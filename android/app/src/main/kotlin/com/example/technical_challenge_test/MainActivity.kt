package com.example.technical_challenge_test

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.technical_challenge_test/widget"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val question = call.argument<String>("question") ?: ""
                    val topic = call.argument<String>("topic") ?: ""
                    val difficulty = call.argument<String>("difficulty") ?: ""

                    val prefs = context.getSharedPreferences("ChallengeWidgetData", Context.MODE_PRIVATE)
                    prefs.edit().apply {
                        putString("widget_question", question)
                        putString("widget_topic", topic)
                        putString("widget_difficulty", difficulty)
                        apply()
                    }

                    ChallengeWidgetProvider.updateAllWidgets(context)
                    result.success(true)
                }
                "getInitialTarget" -> {
                    val target = intent?.getStringExtra("target_screen")
                    intent?.removeExtra("target_screen")
                    result.success(target)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val target = intent.getStringExtra("target_screen")
        if (target != null) {
            intent.removeExtra("target_screen")
            methodChannel?.invokeMethod("navigateTo", target)
        }
    }
}
