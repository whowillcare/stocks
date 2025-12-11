import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/model/stock_data.dart';

/// SharedPreferences-based cache for stock candle data.
/// This replaces the SQLite implementation for web compatibility.
class StockCache {
  static final StockCache instance = StockCache._();

  StockCache._();

  String _cacheKey(String symbol) => 'cache_candles_${symbol.toUpperCase()}';

  Future<void> insertCandles(String symbol, List<Candle> candles) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = candles.map((c) => c.toMap()).toList();
    await prefs.setString(_cacheKey(symbol), jsonEncode(jsonList));
  }

  Future<List<Candle>> getCandles(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cacheKey(symbol));
    if (jsonStr == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList
          .map((json) => Candle.fromMap(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If parsing fails, return empty list (cache miss)
      return [];
    }
  }
}
