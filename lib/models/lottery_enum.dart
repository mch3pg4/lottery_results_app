enum LotteryType {
  magnum('MAGNUM', 'Magnum'),
  toto('TOTO', 'Sports Toto'),
  damacai('DAMACAI', 'Damacai'),
  cashsweep('CASHSWEEP', 'Cashsweep'),
  sabah88('SABAH88', 'Sabah 88'),
  sadakan('STC', 'Sadakan'),
  singapore('SG', 'Singapore');

  final String code;
  final String displayName;

  const LotteryType(this.code, this.displayName);

  static LotteryType fromCode(String code) {
    return values.firstWhere(
      (type) => type.code == code,
      orElse: () => LotteryType.magnum,
    );
  }
}

