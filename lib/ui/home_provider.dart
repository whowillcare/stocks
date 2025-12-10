import 'dart:convert';
import 'dart:math';
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
  final YahooFinanceApi _yahooApi; // Direct access for search for now, or move to repo? Repo is better but Api for now is quick.

  HomeProvider({StockRepository? repository})
      : _repository = repository ?? StockRepositoryImpl(),
        _yahooApi = YahooFinanceApi() {
     loadSessions();
  }

  // Global Strategy Settings
  int atrPeriod = 14;
  double atrMultiplier = 3.0;
  int emaPeriod = 20;

  // Chart Settings
  int visibleDays = 90;

  // Trend Analysis Settings (Scores)
  double scoreFomo = 3.0;
  double scoreSlightlyAbove = 1.0;
  double scoreOptimal = 0.0;
  double scoreFallingKnife = 2.0;
  double scoreVolumeSpike = -1.0;
  double scoreSideways = 2.0;

  // Search History
  List<String> _searchHistory = [];
  List<String> get searchHistory => List.unmodifiable(_searchHistory);

  Future<void> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load Global Settings
    atrPeriod = prefs.getInt('atrPeriod') ?? 14;
    atrMultiplier = prefs.getDouble('atrMultiplier') ?? 3.0;
    emaPeriod = prefs.getInt('emaPeriod') ?? 20;
    visibleDays = prefs.getInt('visibleDays') ?? 90;
    
    // Load Trend Settings
    scoreFomo = prefs.getDouble('scoreFomo') ?? 3.0;
    scoreSlightlyAbove = prefs.getDouble('scoreSlightlyAbove') ?? 1.0;
    scoreOptimal = prefs.getDouble('scoreOptimal') ?? 0.0;
    scoreFallingKnife = prefs.getDouble('scoreFallingKnife') ?? 2.0;
    scoreVolumeSpike = prefs.getDouble('scoreVolumeSpike') ?? -1.0;
    scoreSideways = prefs.getDouble('scoreSideways') ?? 2.0;
    
    // Load History
    final history = prefs.getStringList('searchHistory');
    if (history != null) {
        _searchHistory = history;
    }
    
    final String? sessionsJson = prefs.getString('sessions');
    
    _sessions.clear();
    
    if (sessionsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(sessionsJson);
        _sessions.addAll(list.map((e) => StockSession.fromJson(e)).toList());
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

    notifyListeners();
  }

  Future<void> saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String json = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('sessions', json);
  }
  
  Future<void> saveGlobalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('atrPeriod', atrPeriod);
    await prefs.setDouble('atrMultiplier', atrMultiplier);
    await prefs.setInt('emaPeriod', emaPeriod);
    await prefs.setInt('visibleDays', visibleDays);
    
    await prefs.setDouble('scoreFomo', scoreFomo);
    await prefs.setDouble('scoreSlightlyAbove', scoreSlightlyAbove);
    await prefs.setDouble('scoreOptimal', scoreOptimal);
    await prefs.setDouble('scoreFallingKnife', scoreFallingKnife);
    await prefs.setDouble('scoreVolumeSpike', scoreVolumeSpike);
    await prefs.setDouble('scoreSideways', scoreSideways);
    
    await prefs.setStringList('searchHistory', _searchHistory);
  }


  final List<StockSession> _sessions = [];
  List<StockSession> get sessions => List.unmodifiable(_sessions);

  int _currentSessionIndex = 0;
  int get currentSessionIndex => _currentSessionIndex;

  StockSession get currentSession => _sessions[_currentSessionIndex];

  void addSession() {
    final session = StockSession(const Uuid().v4());
    _sessions.add(session);
    _currentSessionIndex = _sessions.length - 1;
    saveSessions();
    notifyListeners();
  }

  void removeSession(int index) {
    if (_sessions.length <= 1) return; // Keep at least one
    _sessions.removeAt(index);
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

  void updateGlobalAtrParams({int? period, double? multiplier}) {
    if (period != null) atrPeriod = period;
    if (multiplier != null) atrMultiplier = multiplier;
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

  void addToHistory(String symbol) {
      if (symbol.isEmpty) return;
      _searchHistory.remove(symbol);
      _searchHistory.insert(0, symbol);
      if (_searchHistory.length > 20) {
          _searchHistory = _searchHistory.sublist(0, 20);
      }
      saveGlobalSettings();
  }

  Future<void> fetchStockData(String symbol, {bool forceRefresh = false}) async {
      await fetchStockDataForSession(currentSession, symbol, forceRefresh: forceRefresh);
  }

  Future<void> fetchStockDataForSession(StockSession session, String symbol, {bool forceRefresh = false}) async {
    if (symbol.isEmpty) return;

    session.isLoading = true;
    session.errorMessage = null;
    notifyListeners();

    try {
      session.stockQuote = await _repository.getStockData(symbol, forceRefresh: forceRefresh);
      session.symbol = session.stockQuote?.symbol;
      addToHistory(session.symbol!); // Add to history
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
      strategy = AtrStopStrategy(period: atrPeriod, multiplier: atrMultiplier);
    } else {
      strategy = EmaStopStrategy(period: emaPeriod);
    }
    
    final result = strategy.calculateStopPrice(session.stockQuote!.candles, entryDate: session.entryDate, entryPrice: session.entryPrice);
    session.cutLossPrice = result.cutLossPrice;
    session.trailingStopPrice = result.trailingStopPrice;
    session.equation = result.equation;
    
    // Calculate Trend/Risk
    final candles = session.stockQuote!.candles;
    
    // Helper helper:
    final ema20Series = EmaStopStrategy.calculateValidSeries(candles, 20); 
    final ema50Series = EmaStopStrategy.calculateValidSeries(candles, 50);

    // Calculate ATR manually here or expose from Strategy? 
    double atr = 0.0;
    if (candles.length > atrPeriod) {
         // This is a bit expensive to re-calc always. 
         // Optimize later. For now duplicate logic from AtrStopStrategy broadly.
         // Actually, let's just create instance and use a public method if available? No public method.
         // Let's add a static method to AtrStopStrategy or just inline.
         
         List<double> trs = [];
         for (int i = candles.length - atrPeriod - 1; i < candles.length; i++) {
             if (i <= 0) continue;
             final current = candles[i];
             final prev = candles[i-1];
             final tr = max(current.high - current.low, max((current.high - prev.close).abs(), (current.low - prev.close).abs()));
             trs.add(tr);
         }
         if (trs.isNotEmpty) {
             atr = trs.reduce((a, b) => a + b) / trs.length;
         }
    }
    
    final analyzer = TrendAnalyzer(
        scoreFomo: scoreFomo,
        scoreSlightlyAbove: scoreSlightlyAbove,
        scoreOptimal: scoreOptimal,
        scoreFallingKnife: scoreFallingKnife,
        scoreVolumeSpike: scoreVolumeSpike,
        scoreSideways: scoreSideways,
    );
    
    session.trendAnalysis = analyzer.analyze(candles, ema20Series, ema50Series, atr);
  }

  void updateTrendParams({
      double? fomo, 
      double? slightlyAbove, 
      double? optimal, 
      double? fallingKnife, 
      double? volumeSpike, 
      double? sideways
  }) {
      if (fomo != null) scoreFomo = fomo;
      if (slightlyAbove != null) scoreSlightlyAbove = slightlyAbove;
      if (optimal != null) scoreOptimal = optimal;
      if (fallingKnife != null) scoreFallingKnife = fallingKnife;
      if (volumeSpike != null) scoreVolumeSpike = volumeSpike;
      if (sideways != null) scoreSideways = sideways;
      
      _recalculateAllStops();
      saveGlobalSettings();
      notifyListeners();
  }
}
