import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/repository.dart';
import '../data/yahoo_api.dart'; // For search candidates

import '../domain/model/search_result.dart';
import '../domain/strategy/strategy.dart';
import '../domain/analysis/trend_analyzer.dart';
import 'stock_session.dart';

class HomeProvider extends ChangeNotifier {
  final StockRepository _repository;
  final YahooFinanceApi
  _yahooApi; // Direct access for search for now, or move to repo? Repo is better but Api for now is quick.

  static int maxHistoryLength = 100;

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
    for (var session in _sessions) {
      if (session.symbol != null) {
        fetchStockDataForSession(session, session.symbol!); // Re-fetch data
      }
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
