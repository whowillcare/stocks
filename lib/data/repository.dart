
import '../domain/model/stock_data.dart';
import 'yahoo_api.dart';
import 'stock_database.dart';

abstract class StockRepository {
  Future<StockQuote> getStockData(String symbol, {bool forceRefresh = false});
}

class StockRepositoryImpl implements StockRepository {
  final YahooFinanceApi _api;
  final StockDatabase _db;

  StockRepositoryImpl({YahooFinanceApi? api, StockDatabase? db})
      : _api = api ?? YahooFinanceApi(),
        _db = db ?? StockDatabase.instance;

  @override
  Future<StockQuote> getStockData(String symbol, {bool forceRefresh = false}) async {
    // If not forcing refresh, try cache first
    if (!forceRefresh) {
      final cachedCandles = await _db.getCandles(symbol);
      if (cachedCandles.isNotEmpty) {
        // We could also check date here to auto-refresh if old, but user asked for manual refresh button.
        // So we stick to manual force.
        return StockQuote(symbol: symbol, candles: cachedCandles);
      }
    }

    try {
      final candles = await _api.fetchChartData(symbol);
      await _db.insertCandles(symbol, candles);
      return StockQuote(symbol: symbol, candles: candles);
    } catch (e) {
       // If force refresh failed, fallback to cache if available
      if (forceRefresh) {
         final cachedCandles = await _db.getCandles(symbol);
         if (cachedCandles.isNotEmpty) {
           return StockQuote(symbol: symbol, candles: cachedCandles);
         }
      }
      rethrow;
    }
  }
}
