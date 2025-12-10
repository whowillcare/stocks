import 'dart:math';
import '../model/stock_data.dart';

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
    
    // === PART 1: Calculate ATR ===
    final currentATR = _calculateATR(candles, candles.length - 1, period);
    if (currentATR == null) {
        return StrategyResult(cutLossPrice: 0.0, equation: 'Error calculating ATR');
    }
    
    // === PART 2: Determine Entry Reference ===
    int cutLossRefIndex = candles.length - 1;
    double refClose = 0.0;
    String cutLossRefDesc = '';
    bool hasEntry = false;

    if (entryPrice != null) {
        refClose = entryPrice;
        cutLossRefDesc = 'Entry via Price';
        hasEntry = true;
        cutLossRefIndex = candles.length - 1;
    } else if (entryDate != null) {
        final eY = entryDate.year;
        final eM = entryDate.month;
        final eD = entryDate.day;
        
        for (int i = 0; i < candles.length; i++) {
            final d = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);
            if (d.year == eY && d.month == eM && d.day == eD) {
                cutLossRefIndex = i;
                refClose = candles[i].close;
                cutLossRefDesc = 'Entry via Close';
                hasEntry = true;
                break;
            }
        }
    }

    if (!hasEntry) {
        // No entry yet - use trading hours logic for reference
        final nowUtc = DateTime.now().toUtc();
        final hour = nowUtc.hour;
        final isTradingHours = hour >= 13 && hour < 22;
        
        cutLossRefIndex = candles.length - 1;
        refClose = candles.last.close;
        cutLossRefDesc = 'Current Close';
        
        if (isTradingHours && candles.length > 1) {
            cutLossRefIndex = candles.length - 2;
            refClose = candles[candles.length - 2].close;
            cutLossRefDesc = 'Prev Close (Trading Hours)';
        }
    }

    // Calculate Cut Loss ATR (historical if entry exists)
    final cutLossATR = _calculateATR(candles,cutLossRefIndex, period) ?? currentATR;
    final cutLoss = refClose - (cutLossATR * multiplier);
    
    // === PART 3: Calculate Trailing Stop ===
    double highestClose = 0.0;
    double? trailingStop;
    
    if (hasEntry && entryDate != null) {
        final entryTs = entryDate.millisecondsSinceEpoch / 1000;
        final relevantCandles = candles.where((c) => c.date >= entryTs).toList();
        
        if (relevantCandles.isNotEmpty) {
            highestClose = relevantCandles.map((c) => c.close).reduce(max);
            trailingStop = highestClose - (currentATR * multiplier);
        }
    } else {
        final lookback = period;
        final startIdx = max(0, candles.length - lookback);
        final relevantCandles = candles.sublist(startIdx);
        highestClose = relevantCandles.map((c) => c.close).reduce(max);
        trailingStop = highestClose - (currentATR * multiplier);
    }

    // === PART 4: Post-Entry Analysis (if entry exists) ===
    PostEntryAnalysis? postEntry;
    if (hasEntry && entryDate != null && entryPrice != null) {
        // Calculate EMA20 for post-entry check
        final ema20Series = EmaStopStrategy.calculateValidSeries(candles, 20);
        final ema20 = ema20Series.last ?? candles.last.close;
        
        // Import TrendAnalyzer would create circular dependency, so inline basic check
        final entryTs = entryDate.millisecondsSinceEpoch ~/ 1000;
        int entryIndex = -1;
        for (int i = 0; i < candles.length; i++) {
            if (candles[i].date >= entryTs) {
                entryIndex = i;
                break;
            }
        }
        
        if (entryIndex != -1) {
            final daysHeld = candles.length - 1 - entryIndex;
            final currentPrice = candles.last.close;
            final aboveEma = currentPrice > ema20;
            
            double lowestLowSinceEntry = double.infinity;
            for (int i = entryIndex; i < candles.length; i++) {
                lowestLowSinceEntry = min(lowestLowSinceEntry, candles[i].low);
            }
            
            final structureBreakLevel = entryPrice - (1.5 * currentATR);
            final structureIntact = lowestLowSinceEntry > structureBreakLevel;
            
            TradeState state;
            String note;
            
            if (daysHeld < 3) {
                state = TradeState.waitingConfirmation;
                note = 'Day $daysHeld/3-7: Waiting confirmation';
            } else if (!structureIntact) {
                state = TradeState.failed;
                note = 'Structure broken';
            } else if (!aboveEma && daysHeld >= 7) {
                state = TradeState.failed;
                note = 'Failed to hold above EMA20';
            } else if (aboveEma && structureIntact && daysHeld >= 3) {
                state = TradeState.confirmed;
                note = 'Confirmed ($daysHeld days)';
            } else {
                state = TradeState.waitingConfirmation;
                note = 'Day $daysHeld: Monitoring';
            }
            
            postEntry = PostEntryAnalysis(
                state: state,
                daysHeld: daysHeld,
                structureIntact: structureIntact,
                aboveKeyEma: aboveEma,
                note: note,
            );
        }
    }
    
    // === PART 5: Profit Management (Breakeven & Targets) ===
    bool moveToBreakeven = false;
    double? partialProfitTarget;
    
    if (hasEntry && entryPrice != null) {
        final currentPrice = candles.last.close;
        final riskAmount = (entryPrice - cutLoss).abs();
        final currentGain = currentPrice - entryPrice;
        final rMultiple = riskAmount > 0 ? currentGain / riskAmount : 0;
        
        // Move to breakeven if > 1R profit
        if (rMultiple >= 1.0) {
            moveToBreakeven = true;
        }
        
        // Set partial profit target at 2R
        if (rMultiple < 2.0) {
            partialProfitTarget = entryPrice + (2.0 * riskAmount);
        }
    }
    
    // === PART 6: Entry Validation (Pre-Entry Analysis) ===
    bool canEnter = true;
    String entryReason = '';
    bool breakoutDetected = false;
    
    if (!hasEntry) {
        final currentPrice = candles.last.close;
        
        // Check breakout
        if (candles.length >= 21) {
            double highestPrev = double.negativeInfinity;
            for (int i = max(0, candles.length - 21); i < candles.length - 1; i++) {
                highestPrev = max(highestPrev, candles[i].close);
            }
            breakoutDetected = currentPrice > highestPrev;
        }
        
        // Basic EMA check for entry
        final ema20Series = EmaStopStrategy.calculateValidSeries(candles, 20);
        final ema20 = ema20Series.last;
        
        if (ema20 != null) {
            final distFromEma = (currentPrice - ema20) / currentATR;
            
            if (distFromEma > 1.0) {
                canEnter = false;
                entryReason = 'Too far above EMA20 (chasing)';
            } else if (distFromEma < -0.5) {
                canEnter = false;
                entryReason = 'Price below EMA20 (weak structure)';
            } else {
                canEnter = true;
                entryReason = breakoutDetected ? 'Breakout + Good position' : 'Within safe entry range';
            }
        }
    }
    
    // === PART 7: Build Equation ===
    final sb = StringBuffer();
    if ((cutLossATR - currentATR).abs() > 0.01) {
        sb.writeln('Entry ATR: ${cutLossATR.toStringAsFixed(2)} | Current ATR: ${currentATR.toStringAsFixed(2)}');
    } else {
        sb.writeln('ATR: ${currentATR.toStringAsFixed(2)}');
    }
    
    sb.writeln('Cut Loss: $cutLossRefDesc (${refClose.toStringAsFixed(2)}) - ${multiplier}x ATR = ${cutLoss.toStringAsFixed(2)}');
    
    if (trailingStop != null) {
        sb.writeln('Trailing: Highest Close (${highestClose.toStringAsFixed(2)}) - ${multiplier}x ATR = ${trailingStop.toStringAsFixed(2)}');
    }
    
    if (postEntry != null) {
        sb.writeln('Status: ${postEntry.note}');
    }
    
    if (moveToBreakeven) {
        sb.writeln('💡 Move stop to breakeven (${entryPrice!.toStringAsFixed(2)})');
    }
    
    if (partialProfitTarget != null) {
        sb.writeln('🎯 Partial profit target: ${partialProfitTarget.toStringAsFixed(2)} (2R)');
    }
    
    if (!hasEntry && !canEnter) {
        sb.writeln('⚠️  Entry: $entryReason');
    } else if (!hasEntry && breakoutDetected) {
        sb.writeln('✅ Breakout detected');
    }
    
    return StrategyResult(
        cutLossPrice: cutLoss,
        trailingStopPrice: trailingStop,
        equation: sb.toString(),
        postEntry: postEntry,
        canEnter: canEnter,
        entryReason: entryReason,
        breakoutDetected: breakoutDetected,
        moveToBreakeven: moveToBreakeven,
        partialProfitTarget: partialProfitTarget,
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
