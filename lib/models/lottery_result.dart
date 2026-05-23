class LotteryResult {
  final String name;
  final String date;
  final List<String> numbers;
  final String? bonus;
  final LotteryMachine? machine;

  LotteryResult({
    required this.name,
    required this.date,
    required this.numbers,
    this.bonus,
    this.machine,
  });

  factory LotteryResult.fromJson(Map<String, dynamic> json) {
    return LotteryResult(
      name: json['name'] ?? '',
      date: json['date'] ?? '',
      numbers: List<String>.from(json['numbers'] ?? []),
      bonus: json['bonus'],
      machine: json['machine'] != null ? LotteryMachine.fromJson(json['machine']) : null,
    );
  }
}

class LotteryMachine {
  final String? id;
  final String? name;

  LotteryMachine({this.id, this.name});

  factory LotteryMachine.fromJson(Map<String, dynamic> json) {
    return LotteryMachine(
      id: json['id'],
      name: json['name'],
    );
  }
}

