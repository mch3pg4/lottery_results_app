import 'package:home_widget/home_widget.dart';

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
  static const String _androidWidgetProviderName = 'ResultsWidget';

  static const String keyName = 'lottery_name';
  static const String keyDescription = 'lottery_description';
  static const String keyResult = 'lottery_result';

  static Future<void> saveAndUpdate(WidgetResult value) async {
    await HomeWidget.saveWidgetData<String>(keyName, value.name);
    await HomeWidget.saveWidgetData<String>(keyDescription, value.description);
    await HomeWidget.saveWidgetData<String>(keyResult, value.result);

    await HomeWidget.updateWidget(
      name: _androidWidgetProviderName,
      androidName: _androidWidgetProviderName,
    );
  }
}
