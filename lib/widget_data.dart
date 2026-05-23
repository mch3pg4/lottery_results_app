class WidgetResult {
  final String name;
  final String description;
  final String result;

  WidgetResult({
    required this.name,
    required this.description,
    required this.result,
  });
}

class WidgetDataService {
  static const String keyName = 'lottery_name';
  static const String keyDescription = 'lottery_description';
  static const String keyResult = 'lottery_result';

  static Future<void> saveAndUpdate(WidgetResult value) async {
    // No-op fallback: preserve call sites without requiring the home_widget plugin.
    // The Android app widget can be reconnected later via a platform channel or
    // a dedicated widget package if needed.
    return;
  }
}
