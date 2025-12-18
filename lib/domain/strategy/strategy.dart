// strategy.dart
// ATR-based stop strategies with entry validation, trailing stop lock,
// and profit management integrated with TrendAnalyzer

import 'dart:math';
import '../model/stock_data.dart';
import '../analysis/trend_analyzer.dart';
import '../analysis/monitor_engine.dart';

abstract class StopStrategy {
  String get name;
  StrategyResult calculateStopPrice(
    List<Candle> candles, {
    DateTime? entryDate,
    double? entryPrice,
  });
}

class AtrStopStrategy implements StopStrategy {
  final int period;
  final double stopMultiplier; // k for ISL (initial stop loss)
  final double trailMultiplier; // k for trailing stop

  AtrStopStrategy({
    this.period = 14,
    this.stopMultiplier = 2.0,
    this.trailMultiplier = 3.0,
  });

  @override
  String get name =>
      'ATR Strategy ($period, ISL:${stopMultiplier}x, Trail:${trailMultiplier}x)';

  @override
  StrategyResult calculateStopPrice(
    List<Candle> candles, {
    DateTime? entryDate,
    double? entryPrice,
  }) {
    if (candles.length < period + 1) {
      return StrategyResult(cutLossPrice: 0.0, equation: 'Not enough data');
    }

    final closes = candles.map((c) => c.close).toList();
    final atrSeries = Indicator.atr(candles, period: period);
    final ema20Series = Indicator.ema(closes, 20);
    final ema50Series = Indicator.ema(closes, 50);

    final last = candles.length - 1;
    final latestAtr = atrSeries[last];
    final latestEma20 = ema20Series[last];
    final latestEma50 = ema50Series[last];
    final priceNow = closes[last];

    if (latestAtr.isNaN) {
      return StrategyResult(
        cutLossPrice: 0.0,
        equation: 'Error calculating ATR',
      );
    }

    // === Determine Entry Reference ===
    bool hasEntry = false;
    int entryIndex = -1;
    double entryRef = priceNow;
    String refDesc = 'Current Close';

    if (entryDate != null) {
      final eY = entryDate.year;
      final eM = entryDate.month;
      final eD = entryDate.day;
      for (int i = 0; i < candles.length; i++) {
        final d = DateTime.fromMillisecondsSinceEpoch(candles[i].date * 1000);
        if (d.year == eY && d.month == eM && d.day == eD) {
          entryIndex = i;
          if (entryPrice != null) {
            entryRef = entryPrice;
            refDesc = 'Entry Price';
            hasEntry = true;
          } else {
            entryRef = candles[i].close;
            refDesc = 'Entry Close';
            hasEntry = true;
          }
          break;
        }
      }
    }

    if (!hasEntry) {
      // Use trading hours logic
      final nowUtc = DateTime.now().toUtc();
      final hour = nowUtc.hour;
      final isTradingHours = hour >= 13 && hour < 22;

      if (isTradingHours && candles.length > 1) {
        entryRef = candles[candles.length - 2].close;
        refDesc = 'Prev Close (Trading Hours)';
      }
    }

    // === Initial Stop Loss (ISL) ===
    final atrAtEntry = hasEntry && entryIndex >= period
        ? atrSeries[entryIndex]
        : latestAtr;
    final minAtr = min(atrAtEntry, latestAtr);
    final initialStop =
        entryRef - stopMultiplier * (atrAtEntry.isNaN ? latestAtr : atrAtEntry);

    // === Trailing Stop (never decreases) ===
    double highestCloseSinceEntry = priceNow;
    String highestCloseDesc = 'Current Close';
    if (hasEntry && entryIndex >= 0) {
      highestCloseSinceEntry = 0.0;
      for (int i = entryIndex; i <= last; i++) {
        if (closes[i] >= highestCloseSinceEntry) {
          highestCloseSinceEntry = closes[i];
          highestCloseDesc = '@[${candles[i].dateStr}]';
        }
      }
    } else {
      // Use rolling 60-day highest
      highestCloseSinceEntry = Indicator.rollingHighestClose(closes, last, 60);
      highestCloseDesc = 'Rolling 60-day High';
    }

    final trailingCalc = highestCloseSinceEntry - trailMultiplier * minAtr;
    // Trailing stop = max(initialStop, calculated trailing) - NEVER moves down
    final trailingStop = max(initialStop, trailingCalc);

    // === Entry Validation (Pre-Entry Analysis) ===
    bool canEnter = true;
    String entryReason = '';
    bool breakoutDetected = false;

    if (!hasEntry) {
      // Check breakout (20-day)
      if (candles.length >= 21) {
        final prevHigh = Indicator.rollingHighestClose(closes, last - 1, 20);
        breakoutDetected = !prevHigh.isNaN && priceNow > prevHigh;
      }

      // Entry zone validation
      final entryMin = latestEma20 - 0.5 * latestAtr;
      final entryMax = latestEma20 + 0.2 * latestAtr;

      // Volume check
      final volumes = candles.map((c) => c.volume.toDouble()).toList();
      final vol20 = Indicator.rollingAvgVolume(volumes, last, 20);
      final volConfirm = volumes[last] >= vol20 * 1.2;

      // Trend score
      final trendScore = calcTrendScore(candles);

      if (trendScore < 1) {
        canEnter = false;
        entryReason = 'Weak trend (score: $trendScore)';
      } else if (!volConfirm) {
        canEnter = false;
        entryReason = 'Volume below average';
      } else if (priceNow > entryMax + latestAtr) {
        canEnter = false;
        entryReason = 'Chasing (too far above EMA20)';
      } else if (priceNow < entryMin - latestAtr) {
        canEnter = false;
        entryReason = 'Price too far below EMA20';
      } else if (priceNow >= entryMin && priceNow <= entryMax) {
        canEnter = true;
        entryReason = breakoutDetected
            ? 'Breakout + Good zone'
            : 'Good entry zone';
      } else {
        canEnter = true;
        entryReason = 'Acceptable (outside optimal zone)';
      }
      if (canEnter) {
        entryReason = '$entryReason at Range($entryMin, $entryMax)';
      }
    }

    // === Post-Entry Analysis ===
    PostEntryAnalysis? postEntry;
    if (hasEntry && entryPrice != null) {
      final daysHeld = entryIndex >= 0 ? (last - entryIndex) : 0;
      final aboveEma = priceNow > latestEma20;

      // Structure check: lowest low since entry
      double lowestLowSinceEntry = double.infinity;
      if (entryIndex >= 0) {
        for (int i = entryIndex; i <= last; i++) {
          lowestLowSinceEntry = min(lowestLowSinceEntry, candles[i].low);
        }
      }

      final structureBreakLevel = entryPrice - (1.5 * latestAtr);
      final structureIntact = lowestLowSinceEntry > structureBreakLevel;

      // Post-entry confirmation since entry
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

    // === Monitor Engine Analysis (when entered) ===
    MonitorResult? monitorResult;
    if (hasEntry && entryIndex >= 0 && entryIndex < candles.length) {
      // Get data Since entry for monitoring
      final postEntryCandles = candles.sublist(entryIndex);
      if (postEntryCandles.length >= 2) {
        final monitorCloses = postEntryCandles.map((c) => c.close).toList();
        final monitorHighs = postEntryCandles.map((c) => c.high).toList();
        final monitorLows = postEntryCandles.map((c) => c.low).toList();
        final monitorVols = postEntryCandles
            .map((c) => c.volume.toDouble())
            .toList();

        final engine = MonitorEngine(
          closes: monitorCloses,
          highs: monitorHighs,
          lows: monitorLows,
          volumes: monitorVols,
        );
        monitorResult = engine.evaluate();
      }
    }

    // === Profit Management ===
    bool moveToBreakeven = false;
    double? partialProfitTarget;

    // === Build Equation / Notes ===
    final sb = StringBuffer();
    sb.writeln(
      'ATR: ${latestAtr.toStringAsFixed(2)} | Min ATR: ${minAtr.toStringAsFixed(2)} | ATR at Entry: ${atrAtEntry.toStringAsFixed(2)}',
    );
    sb.writeln(
      'EMA20: ${latestEma20.toStringAsFixed(2)} | EMA50: ${latestEma50.toStringAsFixed(2)}',
    );
    sb.writeln(
      'ISL: $refDesc (${entryRef.toStringAsFixed(2)}) - ${stopMultiplier}x ATR(${atrAtEntry.toStringAsFixed(2)}) = ${initialStop.toStringAsFixed(2)}',
    );
    sb.writeln(
      'Trailing: Highest ($highestCloseDesc ${highestCloseSinceEntry.toStringAsFixed(2)}) - ${trailMultiplier}x ATR(${minAtr.toStringAsFixed(2)}) = ${trailingStop.toStringAsFixed(2)}',
    );

    if (postEntry != null) {
      sb.writeln('Status: ${postEntry.note}');
    }

    if (hasEntry && entryPrice != null) {
      if (trailingStop > initialStop) {
        sb.writeln(
          'Trailing Stop (${trailingStop.toStringAsFixed(2)}) is above initial stop (${initialStop.toStringAsFixed(2)})',
        );
      }
      final riskAmount = (entryPrice - initialStop).abs();
      final currentGain = priceNow - entryPrice;
      final rMultiple = riskAmount > 0 ? currentGain / riskAmount : 0;

      // Move to breakeven if > 1R profit
      if (rMultiple >= 1.0) {
        moveToBreakeven = true;
        sb.writeln(
          'riskAmount: $riskAmount >0 and currentGain: $currentGain💡 Move stop to breakeven (${entryPrice.toStringAsFixed(2)})',
        );
      }

      // Partial profit target at 2R
      if (rMultiple < 2.0) {
        partialProfitTarget = entryPrice + (2.0 * riskAmount);
        sb.writeln(
          '🎯 In order to make profit: ${partialProfitTarget.toStringAsFixed(2)} (eP(${entryPrice.toStringAsFixed(2)}) + 2R(${riskAmount.toStringAsFixed(2)}))',
        );
      }
    }

    if (!hasEntry) {
      if (canEnter) {
        sb.writeln('✅ $entryReason');
      } else {
        sb.writeln('⚠️ $entryReason');
      }
      if (breakoutDetected) {
        sb.writeln('📈 Breakout detected');
      }
    }

    return StrategyResult(
      cutLossPrice: initialStop,
      trailingStopPrice: trailingStop,
      equation: sb.toString(),
      postEntry: postEntry,
      monitorResult: monitorResult,
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
  StrategyResult calculateStopPrice(
    List<Candle> candles, {
    DateTime? entryDate,
    double? entryPrice,
  }) {
    if (candles.length < period) {
      return StrategyResult(cutLossPrice: 0.0, equation: 'Not enough data');
    }

    final closes = candles.map((c) => c.close).toList();
    final emaSeries = Indicator.ema(closes, period);
    final ema = emaSeries.last;

    if (ema.isNaN) {
      return StrategyResult(
        cutLossPrice: 0.0,
        equation: 'Error calculating EMA',
      );
    }

    return StrategyResult(
      cutLossPrice: ema,
      trailingStopPrice: null,
      equation:
          'Limit: ${ema.toStringAsFixed(2)}\nCalculation: EMA ($period) of Close Prices',
    );
  }

  /// Calculate full EMA series for charting
  static List<double?> calculateValidSeries(List<Candle> candles, int period) {
    if (candles.length < period) {
      return List.filled(candles.length, null);
    }

    final closes = candles.map((c) => c.close).toList();
    final emaSeries = Indicator.ema(closes, period);

    return emaSeries.map((v) => v.isNaN ? null : v).toList();
  }
}
