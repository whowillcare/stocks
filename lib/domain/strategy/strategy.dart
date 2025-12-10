import 'dart:math';
import '../model/stock_data.dart';

class StrategyResult {
  final double cutLossPrice;
  final double? trailingStopPrice;
  final String equation;

  StrategyResult({
    required this.cutLossPrice,
    this.trailingStopPrice,
    required this.equation,
  });
}

abstract class StopStrategy {
  String get name;
  StrategyResult calculateStopPrice(List<Candle> candles, {DateTime? entryDate, double? entryPrice});
}

class AtrStopStrategy implements StopStrategy {
  final int period;
  final double multiplier;

  AtrStopStrategy({this.period = 14, this.multiplier = 3.0});

  @override
  String get name => 'ATR Dual Stop ($period, ${multiplier}x)';
  
  /// Calculate ATR for candles up to the specified index (inclusive)
  static double? _calculateATR(List<Candle> candles, int untilIndex, int period) {
    if (untilIndex < period || candles.isEmpty) return null;
    
    List<double> trs = [];
    // Calculate True Range for the period ending at untilIndex
    final startIdx = max(0, untilIndex - period);
    for (int i = startIdx; i <= untilIndex; i++) {
      if (i == 0) continue;
      final current = candles[i];
      final prev = candles[i - 1];
      final tr = max(
        current.high - current.low,
        max(
          (current.high - prev.close).abs(),
          (current.low - prev.close).abs()
        )
      );
      trs.add(tr);
    }
    
    if (trs.isEmpty) return null;
    if (trs.length > period) trs = trs.sublist(trs.length - period);
    
    return trs.reduce((a, b) => a + b) / trs.length;
  }
  
  @override
  StrategyResult calculateStopPrice(List<Candle> candles, {DateTime? entryDate, double? entryPrice}) {
    if (candles.length < period + 1) {
        return StrategyResult(cutLossPrice: 0.0, equation: 'Not enough data');
    }
    
    // 1. Cut Loss: Use historical ATR (at entry or reference point)
    // Determine reference index and close price for Cut Loss
    
    int cutLossRefIndex = candles.length - 1; // Default to latest
    double refClose = 0.0;
    String cutLossRefDesc = '';
    bool usedExplicitRef = false;

    if (entryPrice != null) {
        refClose = entryPrice;
        cutLossRefDesc = 'Entry Price';
        usedExplicitRef = true;
        // Use latest ATR when entry price is manually specified
        cutLossRefIndex = candles.length - 1;
    } else if (entryDate != null) {
        // Find candle matching entry date
        final eY = entryDate.year;
        final eM = entryDate.month;
        final eD = entryDate.day;
        
        int foundIndex = -1;
        for (int i = 0; i < candles.length; i++) {
            final d = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);
            if (d.year == eY && d.month == eM && d.day == eD) {
                foundIndex = i;
                break;
            }
        }
        
        if (foundIndex != -1) {
            cutLossRefIndex = foundIndex;
            refClose = candles[foundIndex].close;
            cutLossRefDesc = 'Entry Close';
            usedExplicitRef = true;
        }
    }

    if (!usedExplicitRef) {
        // Fallback: Trading Hours logic
        final nowUtc = DateTime.now().toUtc();
        final hour = nowUtc.hour;
        final isTradingHours = hour >= 13 && hour < 22; 
        
        cutLossRefIndex = candles.length - 1;
        refClose = candles.last.close;
        cutLossRefDesc = 'Last Close';
        
        if (isTradingHours && candles.length > 1) {
            cutLossRefIndex = candles.length - 2;
            refClose = candles[candles.length - 2].close;
            cutLossRefDesc = 'Prev Close (Trading Hours)';
        }
    }

    // Calculate Cut Loss ATR (historical, at reference point)
    final cutLossATR = _calculateATR(candles, cutLossRefIndex, period);
    if (cutLossATR == null) {
        return StrategyResult(cutLossPrice: 0.0, equation: 'Error calculating Cut Loss ATR');
    }
    
    final cutLoss = refClose - (cutLossATR * multiplier);
    
    // 2. Trailing Profit: Use current ATR (latest data)
    final currentATR = _calculateATR(candles, candles.length - 1, period);
    if (currentATR == null) {
        return StrategyResult(cutLossPrice: cutLoss, equation: 'Cut Loss: ${cutLoss.toStringAsFixed(2)}\nError calculating Trailing ATR');
    }
    
    double highestClose = 0.0;
    String referenceDesc = '';
    double? trailingStop;
    
    if (entryDate != null) {
        final entryTs = entryDate.millisecondsSinceEpoch / 1000;
        final relevantCandles = candles.where((c) => c.date >= entryTs).toList();
        
        if (relevantCandles.isNotEmpty) {
            highestClose = relevantCandles.map((c) => c.close).reduce(max);
            trailingStop = highestClose - (currentATR * multiplier);
            referenceDesc = 'Highest Close since Entry';
        }
    } else {
        final lookback = period;
        final startIdx = max(0, candles.length - lookback);
        final relevantCandles = candles.sublist(startIdx);
        highestClose = relevantCandles.map((c) => c.close).reduce(max);
        trailingStop = highestClose - (currentATR * multiplier);
        referenceDesc = 'Highest Close (Last $period days)';
    }

    // Build equation string
    final sb = StringBuffer();
    // Show both ATRs if they differ significantly
    if ((cutLossATR - currentATR).abs() > 0.01) {
        sb.writeln('Cut Loss ATR: ${cutLossATR.toStringAsFixed(2)} | Current ATR: ${currentATR.toStringAsFixed(2)}');
    } else {
        sb.writeln('ATR: ${cutLossATR.toStringAsFixed(2)}');
    }
    sb.writeln('Cut Loss: $cutLossRefDesc (${refClose.toStringAsFixed(2)}) - ${multiplier}x ATR = ${cutLoss.toStringAsFixed(2)}');
    if (trailingStop != null) {
        sb.writeln('Trailing: $referenceDesc (${highestClose.toStringAsFixed(2)}) - ${multiplier}x Current ATR = ${trailingStop.toStringAsFixed(2)}');
    }
    
    return StrategyResult(
        cutLossPrice: cutLoss, 
        trailingStopPrice: trailingStop,
        equation: sb.toString(),
    );
  }
}

class EmaStopStrategy implements StopStrategy {
  final int period;

  EmaStopStrategy({this.period = 20});

  @override
  String get name => 'EMA Stop ($period)';

  @override
  StrategyResult calculateStopPrice(List<Candle> candles, {DateTime? entryDate, double? entryPrice}) {
    if (candles.length < period) return StrategyResult(cutLossPrice: 0.0, equation: 'Not enough data');

    final k = 2 / (period + 1);
    
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += candles[i].close;
    }
    double ema = sum / period;

    for (int i = period; i < candles.length; i++) {
      ema = (candles[i].close * k) + (ema * (1 - k));
    }
    
    return StrategyResult(
        cutLossPrice: ema, 
        trailingStopPrice: null, 
        equation: 'Limit: ${ema.toStringAsFixed(2)}\nCalculation: EMA ($period) of Close Prices',
    );
  }

  static List<double?> calculateValidSeries(List<Candle> candles, int period) {
    List<double?> series = List.filled(candles.length, null);
    if (candles.length < period) return series;

    final k = 2 / (period + 1);
    
    double sum = 0;
    for (int i = 0; i < period; i++) {
        sum += candles[i].close;
    }
    double ema = sum / period;
    series[period - 1] = ema;

    for (int i = period; i < candles.length; i++) {
        ema = (candles[i].close * k) + (ema * (1 - k));
        series[i] = ema;
    }
    return series;
  }
}
