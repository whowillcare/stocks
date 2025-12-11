import '../domain/model/stock_data.dart';
import 'yahoo_api.dart';
import 'stock_cache.dart';

abstract class StockRepository {
  Future<StockQuote> getStockData(String symbol, {bool forceRefresh = false});
}

class StockRepositoryImpl implements StockRepository {
  final YahooFinanceApi _api;
  final StockCache _cache;

  StockRepositoryImpl({YahooFinanceApi? api, StockCache? cache})
    : _api = api ?? YahooFinanceApi(),
      _cache = cache ?? StockCache.instance;

  @override
  Future<StockQuote> getStockData(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    // If not forcing refresh, try cache first
    if (!forceRefresh) {
      final cachedCandles = await _cache.getCandles(symbol);
      if (cachedCandles.isNotEmpty) {
        return StockQuote(symbol: symbol, candles: cachedCandles);
      }
    }

    try {
      final candles = await _api.fetchChartData(symbol);
      await _cache.insertCandles(symbol, candles);
      return StockQuote(symbol: symbol, candles: candles);
    } catch (e) {
      // If force refresh failed, fallback to cache if available
      if (forceRefresh) {
        final cachedCandles = await _cache.getCandles(symbol);
        if (cachedCandles.isNotEmpty) {
          return StockQuote(symbol: symbol, candles: cachedCandles);
        }
      }
      rethrow;
    }
  }
}
