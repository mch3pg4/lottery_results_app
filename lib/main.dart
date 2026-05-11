import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';


import 'widget_data.dart';

Future<void> main() async {
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lottery Results',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B4BFF)),
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Lottery Results'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedLottery = 0;
  int _selectedTab = 0;
  bool _isLoadingCompanies = false;
  String? _companiesError;
  List<String> _companies = const [];

  final List<_LotteryOption> _lotteryOptions = const [
    _LotteryOption(
      name: 'Lotto Max',
      subtitle: 'Evening draw',
      numbers: ['04', '11', '18', '23', '37', '44'],
      bonus: '09',
    ),
    _LotteryOption(
      name: 'Power Pick',
      subtitle: 'Midday draw',
      numbers: ['02', '10', '16', '28', '33', '41'],
      bonus: '07',
    ),
    _LotteryOption(
      name: 'Daily Lucky',
      subtitle: 'Morning draw',
      numbers: ['01', '08', '14', '22', '30', '46'],
      bonus: '12',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _syncWidget();
    fetch4DCompanies();
  }

  void _selectLottery(int index) {
    setState(() {
      _selectedLottery = index;
    });
    _syncWidget();
  }

  Future<void> _syncWidget() async {
    final selected = _lotteryOptions[_selectedLottery];
    final combinedNumbers = '${selected.numbers.join(' ')} | Bonus ${selected.bonus}';
    await WidgetDataService.saveAndUpdate(
      WidgetResult(
        name: selected.name,
        description: selected.subtitle,
        result: combinedNumbers,
      ),
    );
  }

  Future<void> fetch4DCompanies() async {
    setState(() {
      _isLoadingCompanies = true;
      _companiesError = null;
    });

    final url = Uri.parse('https://4d-results.p.rapidapi.com/get_4d_companies');
    final headers = {
      'x-rapidapi-key': dotenv.env['RAPIDAPI_KEY'] ?? '',
      'x-rapidapi-host': '4d-results.p.rapidapi.com',
      'Content-Type': 'application/json',
    };

    if ((headers['x-rapidapi-key'] ?? '').isEmpty) {
      setState(() {
        _isLoadingCompanies = false;
        _companiesError =
            'Missing RAPIDAPI_KEY. Run with --dart-define=RAPIDAPI_KEY=your_key';
      });
      return;
    }

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final companies = _extractCompanies(decoded);

        setState(() {
          _companies = companies;
          _isLoadingCompanies = false;
        });
      } else {
        setState(() {
          _isLoadingCompanies = false;
          _companiesError =
              'Request failed (${response.statusCode}): ${response.reasonPhrase ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingCompanies = false;
        _companiesError = 'Error fetching companies: $e';
      });
    }
  }

  List<String> _extractCompanies(dynamic decoded) {
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList();
    }

    if (decoded is Map<String, dynamic>) {
      for (final key in ['companies', 'data', 'results', 'result']) {
        final value = decoded[key];
        if (value is List) {
          return value.map((item) => item.toString()).toList();
        }
      }

      if (decoded.isNotEmpty) {
        return decoded.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .toList();
      }
    }

    return [decoded.toString()];
  }



  String _formatDate(DateTime date) {
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    final day = date.day.toString().padLeft(2, '0');
    return '$weekday, $day $month ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedLottery = _lotteryOptions[_selectedLottery];
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(_selectedTab == 0 ? widget.title : _tabTitle(_selectedTab)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDateBanner(today),
                  const SizedBox(height: 16),
                  _buildLotteryToggles(),
                  const SizedBox(height: 16),
                  _buildResultsCard(selectedLottery),
                  const SizedBox(height: 16),
                  _buildInfoCards(),
                  const SizedBox(height: 16),
                  _buildCompaniesCard(),
                ],
              ),
            ),
            _buildPlaceholderTab(
              icon: Icons.history_rounded,
              title: 'Recent draws',
              message:
                  'Past results, saved favorites, and draw history will appear here.',
            ),
            _buildPlaceholderTab(
              icon: Icons.settings_rounded,
              title: 'More options',
              message:
                  'Settings, notifications, and app preferences can live here later.',
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_rounded),
            label: 'Results',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  String _tabTitle(int index) {
    switch (index) {
      case 1:
        return 'Hello';
      case 2:
        return 'More';
      default:
        return widget.title;
    }
  }

  Widget _buildPlaceholderTab({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBanner(DateTime today) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primaryContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.calendar_today_rounded, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Today',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(today),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Day',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(today).split(',').first,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLotteryToggles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose lottery',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ToggleButtons(
          isSelected: List<bool>.generate(
            _lotteryOptions.length,
            (index) => index == _selectedLottery,
          ),
          onPressed: _selectLottery,
          borderRadius: BorderRadius.circular(16),
          selectedColor: Colors.white,
          fillColor: Theme.of(context).colorScheme.primary,
          color: Theme.of(context).colorScheme.primary,
          constraints: const BoxConstraints(minHeight: 52, minWidth: 104),
          renderBorder: false,
          children: _lotteryOptions
              .map(
                (option) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    option.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildResultsCard(_LotteryOption selectedLottery) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedLottery.name,
                    key: const Key('selected-lottery-name'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedLottery.subtitle,
                    key: const Key('selected-lottery-subtitle'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Placeholder results',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final number in selectedLottery.numbers)
                _buildNumberBall(number, filled: true),
              _buildNumberBall(selectedLottery.bonus, label: 'Bonus'),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F7FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Winning numbers are placeholders for now. Replace them with live data when your API is ready.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberBall(String value, {bool filled = false, String? label}) {
    final color = Theme.of(context).colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.white,
            border: Border.all(color: color.withValues(alpha: 0.25), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoCards() {
    return Row(
      children: [
        Expanded(
          child: _InfoCard(
            title: 'Jackpot',
            value: r'$1.2M',
            icon: Icons.payments_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InfoCard(
            title: 'Next draw',
            value: 'Tonight 8:00 PM',
            icon: Icons.schedule_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildCompaniesCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '4D Companies',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                onPressed: _isLoadingCompanies ? null : fetch4DCompanies,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
              ),
            ],
          ),
          if (_isLoadingCompanies)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_companiesError != null)
            Text(
              _companiesError!,
              style: const TextStyle(color: Colors.redAccent),
            )
          else if (_companies.isEmpty)
            const Text('No company data returned from API yet.')
          else
            ..._companies.map(
              (company) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('- $company'),
              ),
            ),
        ],
      ),
    );
  }
}

class _LotteryOption {
  const _LotteryOption({
    required this.name,
    required this.subtitle,
    required this.numbers,
    required this.bonus,
  });

  final String name;
  final String subtitle;
  final List<String> numbers;
  final String bonus;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
