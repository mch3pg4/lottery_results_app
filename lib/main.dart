import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widget_data.dart';
import 'pages/history_page.dart';
import 'pages/login_page.dart';
import 'pages/settings_page.dart';
import 'models/lottery_enum.dart';
import 'models/lottery_result.dart';
import 'theme/app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await AppThemeController.instance.init();
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  runApp(const MyApp());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginPage();
        }

        return const MyHomePage(title: 'Lottery Results');
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.instance.themeMode,
      builder: (context, mode, _) {
        final lightScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B4BFF),
          brightness: Brightness.light,
        );
        final darkScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B4BFF),
          brightness: Brightness.dark,
        );
        return MaterialApp(
          title: 'Lottery Results',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorScheme: lightScheme,
            scaffoldBackgroundColor: const Color(0xFFF4F6FB),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            scaffoldBackgroundColor: darkScheme.surface,
            useMaterial3: true,
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

class _ResultsCacheKey {
  final LotteryType type;
  final int regionTabIndex;
  final DateTime date; // date-only

  const _ResultsCacheKey({
    required this.type,
    required this.regionTabIndex,
    required this.date,
  });

  @override
  bool operator ==(Object other) {
    return other is _ResultsCacheKey &&
        other.type == type &&
        other.regionTabIndex == regionTabIndex &&
        other.date.year == date.year &&
        other.date.month == date.month &&
        other.date.day == date.day;
  }

  @override
  int get hashCode =>
      Object.hash(type, regionTabIndex, date.year, date.month, date.day);
}

class _ResultsCacheEntry {
  final DateTime cachedAt;
  final LotteryResult result;

  final String? moonDrawInfo;
  final List<String> moonSpecialList;
  final List<String> moonConsolationList;

  final String? damacaiDrawNo;
  final String? damacaiDrawVenue;
  final List<String> damacaiStarterList;
  final List<String> damacaiConsolationList;
  final Map<String, String> damacaiPrizeMoney;

  const _ResultsCacheEntry({
    required this.cachedAt,
    required this.result,
    required this.moonDrawInfo,
    required this.moonSpecialList,
    required this.moonConsolationList,
    required this.damacaiDrawNo,
    required this.damacaiDrawVenue,
    required this.damacaiStarterList,
    required this.damacaiConsolationList,
    required this.damacaiPrizeMoney,
  });
}

class _PageCacheEntry {
  final DateTime cachedAt;
  final String body;

  const _PageCacheEntry({required this.cachedAt, required this.body});
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const Duration _resultsCacheTtl = Duration(hours: 12);
  static const int _resultsCacheMaxEntries = 40;

  static const Duration _pageCacheTtl = Duration(hours: 12);
  static const int _pageCacheMaxEntries = 20;

  final LinkedHashMap<_ResultsCacheKey, _ResultsCacheEntry> _resultsCache =
      LinkedHashMap<_ResultsCacheKey, _ResultsCacheEntry>();

  final LinkedHashMap<String, _PageCacheEntry> _pageCache =
      LinkedHashMap<String, _PageCacheEntry>();

  int _selectedLottery = 0;
  int _selectedTab = 0;
  int _selectedRegionTab = 0; // 0=West, 1=East, 2=Singapore

  DateTime _selectedDate = DateTime.now();
  bool _isLoadingResults = false;
  String? _resultsError;
  LotteryResult? _lotteryResult;

  List<LotteryType> _lotteryTypesForRegion(int regionTabIndex) {
    switch (regionTabIndex) {
      case 1: // East
        return const [
          LotteryType.cashsweep,
          LotteryType.sabah88,
          LotteryType.sadakan,
        ];
      case 2: // Singapore
        return const [LotteryType.singapore];
      case 0: // West
      default:
        return const [
          LotteryType.magnum,
          LotteryType.toto,
          LotteryType.damacai,
        ];
    }
  }

  List<LotteryType> get _visibleLotteryTypes =>
      _lotteryTypesForRegion(_selectedRegionTab);

  int _fetchRequestId = 0;

  String? _moonDrawInfo;
  List<String> _moonSpecialList = const [];
  List<String> _moonConsolationList = const [];

  String? _damacaiDrawNo;
  String? _damacaiDrawVenue;
  List<String> _damacaiStarterList = const [];
  List<String> _damacaiConsolationList = const [];
  Map<String, String> _damacaiPrizeMoney = const {};

  @override
  void initState() {
    super.initState();
    _syncWidget();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  _ResultsCacheKey _cacheKeyFor(
    LotteryType type,
    DateTime date,
    int regionTabIndex,
  ) {
    // Damacai can come from two sources (API or 4dmoon fallback). Keying it
    // without region ensures both paths share the same cache entry.
    final effectiveRegion = type == LotteryType.damacai ? -1 : regionTabIndex;
    return _ResultsCacheKey(
      type: type,
      regionTabIndex: effectiveRegion,
      date: _dateOnly(date),
    );
  }

  _ResultsCacheEntry? _getCachedResults(_ResultsCacheKey key) {
    final entry = _resultsCache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.cachedAt) > _resultsCacheTtl) {
      _resultsCache.remove(key);
      return null;
    }

    // LRU touch
    _resultsCache.remove(key);
    _resultsCache[key] = entry;
    return entry;
  }

  void _putCachedResults(_ResultsCacheKey key, _ResultsCacheEntry entry) {
    _resultsCache.remove(key);
    _resultsCache[key] = entry;

    while (_resultsCache.length > _resultsCacheMaxEntries) {
      _resultsCache.remove(_resultsCache.keys.first);
    }
  }

  _PageCacheEntry? _getCachedPage(String url) {
    final entry = _pageCache[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.cachedAt) > _pageCacheTtl) {
      _pageCache.remove(url);
      return null;
    }

    // LRU touch
    _pageCache.remove(url);
    _pageCache[url] = entry;
    return entry;
  }

  void _putCachedPage(String url, _PageCacheEntry entry) {
    _pageCache.remove(url);
    _pageCache[url] = entry;

    while (_pageCache.length > _pageCacheMaxEntries) {
      _pageCache.remove(_pageCache.keys.first);
    }
  }

  String _timeGreeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _displayName() {
    final user = Supabase.instance.client.auth.currentUser;
    final name =
        (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'])
            ?.toString()
            .trim();
    if (name != null && name.isNotEmpty) return name;

    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) {
      final at = email.indexOf('@');
      return at > 0 ? email.substring(0, at) : email;
    }

    return 'there';
  }

  Widget _buildGreetingCard() {
    final greeting = _timeGreeting(DateTime.now());
    final name = _displayName();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.waving_hand_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $name',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Let\'s check today\'s results.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _selectLottery(int index) {
    setState(() {
      _selectedLottery = index;
    });
    _fetchLotteryResults();
  }

  void _selectRegionTab(int index) {
    setState(() {
      _selectedRegionTab = index;
      _selectedLottery = 0;
    });
    _fetchLotteryResults();
  }

  Future<void> _fetchLotteryResults() async {
    final requestId = ++_fetchRequestId;
    final visible = _visibleLotteryTypes;
    if (visible.isEmpty) return;
    final selectedLottery =
        visible[_selectedLottery.clamp(0, visible.length - 1)];

    final cacheKey = _cacheKeyFor(
      selectedLottery,
      _selectedDate,
      _selectedRegionTab,
    );
    final cached = _getCachedResults(cacheKey);
    if (cached != null) {
      setState(() {
        _isLoadingResults = false;
        _resultsError = null;
        _lotteryResult = cached.result;

        _moonDrawInfo = cached.moonDrawInfo;
        _moonSpecialList = cached.moonSpecialList;
        _moonConsolationList = cached.moonConsolationList;

        _damacaiDrawNo = cached.damacaiDrawNo;
        _damacaiDrawVenue = cached.damacaiDrawVenue;
        _damacaiStarterList = cached.damacaiStarterList;
        _damacaiConsolationList = cached.damacaiConsolationList;
        _damacaiPrizeMoney = cached.damacaiPrizeMoney;
      });
      _syncWidget();
      return;
    }

    setState(() {
      _isLoadingResults = true;
      _resultsError = null;
      _lotteryResult = null;

      _moonDrawInfo = null;
      _moonSpecialList = const [];
      _moonConsolationList = const [];

      if (selectedLottery == LotteryType.damacai) {
        _damacaiDrawNo = null;
        _damacaiDrawVenue = null;
        _damacaiStarterList = const [];
        _damacaiConsolationList = const [];
        _damacaiPrizeMoney = const {};
      }
    });

    if (selectedLottery == LotteryType.damacai) {
      final ok = await _fetchDamacaiResults(
        requestId: requestId,
        requestedDate: _selectedDate,
      );

      if (!ok) {
        if (!mounted || requestId != _fetchRequestId) return;
        setState(() {
          _isLoadingResults = true;
          _resultsError = null;
        });
        await _fetch4dMoonResults(
          requestId: requestId,
          requestedDate: _selectedDate,
          regionTabIndex: 0,
          lotteryType: LotteryType.damacai,
        );
      }
      return;
    }

    await _fetch4dMoonResults(
      requestId: requestId,
      requestedDate: _selectedDate,
      regionTabIndex: _selectedRegionTab,
      lotteryType: selectedLottery,
    );
  }

  String _formatYyyyMmDdDash(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _moonSectionIdForRegion(int regionTabIndex) {
    switch (regionTabIndex) {
      case 1:
        return 'sectionB';
      case 2:
        return 'sectionC';
      case 0:
      default:
        return 'sectionA';
    }
  }

  bool _moonTitleMatches(LotteryType type, String title) {
    final t = title.toLowerCase();
    switch (type) {
      case LotteryType.magnum:
        return t.contains('magnum 4d');
      case LotteryType.toto:
        return t.contains('sportstoto 4d');
      case LotteryType.cashsweep:
        return t.contains('cashsweep');
      case LotteryType.sabah88:
        return t.contains('sabah 4d');
      case LotteryType.sadakan:
        return t.contains('sandakan 4d');
      case LotteryType.singapore:
        return t.contains('singapore 4d');
      case LotteryType.damacai:
        return t.contains('damacai');
    }
  }

  Future<void> _fetch4dMoonResults({
    required int requestId,
    required DateTime requestedDate,
    required int regionTabIndex,
    required LotteryType lotteryType,
  }) async {
    final dateDash = _formatYyyyMmDdDash(requestedDate);
    final url = Uri.parse('https://www.4dmoon.com/past-results/$dateDash');
    final sectionId = _moonSectionIdForRegion(regionTabIndex);
    final urlKey = url.toString();

    try {
      final cachedPage = _getCachedPage(urlKey);

      final String body;
      if (cachedPage != null) {
        body = cachedPage.body;
      } else {
        final response = await http
            .get(
              url,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
                'Accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (!mounted || requestId != _fetchRequestId) return;

        if (response.statusCode != 200) {
          setState(() {
            _resultsError = '4dmoon error: HTTP ${response.statusCode}';
            _isLoadingResults = false;
          });
          return;
        }

        body = utf8.decode(response.bodyBytes, allowMalformed: true);
        _putCachedPage(
          urlKey,
          _PageCacheEntry(cachedAt: DateTime.now(), body: body),
        );
      }

      final doc = html_parser.parse(body);
      final section = doc.getElementById(sectionId);
      if (section == null) {
        setState(() {
          _resultsError = '4dmoon page format changed (missing $sectionId).';
          _isLoadingResults = false;
        });
        return;
      }

      final blocks = section.querySelectorAll('div.mbx');
      if (blocks.isEmpty) {
        setState(() {
          _resultsError = 'No results found on 4dmoon for this tab.';
          _isLoadingResults = false;
        });
        return;
      }

      dom.Element? matched;
      String matchedTitle = '';
      for (final block in blocks) {
        final headerCell =
            block.querySelector('span.rdd')?.parent ??
            block.querySelector('table.rtb td[style*="width:75%"]');
        final title = (headerCell?.text ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (title.isEmpty) continue;
        if (_moonTitleMatches(lotteryType, title)) {
          matched = block;
          matchedTitle = title;
          break;
        }
      }

      if (matched == null) {
        setState(() {
          _resultsError =
              'No ${lotteryType.displayName} results found on this tab.';
          _isLoadingResults = false;
        });
        return;
      }

      final matchedEl = matched;

      final top3 = matchedEl
          .querySelectorAll('td.rtn')
          .map((e) => e.text.trim())
          .where((e) => e.isNotEmpty)
          .take(3)
          .toList(growable: false);

      List<String> special = const [];
      List<String> consolation = const [];
      for (final table in matchedEl.querySelectorAll('table.rtb2')) {
        final header = table
            .querySelector('td.rpl')
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (header == null || header.isEmpty) continue;

        final nums = table
            .querySelectorAll('td.rbn')
            .map((e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim())
            .where((e) => e.isNotEmpty)
            .where((e) => !RegExp(r'^-+$').hasMatch(e))
            .where((e) => e != '----')
            .toList(growable: false);

        if (header.toLowerCase() == 'special') {
          special = nums;
        } else if (header.toLowerCase() == 'consolation') {
          consolation = nums;
        }
      }

      final drawInfo = matchedEl.querySelector('span.rdd')?.text.trim();

      if (top3.isEmpty) {
        setState(() {
          _resultsError = 'Failed to parse results from 4dmoon.';
          _isLoadingResults = false;
        });
        return;
      }

      final parsedResult = LotteryResult(
        name: lotteryType.displayName,
        date: drawInfo ?? matchedTitle,
        numbers: top3,
      );

      final cacheKey = _cacheKeyFor(lotteryType, requestedDate, regionTabIndex);
      _putCachedResults(
        cacheKey,
        _ResultsCacheEntry(
          cachedAt: DateTime.now(),
          result: parsedResult,
          moonDrawInfo: drawInfo,
          moonSpecialList: List<String>.unmodifiable(special),
          moonConsolationList: List<String>.unmodifiable(consolation),
          damacaiDrawNo: null,
          damacaiDrawVenue: null,
          damacaiStarterList: const [],
          damacaiConsolationList: const [],
          damacaiPrizeMoney: const {},
        ),
      );

      setState(() {
        _lotteryResult = parsedResult;
        _moonDrawInfo = drawInfo;
        _moonSpecialList = special;
        _moonConsolationList = consolation;
        _isLoadingResults = false;
        _resultsError = null;
      });
      _syncWidget();
    } on TimeoutException {
      if (!mounted || requestId != _fetchRequestId) return;
      setState(() {
        _resultsError = '4dmoon request timed out.';
        _isLoadingResults = false;
      });
    } catch (e) {
      if (!mounted || requestId != _fetchRequestId) return;
      setState(() {
        _resultsError = 'Failed to fetch results from 4dmoon: $e';
        _isLoadingResults = false;
      });
    }
  }

  String _formatYyyyMmDd(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  Future<bool> _fetchDamacaiResults({
    required int requestId,
    required DateTime requestedDate,
  }) async {
    final yyyymmdd = _formatYyyyMmDd(requestedDate);
    final year = requestedDate.year.toString().padLeft(4, '0');
    final url = Uri.parse(
      'https://damacai.hongineer.com/results/$year/$yyyymmdd.json',
    );

    try {
      final response = await http
          .get(
            url,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
              'Accept': 'application/json,text/plain,*/*',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || requestId != _fetchRequestId) return false;

      if (response.statusCode != 200) {
        setState(() {
          _resultsError = 'Damacai API error: HTTP ${response.statusCode}';
          _isLoadingResults = false;
        });
        return false;
      }

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _resultsError = 'Damacai API returned unexpected JSON.';
          _isLoadingResults = false;
        });
        return false;
      }

      final p1 = decoded['p1']?.toString().trim() ?? '';
      final p2 = decoded['p2']?.toString().trim() ?? '';
      final p3 = decoded['p3']?.toString().trim() ?? '';

      final numbers = <String>[p1, p2, p3].where((n) => n.isNotEmpty).toList();
      if (numbers.isEmpty) {
        setState(() {
          _resultsError = 'No prize numbers found in Damacai response.';
          _isLoadingResults = false;
        });
        return false;
      }

      final drawDate =
          decoded['drawDate']?.toString() ?? requestedDate.toString();

      final drawNo = decoded['drawNo']?.toString();
      final drawVenue = decoded['drawVenue']?.toString();

      final starterListRaw = decoded['starterList'];
      final consolidateListRaw = decoded['consolidateList'];

      final starterList = starterListRaw is List
          ? starterListRaw.map((e) => e.toString()).toList(growable: false)
          : const <String>[];
      final consolationList = consolidateListRaw is List
          ? consolidateListRaw.map((e) => e.toString()).toList(growable: false)
          : const <String>[];

      final prizeMoney = <String, String>{};
      void addMoney(String label, String key) {
        final value = decoded[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          prizeMoney[label] = value;
        }
      }

      addMoney('1+3D Jackpot 1', '1+3DJackpot1');
      addMoney('1+3D Jackpot 2', '1+3DJackpot2');
      addMoney('3D Jackpot', '3DJackpot');
      addMoney('Damacai Jackpot 1', 'dmcJackpot1');
      addMoney('Damacai Jackpot 2', 'dmcJackpot2');
      addMoney('3+3D Bonus (P1)', '3+3DBonusp1');
      addMoney('3+3D Bonus (P2)', '3+3DBonusp2');
      addMoney('3+3D Bonus (P3)', '3+3DBonusp3');

      final parsedResult = LotteryResult(
        name: LotteryType.damacai.displayName,
        date: drawDate,
        numbers: numbers,
      );

      final cacheKey = _cacheKeyFor(LotteryType.damacai, requestedDate, 0);
      _putCachedResults(
        cacheKey,
        _ResultsCacheEntry(
          cachedAt: DateTime.now(),
          result: parsedResult,
          moonDrawInfo: null,
          moonSpecialList: const [],
          moonConsolationList: const [],
          damacaiDrawNo: drawNo,
          damacaiDrawVenue: drawVenue,
          damacaiStarterList: List<String>.unmodifiable(starterList),
          damacaiConsolationList: List<String>.unmodifiable(consolationList),
          damacaiPrizeMoney: Map<String, String>.unmodifiable(prizeMoney),
        ),
      );

      setState(() {
        _lotteryResult = parsedResult;
        _damacaiDrawNo = drawNo;
        _damacaiDrawVenue = drawVenue;
        _damacaiStarterList = starterList;
        _damacaiConsolationList = consolationList;
        _damacaiPrizeMoney = Map.unmodifiable(prizeMoney);
        _isLoadingResults = false;
        _resultsError = null;
      });
      _syncWidget();
      return true;
    } on TimeoutException {
      if (!mounted || requestId != _fetchRequestId) return false;
      setState(() {
        _resultsError = 'Damacai API timed out.';
        _isLoadingResults = false;
      });
      return false;
    } catch (e) {
      if (!mounted || requestId != _fetchRequestId) return false;
      setState(() {
        _resultsError = 'Failed to fetch Damacai results: $e';
        _isLoadingResults = false;
      });
      return false;
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
    final visible = _visibleLotteryTypes;
    if (visible.isEmpty) return;
    final selected = visible[_selectedLottery.clamp(0, visible.length - 1)];
    final numberStr = _lotteryResult?.numbers.join(' ') ?? '';
    final bonusStr = _lotteryResult?.bonus != null
        ? '| Bonus ${_lotteryResult!.bonus}'
        : '';
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
    final visible = _visibleLotteryTypes;
    final selectedLottery =
        visible[_selectedLottery.clamp(0, visible.length - 1)];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                  _buildGreetingCard(),
                  const SizedBox(height: 16),
                  _buildDateBanner(),
                  const SizedBox(height: 16),
                  _buildRegionTabs(),
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
  }

  Widget _buildDateBanner() {
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
              child: const Icon(
                Icons.calendar_today_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDate.difference(DateTime.now()).inDays == 0
                        ? 'Today'
                        : 'Selected Date',
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

  Widget _buildRegionTabs() {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 0, label: Text('West')),
              ButtonSegment<int>(value: 1, label: Text('East')),
              ButtonSegment<int>(value: 2, label: Text('Singapore')),
            ],
            selected: <int>{_selectedRegionTab},
            onSelectionChanged: (values) {
              final next = values.isEmpty ? 0 : values.first;
              _selectRegionTab(next);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLotteryToggles() {
    final visible = _visibleLotteryTypes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose lottery',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List<Widget>.generate(visible.length, (index) {
              final isSelected = index == _selectedLottery;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  onSelected: (_) => _selectLottery(index),
                  label: Text(visible[index].displayName),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsCard(LotteryType selectedLottery) {
    final isDamacai = selectedLottery == LotteryType.damacai;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!isDamacai &&
                      _moonDrawInfo != null &&
                      _moonDrawInfo!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _moonDrawInfo!.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isDamacai &&
                      (_damacaiDrawNo != null ||
                          _damacaiDrawVenue != null)) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (_damacaiDrawNo != null &&
                            _damacaiDrawNo!.trim().isNotEmpty)
                          'Draw ${_damacaiDrawNo!.trim()}',
                        if (_damacaiDrawVenue != null &&
                            _damacaiDrawVenue!.trim().isNotEmpty)
                          _damacaiDrawVenue!.trim(),
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              if (!_isLoadingResults)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _lotteryResult?.numbers.isNotEmpty ?? false
                        ? 'Results'
                        : 'No data',
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                    if (_lotteryResult!.numbers.isNotEmpty)
                      _buildNumberBall(
                        _lotteryResult!.numbers[0],
                        filled: true,
                        label: '1st',
                      ),
                    if (_lotteryResult!.numbers.length > 1)
                      _buildNumberBall(
                        _lotteryResult!.numbers[1],
                        filled: true,
                        label: '2nd',
                      ),
                    if (_lotteryResult!.numbers.length > 2)
                      _buildNumberBall(
                        _lotteryResult!.numbers[2],
                        filled: true,
                        label: '3rd',
                      ),
                    if (_lotteryResult?.bonus != null)
                      _buildNumberBall(_lotteryResult!.bonus!, label: 'Bonus'),
                  ],
                ),
                if (!isDamacai && _moonSpecialList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Special prizes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final n in _moonSpecialList) _buildNumberPill(n),
                    ],
                  ),
                ],
                if (!isDamacai && _moonConsolationList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Consolation prizes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final n in _moonConsolationList) _buildNumberPill(n),
                    ],
                  ),
                ],
                if (isDamacai && _damacaiPrizeMoney.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Prize money',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: _damacaiPrizeMoney.entries
                          .map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'RM ${e.value}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (isDamacai && _damacaiStarterList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Starter prizes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final n in _damacaiStarterList) _buildNumberPill(n),
                    ],
                  ),
                ],
                if (isDamacai && _damacaiConsolationList.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Consolation prizes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final n in _damacaiConsolationList)
                        _buildNumberPill(n),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isDamacai
                              ? 'Damacai results fetched from REST API.'
                              : 'Results fetched from 4dmoon.',
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

  Widget _buildNumberPill(String value) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        value,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
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
            color: filled ? color : Theme.of(context).colorScheme.surface,
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
              color: filled ? Theme.of(context).colorScheme.onPrimary : color,
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        color: Theme.of(context).colorScheme.surface,
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
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
