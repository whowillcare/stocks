import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/model/stock_data.dart';
import '../domain/model/search_result.dart';

const String prefixProxy = String.fromEnvironment(
  'PREFIX_PROXY',
  defaultValue: '',
);

class YahooFinanceApi {
  static const String _baseUrl =
      '${prefixProxy}https://query1.finance.yahoo.com/v8/finance/chart';

  Future<List<Candle>> fetchChartData(String symbol) async {
    final url = Uri.parse(
      '$_baseUrl/$symbol?range=5y&interval=1d',
    ); // Fetch 5 years of daily data

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final result = json['chart']['result'][0];
        final timestamp = result['timestamp'] as List<dynamic>;
        final indicators = result['indicators']['quote'][0];

        final opens = indicators['open'] as List<dynamic>;
        final highs = indicators['high'] as List<dynamic>;
        final lows = indicators['low'] as List<dynamic>;
        final closes = indicators['close'] as List<dynamic>;
        final volumes = indicators['volume'] as List<dynamic>;

        final List<Candle> candles = [];

        for (int i = 0; i < timestamp.length; i++) {
          if (opens[i] == null ||
              highs[i] == null ||
              lows[i] == null ||
              closes[i] == null) {
            continue; // Skip incomplete data
          }

          candles.add(
            Candle(
              date: timestamp[i] as int,
              open: (opens[i] as num).toDouble(),
              high: (highs[i] as num).toDouble(),
              low: (lows[i] as num).toDouble(),
              close: (closes[i] as num).toDouble(),
              volume: volumes[i] != null ? (volumes[i] as num).toInt() : 0,
            ),
          );
        }
        return candles;
      } else {
        throw Exception('Failed to load stock data: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching data: $e');
    }
  }

  Future<List<StockSearchResult>> searchSymbols(String query) async {
    final url = Uri.parse(
      '${prefixProxy}https://query1.finance.yahoo.com/v1/finance/search?q=$query&quotesCount=10&newsCount=0',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final quotes = json['quotes'] as List<dynamic>;

        return quotes
            .map(
              (q) => StockSearchResult(
                symbol: q['symbol'] ?? '',
                shortname: q['shortname'] ?? q['longname'] ?? '',
                exchange: q['exchange'] ?? '',
              ),
            )
            .toList();
      } else {
        throw Exception('Failed to search symbols: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching symbols: $e');
    }
  }
}
