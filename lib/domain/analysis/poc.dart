// flutter_trade_analysis.dart
// Single-file library implementing a full signal engine for
// trend detection, entry-range risk, stops (ATR-based),
// confirmation rules, sideways handling and failure rules.
//
// Usage: import this file into your Flutter app or Dart backend.
// It is written to be pure-Dart so it can run on mobile or server.

import 'dart:math';

// --- Data model ---
class OHLCV {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  OHLCV(this.date, this.open, this.high, this.low, this.close, this.volume);
}

class AnalysisResult {
  final String symbol;
  final DateTime asOf;
  final String trend; // 'uptrend' | 'downtrend' | 'sideways' | 'unknown'
  final int riskLevel; // 0 low - 5 high
  final double entryLow; // suggested safe entry low
  final double entryHigh; // suggested safe entry high
  final double suggestedEntry; // canonical entry price (e.g. close or breakout level)
  final double initialStop; // stop based on entry (entry - k*ATR)
  final double trailingStop; // highestCloseSinceEntry - k*ATR
  final double atr; // latest ATR
  final String note;

  AnalysisResult({
    required this.symbol,
    required this.asOf,
    required this.trend,
    required this.riskLevel,
    required this.entryLow,
    required this.entryHigh,
    required this.suggestedEntry,
    required this.initialStop,
    required this.trailingStop,
    required this.atr,
    required this.note,
  });
}

// --- Technical helpers ---
class Technicals {
  /// Simple Moving Average
  static List<double> sma(List<double> values, int period) {
    final out = List<double>.filled(values.length, double.nan);
    double sum = 0.0;
    for (int i = 0; i < values.length; i++) {
      sum += values[i];
      if (i >= period) sum -= values[i - period];
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  /// Exponential Moving Average (EMA)
  /// alpha = 2/(n+1)
  static List<double> ema(List<double> values, int period) {
    final n = period;
    final alpha = 2.0 / (n + 1);
    final out = List<double>.filled(values.length, double.nan);
    double? prevEma;
    for (int i = 0; i < values.length; i++) {
      double price = values[i];
      if (i < n - 1) {
        // not enough for initial SMA yet
        continue;
      } else if (i == n - 1) {
        // initialize with SMA at period
        final smaWindow = values.sublist(i - (n - 1), i + 1);
        final smaVal = smaWindow.reduce((a, b) => a + b) / n;
        prevEma = smaVal;
        out[i] = prevEma;
      } else {
        prevEma = (price * alpha) + (prevEma! * (1 - alpha));
        out[i] = prevEma;
      }
    }
    return out;
  }

  /// Compute True Range series and ATR (rolling simple SMA of TR or Wilder's EMA if useEwm=true)
  static Map<String, List<double>> trAndAtr(List<OHLCV> bars,
      {int atrPeriod = 14, bool useWilder = false}) {
    final tr = List<double>.filled(bars.length, double.nan);
    final atr = List<double>.filled(bars.length, double.nan);
    for (int i = 0; i < bars.length; i++) {
      final cur = bars[i];
      if (i == 0) {
        tr[i] = cur.high - cur.low;
      } else {
        final prevClose = bars[i - 1].close;
        final a = cur.high - cur.low;
        final b = (cur.high - prevClose).abs();
        final c = (cur.low - prevClose).abs();
        tr[i] = [a, b, c].reduce(max);
      }
    }

    if (!useWilder) {
      // simple moving average ATR
      double sum = 0.0;
      for (int i = 0; i < bars.length; i++) {
        sum += tr[i].isNaN ? 0.0 : tr[i];
        if (i >= atrPeriod) sum -= tr[i - atrPeriod];
        if (i >= atrPeriod - 1) atr[i] = sum / atrPeriod;
      }
    } else {
      // Wilder's smoothing (EMA-like) for ATR
      double? prevAtr;
      for (int i = 0; i < bars.length; i++) {
        if (i < atrPeriod) {
          // accumulate
          double s = 0.0;
          if (i == atrPeriod - 1) {
            for (int j = 0; j <= i; j++) s += tr[j];
            prevAtr = s / atrPeriod;
            atr[i] = prevAtr!;
          }
        } else {
          prevAtr = ((prevAtr ?? 0) * (atrPeriod - 1) + tr[i]) / atrPeriod;
          atr[i] = prevAtr!;
        }
      }
    }

    return {'tr': tr, 'atr': atr};
  }

  /// Highest close in a lookback window ending at index i (inclusive)
  static double rollingHighestClose(List<double> closes, int index, int lookback) {
    final start = max(0, index - (lookback - 1));
    double hi = double.negativeInfinity;
    for (int i = start; i <= index; i++) {
      hi = max(hi, closes[i]);
    }
    return hi.isFinite ? hi : double.nan;
  }

  /// Detect simple higher-highs/higher-lows structure in last N swings
  static bool isHigherHighsHigherLows(List<OHLCV> bars, {int lookback = 20}) {
    if (bars.length < 5) return false;
    // We'll detect simple swing points via local peaks/troughs
    final highs = bars.map((b) => b.high).toList();
    final lows = bars.map((b) => b.low).toList();

    List<int> peakIdx = [];
    List<int> troughIdx = [];
    final n = bars.length;
    for (int i = 1; i < n - 1; i++) {
      if (highs[i] > highs[i - 1] && highs[i] > highs[i + 1]) peakIdx.add(i);
      if (lows[i] < lows[i - 1] && lows[i] < lows[i + 1]) troughIdx.add(i);
    }
    if (peakIdx.length < 2 || troughIdx.length < 2) return false;
    // take last two peaks and troughs
    final lastPeaks = peakIdx.takeLast(3);
    final lastTroughs = troughIdx.takeLast(3);

    // ensure sequence of increasing peaks and troughs
    bool peaksUp = true;
    for (int i = 1; i < lastPeaks.length; i++) {
      if (bars[lastPeaks[i]].high <= bars[lastPeaks[i - 1]].high) peaksUp = false;
    }
    bool troughsUp = true;
    for (int i = 1; i < lastTroughs.length; i++) {
      if (bars[lastTroughs[i]].low <= bars[lastTroughs[i - 1]].low) troughsUp = false;
    }
    return peaksUp && troughsUp;
  }
}

// convenience extension
extension _ListTakeLast<E> on List<E> {
  List<E> takeLast(int n) => sublist(max(0, length - n));
}

// --- Strategy engine ---
class StrategyEngine {
  final String symbol;
  final List<OHLCV> bars; // must be sorted ascending by date
  final int atrPeriod;
  final double entryAtrFactor; // multiplier for entry safe range
  final double stopAtrFactor; // multiplier for initial stop
  final double trailAtrFactor; // multiplier for trailing stop
  final int sidewaysWaitDays; // how many days to treat sideways before failing

  StrategyEngine({
    required this.symbol,
    required this.bars,
    this.atrPeriod = 14,
    this.entryAtrFactor = 0.5,
    this.stopAtrFactor = 2.0,
    this.trailAtrFactor = 3.0,
    this.sidewaysWaitDays = 10,
  }) {
    if (bars.isEmpty) throw ArgumentError('bars cannot be empty');
  }

  /// Core analysis method
  AnalysisResult analyze() {
    final closes = bars.map((b) => b.close).toList();
    final highs = bars.map((b) => b.high).toList();
    final lows = bars.map((b) => b.low).toList();

    // compute ATR
    final trAtr = Technicals.trAndAtr(bars, atrPeriod: atrPeriod, useWilder: true);
    final atrSeries = trAtr['atr']!;
    final latestIdx = bars.length - 1;
    final latestAtr = atrSeries[latestIdx];

    // compute EMAs
    final ema20 = Technicals.ema(closes, 20);
    final ema50 = Technicals.ema(closes, 50);
    final latestEma20 = ema20[latestIdx];
    final latestEma50 = ema50[latestIdx];

    // trend detection
    String trend = 'unknown';
    if (!latestEma20.isNaN && !latestEma50.isNaN) {
      if (closes[latestIdx] > latestEma20 && latestEma20 > latestEma50) trend = 'uptrend';
      else if (closes[latestIdx] < latestEma20 && latestEma20 < latestEma50) trend = 'downtrend';
      else {
        trend = 'sideways';
      }
    }

    // safe entry range around ema20
    final safeLow = (latestEma20 - entryAtrFactor * latestAtr);
    final safeHigh = (latestEma20 + 0.2 * latestAtr);

    // suggested entry default: close or breakout
    double suggestedEntry = closes[latestIdx];

    // check for 20-day breakout
    final prev20High = Technicals.rollingHighestClose(closes, latestIdx - 1, 20);
    bool breakout20 = !prev20High.isNaN && closes[latestIdx] > prev20High;
    if (breakout20) {
      suggestedEntry = max(suggestedEntry, prev20High);
    }

    // risk level scoring
    int riskScore = 0;
    // distance from ema20 normalized by ATR
    final distFromEma = (closes[latestIdx] - latestEma20) / latestAtr;
    if (distFromEma > 1.0) riskScore += 3; // chasing
    else if (distFromEma > 0.5) riskScore += 2;
    else if (distFromEma > 0.1) riskScore += 1;
    else if (distFromEma.abs() < 0.1) riskScore += 0; // near ideal
    else if (distFromEma < -0.5) riskScore += 3; // falling too much

    // volume confirmation: naive check (compare last vol to 20-day avg)
    double vol20 = 0.0;
    if (bars.length >= 20) {
      final last20Vol = bars.sublist(bars.length - 20).map((b) => b.volume).toList();
      vol20 = last20Vol.reduce((a, b) => a + b) / last20Vol.length;
      if (bars[latestIdx].volume > vol20 * 1.5) riskScore = max(0, riskScore - 1); // good volume
    }

    // compute initial stop based on entry (entry - stopAtrFactor*ATR)
    final initialStop = suggestedEntry - stopAtrFactor * latestAtr;

    // compute trailing stop using highest close since potential entry (we'll use 60-day highest)
    final highestClose60 = Technicals.rollingHighestClose(closes, latestIdx, 60);
    final trailingStop = highestClose60 - trailAtrFactor * latestAtr;

    // Confirmation checks (HH+HL optional)
    final hasStructure = Technicals.isHigherHighsHigherLows(bars, lookback: 30);
    final noteBuffer = StringBuffer();
    noteBuffer.writeln('atr=${latestAtr.toStringAsFixed(4)}, ema20=${latestEma20.isNaN ? 'na' : latestEma20.toStringAsFixed(4)}');
    noteBuffer.writeln('trend=$trend, breakout20=$breakout20, HH+HL=$hasStructure');

    // Sideways handling: how long to wait
    // if sideways, count days since last significant move or breakout
    int daysSinceBreakout = 9999;
    if (!prev20High.isNaN) {
      // find index when price first exceeded prev20High in lookback
      daysSinceBreakout = 9999;
      for (int i = max(0, latestIdx - 60); i <= latestIdx; i++) {
        if (closes[i] > prev20High) {
          daysSinceBreakout = latestIdx - i;
          break;
        }
      }
    }

    // Final advice heuristic
    String advice;
    if (trend == 'uptrend') {
      if (riskScore >= 4) {
        advice = 'High risk: avoid entry or reduce size';
      } else {
        if (closes[latestIdx] >= safeLow && closes[latestIdx] <= safeHigh) {
          advice = 'Good entry zone (trend confirmed)';
        } else if (closes[latestIdx] > safeHigh) {
          advice = 'Price slightly above safe zone; consider wait or partial position';
        } else {
          advice = 'Price below EMA20: potential dip entry if stop is acceptable';
        }
      }
    } else if (trend == 'sideways') {
      advice = 'Market sideways: wait for breakout or reduced ATR; or use small size and tight stops';
    } else if (trend == 'downtrend') {
      advice = 'Downtrend: avoid long entries';
    } else {
      advice = 'Insufficient data to advise';
    }

    final res = AnalysisResult(
      symbol: symbol,
      asOf: bars.last.date,
      trend: trend,
      riskLevel: riskScore,
      entryLow: safeLow.isNaN ? double.nan : safeLow,
      entryHigh: safeHigh.isNaN ? double.nan : safeHigh,
      suggestedEntry: suggestedEntry,
      initialStop: initialStop,
      trailingStop: trailingStop,
      atr: latestAtr,
      note: noteBuffer.toString() + '\n' + advice,
    );

    return res;
  }

  /// Helper to compute 'how long to wait in sideways' and fail rules
  Map<String, dynamic> sidewaysPlan() {
    // This method inspects bars and returns guidance on wait days, when to fold
    final closes = bars.map((b) => b.close).toList();
    final latestIdx = bars.length - 1;
    final prev20High = Technicals.rollingHighestClose(closes, latestIdx - 1, 20);

    int daysSinceHigh = 0;
    double lastHigh = closes[0];
    for (int i = latestIdx; i >= 0; i--) {
      if (bars[i].high >= prev20High) {
        daysSinceHigh = latestIdx - i;
        lastHigh = bars[i].high;
        break;
      }
    }

    // default plan
    return {
      'recommendedWaitDays': sidewaysWaitDays,
      'daysSinceBreakout': daysSinceHigh,
      'failIfNoHHDays': sidewaysWaitDays,
      'actionIfFail': 'exit or reduce position; tighten stops to 1*ATR and reassess'
    };
  }
}

// --- Example usage ---
// (In your Flutter app you would fetch OHLCV from provider then pass to StrategyEngine)

/*
Example:

final bars = <OHLCV>[ ... ]; // load historical daily bars sorted ascending
final engine = StrategyEngine(symbol: 'CRML', bars: bars);
final analysis = engine.analyze();
print('Trend: ${analysis.trend}');
print('RiskLevel: ${analysis.riskLevel}');
print('Entry range: ${analysis.entryLow} - ${analysis.entryHigh}');
print('Suggested entry: ${analysis.suggestedEntry}');
print('Initial stop: ${analysis.initialStop}');
print('Trailing stop (3xATR): ${analysis.trailingStop}');
print('Note: ${analysis.note}');

// You can call engine.sidewaysPlan() to get how long to wait and fail rules.
*/
