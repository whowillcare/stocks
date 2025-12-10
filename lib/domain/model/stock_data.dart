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

  @override
  String toString() {
    return 'date: $date, open: $open, high: $high, low: $low, close: $close, volume: $volume';
  }
}

class StockQuote {
  final String symbol;
  final List<Candle> candles;

  StockQuote({required this.symbol, required this.candles});
}

/// Trade lifecycle states for post-entry monitoring
enum TradeState {
  notEntered,           // No position yet
  waitingConfirmation,  // Position entered, waiting 3-7 days for confirmation
  confirmed,            // Trend confirmed, normal trade management
  failed                // Confirmation failed, should exit
}

/// Result of post-entry trend confirmation analysis
class PostEntryAnalysis {
  final TradeState state;
  final int daysHeld;
  final bool structureIntact;
  final bool aboveKeyEma;
  final String note;
  
  PostEntryAnalysis({
    required this.state,
    required this.daysHeld,
    required this.structureIntact,
    required this.aboveKeyEma,
    required this.note,
  });
}

/// Result of swing structure analysis (HH/HL pattern)
class StructureAnalysis {
  final bool hasHigherHighs;
  final bool hasHigherLows;
  final int peakCount;
  final int troughCount;
  final String pattern; // "Uptrend Structure", "Downtrend Structure", "No Clear Pattern"
  
  StructureAnalysis({
    required this.hasHigherHighs,
    required this.hasHigherLows,
    required this.peakCount,
    required this.troughCount,
    required this.pattern,
  });
}

/// Enhanced strategy result with trade lifecycle support
class StrategyResult {
  // Core stop prices
  final double cutLossPrice;
  final double? trailingStopPrice;
  final String equation;
  
  // Post-entry monitoring (null if not entered)
  final PostEntryAnalysis? postEntry;
  
  // Entry analysis
  final bool canEnter;
  final String entryReason;
  final bool breakoutDetected;
  
  // Risk management
  final double? suggestedPositionSize;
  final bool moveToBreakeven;
  final double? partialProfitTarget;
  
  StrategyResult({
    required this.cutLossPrice,
    this.trailingStopPrice,
    required this.equation,
    this.postEntry,
    this.canEnter = true,
    this.entryReason = '',
    this.breakoutDetected = false,
    this.suggestedPositionSize,
    this.moveToBreakeven = false,
    this.partialProfitTarget,
  });
}
