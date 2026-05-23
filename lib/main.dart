import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;

import 'widget_data.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';
import 'models/lottery_enum.dart';
import 'models/lottery_result.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  DateTime _selectedDate = DateTime.now();
  bool _isLoadingResults = false;
  String? _resultsError;
  LotteryResult? _lotteryResult;

  final List<LotteryType> _lotteryTypes = LotteryType.values;

  wvwin.WebviewController? _headlessWebViewController;
  StreamSubscription<wvwin.LoadingState>? _webViewLoadingSub;
  StreamSubscription<dynamic>? _webMessageSub;
  bool _isWebViewReady = false;
  bool _hasWebViewError = false;

  @override
  void initState() {
    super.initState();
    _syncWidget();
    _initHeadlessWebView();
  }

  @override
  void dispose() {
    _webViewLoadingSub?.cancel();
    _webMessageSub?.cancel();
    _headlessWebViewController?.dispose();
    super.dispose();
  }

  bool get _isWindowsDesktop => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _initHeadlessWebView() async {
    if (!_isWindowsDesktop) {
      setState(() {
        _hasWebViewError = true;
        _resultsError = 'This build uses an embedded Windows WebView for fetching results. Please run on Windows desktop.';
      });
      return;
    }

    try {
      final version = await wvwin.WebviewController.getWebViewVersion();
      if (version == null) {
        setState(() {
          _hasWebViewError = true;
          _resultsError = 'WebView2 Runtime is not installed on this PC. Install Microsoft Edge WebView2 Runtime and restart the app.';
        });
        return;
      }

      final controller = wvwin.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.transparent);
      await controller.setPopupWindowPolicy(wvwin.WebviewPopupWindowPolicy.deny);

      _webViewLoadingSub = controller.loadingState.listen((state) {
        if (!mounted) return;
        if (state == wvwin.LoadingState.navigationCompleted) {
          setState(() {
            _isWebViewReady = true;
            _hasWebViewError = false;
          });
          if (_isLoadingResults) {
            _executeFetchInWebView();
          }
        }
      });

      _webMessageSub = controller.webMessage.listen((message) {
        if (!mounted) return;
        _handleWebMessage(message);
      });

      _headlessWebViewController = controller;
      await controller.loadUrl('https://4dyes3.com/en/past-result');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasWebViewError = true;
        _resultsError = 'WebView initialization failed: $e';
        _isLoadingResults = false;
      });
    }
  }


  void _selectLottery(int index) {
    setState(() {
      _selectedLottery = index;
    });
    _fetchLotteryResults();
  }

  Future<void> _fetchLotteryResults() async {
    setState(() {
      _isLoadingResults = true;
      _resultsError = null;
    });

    if (_hasWebViewError) {
      setState(() {
        _isLoadingResults = false;
        _resultsError = _resultsError ?? 'Background engine failed to load. Please restart app.';
      });
      return;
    }

    if (!_isWebViewReady || _headlessWebViewController == null) {
      // Will be triggered automatically when page finishes loading
      return;
    }

    _executeFetchInWebView();
  }

  void _executeFetchInWebView() {
    final dateString = _selectedDate.toString().split(' ')[0];
    final js = '''
      (function() {
        fetch('https://4dyes3.com/getLiveResult.php?date=$dateString', { credentials: 'include' })
        .then(response => {
           if (!response.ok) throw new Error('HTTP ' + response.status);
           return response.text();
        })
        .then(data => window.chrome.webview.postMessage(JSON.stringify({ kind: 'result', payload: data })))
        .catch(e => window.chrome.webview.postMessage(JSON.stringify({ kind: 'error', payload: e.toString() })));
      })();
    ''';
    _headlessWebViewController?.executeScript(js);
  }

  void _handleWebMessage(dynamic message) {
    final lotteryType = _lotteryTypes[_selectedLottery];

    if (message is Map && message['kind'] == 'error') {
      setState(() {
        _resultsError = 'API Error: ${message['payload']}';
        _isLoadingResults = false;
      });
      return;
    }

    if (message is! Map || message['kind'] != 'result') {
      setState(() {
        _resultsError = 'Unexpected WebView message received.';
        _isLoadingResults = false;
      });
      return;
    }

    try {
      final decoded = jsonDecode(message['payload'] as String);
      final result = _extractLotteryResultFromNewApi(decoded, lotteryType);
      setState(() {
        _lotteryResult = result;
        _isLoadingResults = false;
        _resultsError = null;
      });
      _syncWidget();
    } catch (e) {
      setState(() {
        _resultsError = 'Failed to parse results.';
        _isLoadingResults = false;
      });
    }
  }

  LotteryResult _extractLotteryResultFromNewApi(dynamic decoded, LotteryType lotteryType) {
    try {
      if (decoded is Map<String, dynamic>) {
        // Check if it's wrapped in ApiResponse structure
        if (decoded.containsKey('data') && decoded['data'] is Map) {
          final data = decoded['data'] as Map<String, dynamic>;
          return _parseLotteryData(data, lotteryType);
        }

        // Direct data format
        return _parseLotteryData(decoded, lotteryType);
      }

      if (decoded is List && decoded.isNotEmpty) {
        if (decoded.first is Map<String, dynamic>) {
          return _parseLotteryData(decoded.first, lotteryType);
        }
      }
    } catch (e) {
      // Continue to fallback
    }

    // Return empty result
    return LotteryResult(
      name: lotteryType.displayName,
      date: _selectedDate.toString(),
      numbers: [],
    );
  }

  LotteryResult _parseLotteryData(Map<String, dynamic> data, LotteryType lotteryType) {
    try {
      // Extract numbers
      List<String> numbers = [];
      String? bonus;

      // Try different number field names
      if (data.containsKey('numbers')) {
        final nums = data['numbers'];
        if (nums is String) {
          numbers = nums.split(' ').where((n) => n.isNotEmpty).toList();
        } else if (nums is List) {
          numbers = List<String>.from(nums);
        }
      }

      if (data.containsKey('result')) {
        final result = data['result'];
        if (result is String) {
          numbers = result.split(' ').where((n) => n.isNotEmpty).toList();
        } else if (result is List) {
          numbers = List<String>.from(result);
        }
      }

      if (data.containsKey('bonus')) {
        bonus = data['bonus'].toString();
      }

      return LotteryResult(
        name: data['lotteryType']?.toString() ?? lotteryType.displayName,
        date: data['date']?.toString() ?? _selectedDate.toString(),
        numbers: numbers,
        bonus: bonus,
      );
    } catch (e) {
      return LotteryResult(
        name: lotteryType.displayName,
        date: _selectedDate.toString(),
        numbers: [],
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchLotteryResults();
    }
  }

  Future<void> _syncWidget() async {
    final selected = _lotteryTypes[_selectedLottery];
    final numberStr = _lotteryResult?.numbers.join(' ') ?? '';
    final bonusStr = _lotteryResult?.bonus != null ? '| Bonus ${_lotteryResult!.bonus}' : '';
    final combinedNumbers = '$numberStr $bonusStr';
    await WidgetDataService.saveAndUpdate(
      WidgetResult(
        name: selected.displayName,
        description: _selectedDate.toString().split(' ')[0],
        result: combinedNumbers.trim(),
      ),
    );
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
    final selectedLottery = _lotteryTypes[_selectedLottery];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(_selectedTab == 0 ? widget.title : _tabTitle(_selectedTab)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(
              index: _selectedTab,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDateBanner(),
                      const SizedBox(height: 16),
                      _buildLotteryToggles(),
                      const SizedBox(height: 16),
                      _buildResultsCard(selectedLottery),
                      const SizedBox(height: 16),
                      _buildInfoCards(),
                    ],
                  ),
                ),
                const HistoryPage(),
                const SettingsPage(),
              ],
            ),
            if (_isWindowsDesktop && _headlessWebViewController != null && _headlessWebViewController!.value.isInitialized)
              Positioned(
                left: -1000,
                top: -1000,
                width: 1,
                height: 1,
                child: wvwin.Webview(
                  _headlessWebViewController!,
                  width: 1,
                  height: 1,
                  filterQuality: FilterQuality.none,
                ),
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
            label: 'Settings',
          ),
        ],
      ),
    );
  }
  String _tabTitle(int index) {
    switch (index) {
      case 1:
        return 'History';
      case 2:
        return 'More';
      default:
        return widget.title;
    }
  }  Widget _buildDateBanner() {
    return GestureDetector(
      onTap: _selectDate,
      child: Container(
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
                  Text(
                    _selectedDate.difference(DateTime.now()).inDays == 0 ? 'Today' : 'Selected Date',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_selectedDate),
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
                  _formatDate(_selectedDate).split(',').first,
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List<Widget>.generate(
              _lotteryTypes.length,
              (index) {
                final isSelected = index == _selectedLottery;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    onSelected: (_) => _selectLottery(index),
                    label: Text(_lotteryTypes[index].displayName),
                    backgroundColor: Colors.white,
                    selectedColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsCard(LotteryType selectedLottery) {
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
                    selectedLottery.displayName,
                    key: const Key('selected-lottery-name'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(_selectedDate),
                    key: const Key('selected-lottery-subtitle'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        ),
                  ),
                ],
              ),
              if (!_isLoadingResults)
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
                    _lotteryResult?.numbers.isNotEmpty ?? false ? 'Results' : 'No data',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoadingResults)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_resultsError != null)
            Text(
              _resultsError!,
              style: const TextStyle(color: Colors.redAccent),
            )
          else if (_lotteryResult?.numbers.isEmpty ?? true)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No results available for this date',
                  style: TextStyle(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final number in _lotteryResult!.numbers)
                      _buildNumberBall(number, filled: true),
                    if (_lotteryResult?.bonus != null)
                      _buildNumberBall(_lotteryResult!.bonus!, label: 'Bonus'),
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
                      Icon(Icons.check_circle_outline_rounded,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Winning numbers fetched from API for selected date and lottery type.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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


