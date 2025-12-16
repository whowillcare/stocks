import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/repository.dart';
import '../data/yahoo_api.dart'; // For search candidates

import '../domain/model/search_result.dart';
import '../domain/model/stock_event.dart';
import '../domain/strategy/strategy.dart';
import '../domain/analysis/trend_analyzer.dart';
import 'stock_session.dart';
import '../services/notification_service.dart';

class HomeProvider extends ChangeNotifier {
  final StockRepository _repository;
  final YahooFinanceApi
  _yahooApi; // Direct access for search for now, or move to repo? Repo is better but Api for now is quick.

  static int maxHistoryLength = 100;
  static int maxEventLogLength = 50;

  // Available strategies
  final List<StopStrategy> _strategies = [AtrStopStrategy(), EmaStopStrategy()];

  HomeProvider({StockRepository? repository})
    : _repository = repository ?? StockRepositoryImpl(),
      _yahooApi = YahooFinanceApi() {
    loadSessions();
  }

  // Global Strategy Settings
  int atrPeriod = 14;
  double atrMultiplier = 3.0; // ISL multiplier
  double trailMultiplier = 3.0; // Trailing stop multiplier
  int emaPeriod = 20;

  // Chart Settings
  int visibleDays = 90;
  int currentIndex = -1;

  // Search History
  final Map<String, String> _searchHistory = {};

  List<String> get searchHistory => List.unmodifiable(_searchHistory.keys);

  final List<StockEvent> _eventLog = [];
  List<StockEvent> get eventLog => List.unmodifiable(_eventLog);

  void addEvent(String symbol, String message, {String type = 'info'}) {
    _eventLog.add(
      StockEvent(
        timestamp: DateTime.now(),
        symbol: symbol,
        message: message,
        type: type,
      ),
    );
    if (_eventLog.length > maxEventLogLength) {
      _eventLog.removeAt(0); // Keep size limited
    }
    saveEvents();
    notifyListeners();
  }

  void clearEvents() {
    _eventLog.clear();
    saveEvents();
    notifyListeners();
  }

  Future<void> saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonVal = jsonEncode(_eventLog.map((e) => e.toJson()).toList());
    await prefs.setString('eventLog', jsonVal);
  }

  Future<void> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Global Settings
    atrPeriod = prefs.getInt('atrPeriod') ?? 14;
    atrMultiplier = prefs.getDouble('atrMultiplier') ?? 3.0;
    emaPeriod = prefs.getInt('emaPeriod') ?? 20;
    visibleDays = prefs.getInt('visibleDays') ?? 90;
    trailMultiplier = prefs.getDouble('trailMultiplier') ?? 3.0;

    // Load History
    /*final history = prefs.getStringList('searchHistory');
    if (history != null) {
      _searchHistory = history;
    }*/

    final String? eventsJson = prefs.getString('eventLog');
    if (eventsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(eventsJson);
        _eventLog.addAll(list.map((e) => StockEvent.fromJson(e)).toList());
      } catch (e) {
        debugPrint('Error loading events: $e');
      }
    }

    final String? sessionsJson = prefs.getString('sessions');

    _sessions.clear();

    if (sessionsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(sessionsJson);
        _sessions.addAll(
          list.map((e) {
            final session = StockSession.fromJson(e);
            _addHistory(session);
            return session;
          }).toList(),
        );
      } catch (e) {
        debugPrint('Error loading sessions: $e');
      }
    }

    if (_sessions.isEmpty) {
      _sessions.add(StockSession(const Uuid().v4()));
    }

    // Restore data for loaded sessions if symbol exists
    // We use refreshAllSessions with force=false to check for updates but respect cache validity logic
    // if implemented in repo, otherwise it just fetches.
    // Actually repo.getStockData defaults to checking cache if not forced.
    if (_sessions.isNotEmpty) {
      refreshAllSessions(forceRefresh: false);
    }

    _updateSessionMap();
    notifyListeners();
  }

  Future<void> saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String json = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    _updateSessionMap();
    await prefs.setString('sessions', json);
  }

  Future<void> saveGlobalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('atrPeriod', atrPeriod);
    await prefs.setDouble('atrMultiplier', atrMultiplier);
    await prefs.setDouble('trailMultiplier', trailMultiplier);
    await prefs.setInt('emaPeriod', emaPeriod);
    await prefs.setInt('visibleDays', visibleDays);
    // await prefs.setStringList('searchHistory', _searchHistory);
  }

  final List<StockSession> _sessions = [];
  final Map<String, StockSession> _sessionMap = {};

  void _updateSessionMap() {
    _sessionMap.clear();
    for (var session in _sessions) {
      _sessionMap[session.id] = session;
    }
  }

  List<StockSession> get sessions => List.unmodifiable(_sessions);

  int _currentSessionIndex = 0;

  int get currentSessionIndex => _currentSessionIndex;

  StockSession get currentSession => _sessions[_currentSessionIndex];

  void switchSessionFromHistory(String name) {
    if (_searchHistory.containsKey(name)) {
      final id = _searchHistory[name];
      if (id != null) {
        final index = _sessions.indexWhere((element) => element.id == id);
        if (index > -1) {
          setCurrentSession(index);
        }
      }
    }
  }

  void _addHistory(StockSession session) {
    final key = session.symbol;
    if (key != null) {
      _searchHistory[key] = session.id;
    }
  }

  void addSession() {
    final session = StockSession(const Uuid().v4());
    _sessions.add(session);
    _addHistory(session);
    _currentSessionIndex = _sessions.length - 1;
    saveSessions();
    notifyListeners();
  }

  void removeSession(int index) {
    if (_sessions.length <= 1) return; // Keep at least one
    final removed = _sessions.removeAt(index);
    _searchHistory.remove(removed.id);
    // Remove related events
    if (removed.symbol != null) {
      _eventLog.removeWhere((e) => e.symbol == removed.symbol);
      saveEvents();
    }

    if (_currentSessionIndex >= _sessions.length) {
      _currentSessionIndex = _sessions.length - 1;
    }
    saveSessions();
    notifyListeners();
  }

  void setCurrentSession(int index) {
    _currentSessionIndex = index;
    notifyListeners();
  }

  // --- Session Specific Actions ---

  void setStrategyIndex(int index) {
    currentSession.selectedStrategyIndex = index;
    _calculateStop(currentSession);
    notifyListeners();
  }

  void updateEntryParams({DateTime? entryDate, double? entryPrice}) {
    if (entryDate != null) currentSession.entryDate = entryDate;
    if (entryPrice != null) currentSession.entryPrice = entryPrice;

    _calculateStop(currentSession);
    saveSessions();
    notifyListeners();
  }

  void clearEntryParams() {
    currentSession.entryDate = null;
    currentSession.entryPrice = null;
    _calculateStop(currentSession);
    saveSessions();
    notifyListeners();
  }

  void updateGlobalAtrParams({
    int? period,
    double? multiplier,
    double? trailMultiplier,
  }) {
    if (period != null) atrPeriod = period;
    if (multiplier != null) atrMultiplier = multiplier;
    if (trailMultiplier != null) this.trailMultiplier = trailMultiplier;
    _recalculateAllStops();
    saveGlobalSettings();
    notifyListeners();
  }

  void updateGlobalEmaParams({int? period}) {
    if (period != null) emaPeriod = period;
    _recalculateAllStops();
    saveGlobalSettings();
    notifyListeners();
  }

  void updateVisibleDays(int days) {
    if (days < 5) days = 5; // Minimum 5 days
    if (visibleDays != days) {
      visibleDays = days;
      saveGlobalSettings();
      // No need to notify listeners aggressively if it causes rebuilds, but we might want to?
      // Actually, we don't need to rebuild all charts immediately if user is zooming ONE chart.
      // But for consistency let's notify.
      notifyListeners();
    }
  }

  Future<void> refreshAllSessions({bool forceRefresh = true}) async {
    final changes = <String>[];
    for (var session in _sessions) {
      if (session.symbol != null) {
        // Save previous state
        session.previousTrendAnalysis = session.trendAnalysis;
        session.previousTrailingStop = session.trailingStopPrice;

        // Fetch new data
        await fetchStockDataForSession(
          session,
          session.symbol!,
          forceRefresh: forceRefresh,
        );

        // Compare
        final diff = _compareSessionChanges(session);
        if (diff.isNotEmpty) {
          final msg = '$diff';
          changes.add('${session.symbol}: $msg');
          // For now, these real-time alerts are type 'trend' or 'info'
          addEvent(session.symbol!, msg, type: 'trend');
        }

        // Generate historical events if entered
        if (session.entryDate != null && session.entryPrice != null) {
          final histEvents = _generateHistoricalEvents(session);
          changes.addAll(histEvents);
        }
      }
    }

    if (changes.isNotEmpty) {
      // Show latest event content
      final body = changes.length == 1
          ? changes.first
          : '${changes.length} updates. Latest: ${changes.last}';

      NotificationService().showNotification(
        id: 0,
        title: 'Stock Analysis Updates',
        body: body,
        payload: 'events',
      );
    }
  }

  List<String> _generateHistoricalEvents(StockSession session) {
    if (session.stockQuote == null || session.stockQuote!.candles.isEmpty)
      return [];
    if (session.entryDate == null || session.entryPrice == null) return [];

    final symbol = session.symbol!;
    // Clear existing generated events
    _eventLog.removeWhere((e) => e.symbol == symbol && e.type == 'stop_loss');

    final candles = session.stockQuote!.candles;
    final entryDate = session.entryDate!;
    final List<String> generatedMsgs = [];

    // Find entry index
    int entryIndex = -1;
    for (int i = 0; i < candles.length; i++) {
      final d = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);
      if (d.year == entryDate.year &&
          d.month == entryDate.month &&
          d.day == entryDate.day) {
        entryIndex = i;
        break;
      }
    }

    if (entryIndex == -1) {
      for (int i = 0; i < candles.length; i++) {
        final d = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);
        if (d.isAfter(entryDate)) {
          entryIndex = i;
          break;
        }
      }
    }

    if (entryIndex == -1) return [];

    final strategy = _strategies[session.selectedStrategyIndex];
    if (strategy is! AtrStopStrategy) return [];

    double? prevStop;

    for (int i = entryIndex; i < candles.length; i++) {
      final slice = candles.sublist(0, i + 1);
      final date = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);

      final result = strategy.calculateStopPrice(
        slice,
        entryDate: session.entryDate,
        entryPrice: session.entryPrice,
      );

      double? currentStop = result.trailingStopPrice;

      if (currentStop != null) {
        if (prevStop != null && currentStop < prevStop) {
          currentStop = prevStop;
        }

        if (prevStop != null && currentStop > prevStop) {
          final diff = currentStop - prevStop;
          if (diff > 0.01) {
            final msg =
                'Stop Raised: ${prevStop.toStringAsFixed(2)} -> ${currentStop.toStringAsFixed(2)}';
            _eventLog.add(
              StockEvent(
                timestamp: date,
                symbol: symbol,
                message: msg,
                type: 'stop_loss',
              ),
            );

            // Return content if it's the LATEST day (today/yesterday)
            // to avoid spamming notification with old history backfill
            if (i == candles.length - 1) {
              generatedMsgs.add('$symbol: $msg');
            }
          }
        }
        prevStop = currentStop;
      }
    }

    _eventLog.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    saveEvents();
    return generatedMsgs;
  }

  String _compareSessionChanges(StockSession session) {
    final old = session.previousTrendAnalysis;
    final curr = session.trendAnalysis;
    final parts = <String>[];

    if (old == null || curr == null) return '';

    // Trend Score
    if (old.trendScore != curr.trendScore) {
      parts.add('Score ${old.trendScore}->${curr.trendScore}');
    }

    // Trend Label
    if (old.trend != curr.trend) {
      parts.add('Trend ${old.trend}->${curr.trend}');
    }

    // Structure
    if (old.structure['HH'] != curr.structure['HH']) {
      parts.add(curr.structure['HH'] == true ? '+HH' : '-HH');
    }
    if (old.structure['HL'] != curr.structure['HL']) {
      parts.add(curr.structure['HL'] == true ? '+HL' : '-HL');
    }

    // Trailing Stop
    if (session.previousTrailingStop != null &&
        session.trailingStopPrice != null) {
      if ((session.previousTrailingStop! - session.trailingStopPrice!).abs() >
          0.01) {
        // Only show if it MOVED UP (usually TS only goes up or stays) or changed significantly
        if (session.trailingStopPrice! > session.previousTrailingStop!) {
          parts.add(
            'Stop raised to ${session.trailingStopPrice!.toStringAsFixed(2)}',
          );
        }
      }
    }

    return parts.join(', ');
  }

  Future<void> fetchStockData(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    await fetchStockDataForSession(
      currentSession,
      symbol,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> fetchStockDataForSession(
    StockSession session,
    String symbol, {
    bool forceRefresh = false,
  }) async {
    if (symbol.isEmpty) return;
    bool switchTab = false;
    if (_searchHistory.containsKey(symbol)) {
      final historySession = _searchHistory[symbol];
      if (historySession != null) {
        if (session.id != historySession) {
          if (session.symbol == null) {
            removeSession(
              _sessions.indexWhere((element) => element.id == session.id),
            );
          }
          session = _sessionMap[historySession]!;
          switchTab = true;
        }
      }
    }
    session.isLoading = true;
    session.errorMessage = null;
    if (switchTab) {
      setCurrentSession(
        _sessions.indexWhere((element) => element.id == session.id),
      );
    }
    notifyListeners();

    try {
      session.stockQuote = await _repository.getStockData(
        symbol,
        forceRefresh: forceRefresh,
      );
      session.symbol = session.stockQuote?.symbol;
      session.lastRefreshedAt = DateTime.now();
      _calculateStop(session);
      saveSessions();
    } catch (e) {
      session.errorMessage = e.toString();
    } finally {
      session.isLoading = false;
      notifyListeners();
    }
  }

  Future<List<StockSearchResult>> searchCandidates(String query) async {
    if (query.isEmpty) return [];
    try {
      return await _yahooApi.searchSymbols(query);
    } catch (e) {
      debugPrint('Search error: $e'); // Silent fail for UI search
      return [];
    }
  }

  void _recalculateAllStops() {
    for (var session in _sessions) {
      _calculateStop(session);
    }
  }

  void _calculateStop(StockSession session) {
    if (session.stockQuote == null) return;

    StopStrategy strategy;
    if (session.selectedStrategyIndex == 0) {
      strategy = AtrStopStrategy(
        period: atrPeriod,
        stopMultiplier: atrMultiplier,
        trailMultiplier: trailMultiplier,
      );
    } else {
      strategy = EmaStopStrategy(period: emaPeriod);
    }

    final result = strategy.calculateStopPrice(
      session.stockQuote!.candles,
      entryDate: session.entryDate,
      entryPrice: session.entryPrice,
    );
    session.cutLossPrice = result.cutLossPrice;
    session.trailingStopPrice = result.trailingStopPrice;
    session.equation = result.equation;
    session.monitorResult = result.monitorResult;

    // Calculate Trend/Risk using new simplified TrendAnalyzer
    final candles = session.stockQuote!.candles;
    final analyzer = TrendAnalyzer(atrPeriod: atrPeriod);
    session.trendAnalysis = analyzer.analyze(candles);
  }

  void updateTrendParams({
    int? atrPeriod,
    double? stopMult,
    double? trailMult,
  }) {
    if (atrPeriod != null) this.atrPeriod = atrPeriod;
    if (stopMult != null) atrMultiplier = stopMult;
    if (trailMult != null) trailMultiplier = trailMult;

    _recalculateAllStops();
    saveGlobalSettings();
    notifyListeners();
  }
}
