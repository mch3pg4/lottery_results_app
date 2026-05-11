package com.mch.lottery_results.lottery_results;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;
import android.app.PendingIntent;
import android.widget.RemoteViews;

// Note: the home_widget plugin registers a plugin class but does not expose
// a public static getData(Context) helper. Instead we read the SharedPreferences
// entries that the plugin writes. Different plugin versions may use different
// preference file names; we try several common candidates below.

/**
 * Implementation of App Widget functionality for displaying lottery results.
 * Shows today's winning numbers, bonus, and next draw timing.
 */
public class ResultsWidget extends AppWidgetProvider {

    static void updateAppWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {

        // Try reading saved widget data from SharedPreferences. The Dart
        // `home_widget` plugin persists values on Android; the file name can
        // vary between versions, so probe several candidates and finally the
        // default shared prefs.
        SharedPreferences widgetData = null;
        String[] candidates = new String[] {
                "home_widget",
                "HomeWidget",
                "home_widget_prefs",
                context.getPackageName() + "_home_widget",
        };

        for (String name : candidates) {
            try {
                SharedPreferences prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE);
                if (prefs != null && prefs.contains("lottery_name")) {
                    widgetData = prefs;
                    break;
                }
            } catch (Exception ignored) {
            }
        }

        if (widgetData == null) {
            try {
                SharedPreferences prefs = PreferenceManager.getDefaultSharedPreferences(context);
                if (prefs != null && prefs.contains("lottery_name")) {
                    widgetData = prefs;
                }
            } catch (Exception ignored) {
            }
        }

        String lotteryName = context.getString(R.string.lottery_name);
        String lotteryDescription = context.getString(R.string.lottery_description);
        String lotteryResult = context.getString(R.string.lottery_result);
        String nextDraw = context.getString(R.string.next_draw);

        if (widgetData != null) {
            lotteryName = widgetData.getString("lottery_name", lotteryName);
            lotteryDescription = widgetData.getString("lottery_description", lotteryDescription);
            lotteryResult = widgetData.getString("lottery_result", lotteryResult);
        }

        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.results_widget);
        views.setTextViewText(R.id.widget_lottery_name, lotteryName);
        views.setTextViewText(R.id.widget_lottery_description, lotteryDescription);
        views.setTextViewText(R.id.widget_lottery_result, lotteryResult);
        views.setTextViewText(R.id.widget_next_draw, nextDraw);

        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent != null) {
            PendingIntent pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent);
        }

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (AppWidgetManager.ACTION_APPWIDGET_UPDATE.equals(intent.getAction())) {
            AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(context);
            ComponentName thisWidget = new ComponentName(context, ResultsWidget.class);
            int[] appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget);
            onUpdate(context, appWidgetManager, appWidgetIds);
        }
    }

    @Override
    public void onEnabled(Context context) {
        // Enter relevant functionality for when the first widget is created
    }

    @Override
    public void onDisabled(Context context) {
        // Enter relevant functionality for when the last widget is disabled
    }
}

