package com.mch.lottery_results.lottery_results;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.widget.RemoteViews;

/**
 * Implementation of App Widget functionality for displaying lottery results.
 * Shows today's winning numbers, bonus, and next draw timing.
 */
public class ResultsWidget extends AppWidgetProvider {

    static void updateAppWidget(Context context, AppWidgetManager appWidgetManager,
                                int appWidgetId) {

        // Default lottery data (in a real app, this would come from a database or API)
        String lotteryName = context.getString(R.string.lottery_name);
        String lotteryDraw = context.getString(R.string.lottery_draw);
        String lotteryNumbers = context.getString(R.string.lottery_numbers);
        String lotteryBonus = context.getString(R.string.lottery_bonus);
        String nextDraw = context.getString(R.string.next_draw);

        // Construct the RemoteViews object
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.results_widget);

        // Set the text views with lottery data
        views.setTextViewText(R.id.widget_lottery_name, lotteryName);
        views.setTextViewText(R.id.widget_lottery_draw, lotteryDraw);
        views.setTextViewText(R.id.widget_lottery_numbers, lotteryNumbers);
        views.setTextViewText(R.id.widget_lottery_bonus, lotteryBonus);
        views.setTextViewText(R.id.widget_next_draw, nextDraw);

        // Instruct the widget manager to update the widget
        appWidgetManager.updateAppWidget(appWidgetId, views);
    }

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        // There may be multiple widgets active, so update all of them
        for (int appWidgetId : appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId);
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

