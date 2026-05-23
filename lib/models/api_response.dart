class ApiResponse<T> {
  final String? status;
  final T? data;
  final String? message;
  final bool? success;

  ApiResponse({
    this.status,
    this.data,
    this.message,
    this.success,
  });

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic) fromJsonT) {
    return ApiResponse(
      status: json['status'],
      data: json['data'] != null ? fromJsonT(json['data']) : null,
      message: json['message'],
      success: json['success'],
    );
  }
}

class LotteryResultResponse {
  final String? date;
  final String? lotteryType;
  final List<String>? numbers;
  final String? bonus;
  final dynamic result;

  LotteryResultResponse({
    this.date,
    this.lotteryType,
    this.numbers,
    this.bonus,
    this.result,
  });

  factory LotteryResultResponse.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      // If numbers is a string, split it
      List<String> numbersList = [];
      if (json['numbers'] is String) {
        numbersList = (json['numbers'] as String).split(' ').where((n) => n.isNotEmpty).toList();
      } else if (json['numbers'] is List) {
        numbersList = List<String>.from(json['numbers']);
      }

      return LotteryResultResponse(
        date: json['date'],
        lotteryType: json['lotteryType'] ?? json['lottery'],
        numbers: numbersList,
        bonus: json['bonus'],
        result: json['result'],
      );
    }
    return LotteryResultResponse();
  }
}

