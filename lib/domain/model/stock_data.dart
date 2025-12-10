class Candle {
  final int date; // Unix timestamp
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'volume': volume,
    };
  }

  factory Candle.fromMap(Map<String, dynamic> map) {
    return Candle(
      date: map['date'] as int,
      open: (map['open'] as num).toDouble(),
      high: (map['high'] as num).toDouble(),
      low: (map['low'] as num).toDouble(),
      close: (map['close'] as num).toDouble(),
      volume: map['volume'] as int,
    );
  }
}

class StockQuote {
  final String symbol;
  final List<Candle> candles;

  StockQuote({required this.symbol, required this.candles});
}
