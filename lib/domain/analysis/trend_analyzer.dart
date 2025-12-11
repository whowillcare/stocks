// trend_analyzer.dart
// Pure-Dart implementation of trend detection, scoring, structure signals
// Ported from POC with Indicator class, calcTrendScore, and StrategyEngine

import 'dart:math';
import '../model/stock_data.dart';

// --- Technical Indicator Helpers ---
class Indicator {
  /// EMA (period N) - returns list where index i corresponds to same index in closes
  static List<double> ema(List<double> closes, int period) {
    final n = period;
    final alpha = 2.0 / (n + 1);
    final out = List<double>.filled(closes.length, double.nan);
    double? prev;
    for (int i = 0; i < closes.length; i++) {
      final price = closes[i];
      if (i < n - 1) {
        continue; // not enough points
      } else if (i == n - 1) {
        final sum = closes.sublist(0, n).reduce((a, b) => a + b);
        prev = sum / n;
        out[i] = prev;
      } else {
        prev = price * alpha + prev! * (1 - alpha);
        out[i] = prev;
      }
    }
    return out;
  }

  /// True Range series from candles
  static List<double> tr(List<Candle> bars) {
    final t = List<double>.filled(bars.length, double.nan);
    for (int i = 0; i < bars.length; i++) {
      if (i == 0) {
        t[i] = bars[i].high - bars[i].low;
      } else {
        final prevClose = bars[i - 1].close;
        final a = bars[i].high - bars[i].low;
        final b = (bars[i].high - prevClose).abs();
        final c = (bars[i].low - prevClose).abs();
        t[i] = max(a, max(b, c));
      }
    }
    return t;
  }

  /// ATR (Wilder smoothing style)
  static List<double> atr(List<Candle> bars, {int period = 14}) {
    final t = tr(bars);
    final out = List<double>.filled(bars.length, double.nan);
    double? prevAtr;
    for (int i = 0; i < bars.length; i++) {
      if (i < period - 1) continue;
      if (i == period - 1) {
        final sum = t.sublist(0, period).reduce((a, b) => a + b);
        prevAtr = sum / period;
        out[i] = prevAtr;
      } else {
        // Wilder smoothing
        prevAtr = ((prevAtr! * (period - 1)) + t[i]) / period;
        out[i] = prevAtr;
      }
    }
    return out;
  }

  /// Highest close in lookback window ending at idx (inclusive)
  static double rollingHighestClose(List<double> closes, int idx, int lookback) {
    final start = max(0, idx - (lookback - 1));
    double hi = double.negativeInfinity;
    for (int i = start; i <= idx; i++) hi = max(hi, closes[i]);
    return hi.isFinite ? hi : double.nan;
  }

  /// Rolling average volume
  static double rollingAvgVolume(List<double> vols, int idx, int lookback) {
    final start = max(0, idx - (lookback - 1));
    double sum = 0;
    int cnt = 0;
    for (int i = start; i <= idx; i++) {
      sum += vols[i];
      cnt++;
    }
    return cnt > 0 ? sum / cnt : double.nan;
  }
}

// --- Swing Point Detection ---
List<int> _localPeaks(List<double> arr) {
  final idx = <int>[];
  for (int i = 1; i < arr.length - 1; i++) {
    if (arr[i] > arr[i - 1] && arr[i] > arr[i + 1]) idx.add(i);
  }
  return idx;
}

List<int> _localTroughs(List<double> arr) {
  final idx = <int>[];
  for (int i = 1; i < arr.length - 1; i++) {
    if (arr[i] < arr[i - 1] && arr[i] < arr[i + 1]) idx.add(i);
  }
  return idx;
}

/// Check HH/HL/LH/LL structure signals over last lookback days
Map<String, bool> structureSignals(List<Candle> bars, {int lookback = 14}) {
  if (bars.length < 5) return {'HH': false, 'HL': false, 'LH': false, 'LL': false};
  final sliceStart = max(0, bars.length - lookback);
  final sub = bars.sublist(sliceStart);
  final highs = sub.map((b) => b.high).toList();
  final lows = sub.map((b) => b.low).toList();
  final pk = _localPeaks(highs).map((i) => i + sliceStart).toList();
  final tr = _localTroughs(lows).map((i) => i + sliceStart).toList();
  
  bool hh = false, hl = false, lh = false, ll = false;
  
  if (pk.length >= 2) {
    // last two peaks increasing?
    final last = pk._takeLast(3);
    bool peaksUp = true;
    for (int i = 1; i < last.length; i++) {
      if (bars[last[i]].high <= bars[last[i - 1]].high) peaksUp = false;
    }
    if (peaksUp) hh = true;
    
    bool peaksDown = true;
    for (int i = 1; i < last.length; i++) {
      if (bars[last[i]].high >= bars[last[i - 1]].high) peaksDown = false;
    }
    if (peaksDown) lh = true;
  }
  
  if (tr.length >= 2) {
    final last = tr._takeLast(3);
    bool troughsUp = true;
    for (int i = 1; i < last.length; i++) {
      if (bars[last[i]].low <= bars[last[i - 1]].low) troughsUp = false;
    }
    if (troughsUp) hl = true;
    
    bool troughsDown = true;
    for (int i = 1; i < last.length; i++) {
      if (bars[last[i]].low >= bars[last[i - 1]].low) troughsDown = false;
    }
    if (troughsDown) ll = true;
  }
  
  return {'HH': hh, 'HL': hl, 'LH': lh, 'LL': ll};
}

extension _TakeLast<E> on List<E> {
  List<E> _takeLast(int n) => sublist(max(0, length - n));
}

/// Calculate TrendScore (balanced: positive = uptrend signals, negative = downtrend)
int calcTrendScore(List<Candle> bars, {int lookback = 14}) {
  final closes = bars.map((b) => b.close).toList();
  final sig = structureSignals(bars, lookback: lookback);
  int score = 0;
  
  if (sig['HH'] == true) score += 1;
  if (sig['HL'] == true) score += 1;
  if (sig['LH'] == true) score -= 1;
  if (sig['LL'] == true) score -= 1;
  
  // EMA confirmations (20,50)
  final ema20 = Indicator.ema(closes, 20);
  final ema50 = Indicator.ema(closes, 50);
  final last = closes.length - 1;
  
  if (!ema20[last].isNaN && !ema50[last].isNaN) {
    if (closes[last] > ema20[last]) score += 1;
    else score -= 1;
    
    if (ema20[last] > ema50[last]) score += 1;
    else score -= 1;
    
    // slope check (ema20 slope over 3 periods)
    final prevIdx = max(0, last - 3);
    if (!ema20[prevIdx].isNaN && !ema20[last].isNaN) {
      if (ema20[last] > ema20[prevIdx]) score += 1;
      else score -= 1;
    }
  }
  
  return score;
}

// --- Analysis Result ---
class TrendAnalysisResult {
  final int trendScore;
  final String trend;      // 'uptrend' | 'downtrend' | 'sideways'
  final double atr;
  final double ema20;
  final double ema50;
  final double entryMin;   // safe entry low (EMA20 - 0.5*ATR)
  final double entryMax;   // safe entry high (EMA20 + 0.2*ATR)
  final String entryAdvice;
  final bool volumeConfirm;
  final bool breakoutDetected;
  final Map<String, bool> structure; // {HH, HL, LH, LL}
  final List<String> notes;
  
  TrendAnalysisResult({
    required this.trendScore,
    required this.trend,
    required this.atr,
    required this.ema20,
    required this.ema50,
    required this.entryMin,
    required this.entryMax,
    required this.entryAdvice,
    required this.volumeConfirm,
    required this.breakoutDetected,
    required this.structure,
    required this.notes,
  });
  
  /// Convenience: is safe entry based on trend and position
  bool get isSafeEntry => entryAdvice.contains('Good') || entryAdvice.contains('good');
}

// --- Trend Analyzer ---
class TrendAnalyzer {
  final int atrPeriod;
  final double entryAtrFactor;  // 0.5 = EMA20 - 0.5*ATR
  final double entryUpperFactor; // 0.2 = EMA20 + 0.2*ATR
  final int breakoutLookback;
  final int volLookback;
  
  TrendAnalyzer({
    this.atrPeriod = 14,
    this.entryAtrFactor = 0.5,
    this.entryUpperFactor = 0.2,
    this.breakoutLookback = 20,
    this.volLookback = 20,
  });
  
  TrendAnalysisResult analyze(List<Candle> candles) {
    if (candles.isEmpty || candles.length < atrPeriod + 1) {
      return TrendAnalysisResult(
        trendScore: 0,
        trend: 'unknown',
        atr: 0,
        ema20: 0,
        ema50: 0,
        entryMin: 0,
        entryMax: 0,
        entryAdvice: 'Insufficient data',
        volumeConfirm: false,
        breakoutDetected: false,
        structure: {'HH': false, 'HL': false, 'LH': false, 'LL': false},
        notes: ['Not enough data to analyze'],
      );
    }
    
    final closes = candles.map((b) => b.close).toList();
    final volumes = candles.map((b) => b.volume.toDouble()).toList();
    final atrSeries = Indicator.atr(candles, period: atrPeriod);
    final ema20 = Indicator.ema(closes, 20);
    final ema50 = Indicator.ema(closes, 50);
    final last = candles.length - 1;
    
    final latestAtr = atrSeries[last];
    final latestEma20 = ema20[last];
    final latestEma50 = ema50[last];
    
    // Calculate trend score
    final ts = calcTrendScore(candles);
    
    // Structure signals
    final structureSig = structureSignals(candles);
    
    // Safe entry range
    final entryMin = latestEma20 - entryAtrFactor * latestAtr;
    final entryMax = latestEma20 + entryUpperFactor * latestAtr;
    
    final priceNow = closes[last];
    
    // Volume check
    final vol20 = Indicator.rollingAvgVolume(volumes, last, volLookback);
    final volConfirm = volumes[last] >= vol20 * 1.2;
    
    // Breakout check
    final prevHigh = Indicator.rollingHighestClose(closes, last - 1, breakoutLookback);
    bool breakout = !prevHigh.isNaN && priceNow > prevHigh;
    
    // Entry decision
    String entryAdvice = 'No opinion';
    if (ts >= 3 && priceNow >= entryMin && priceNow <= entryMax && volConfirm) {
      entryAdvice = 'Good entry zone';
    } else if (ts >= 2 && priceNow <= entryMin) {
      entryAdvice = 'Potential dip; entry with smaller size';
    } else if (ts < 1) {
      entryAdvice = 'Avoid entry: weak trend';
    } else if (!volConfirm) {
      entryAdvice = 'Caution: volume below average';
    } else if (priceNow > entryMax) {
      entryAdvice = 'Wait or small position (chasing)';
    } else {
      entryAdvice = 'Wait or small position';
    }
    
    // Trend classification
    String trend;
    if (ts >= 3) {
      trend = 'uptrend';
    } else if (ts <= -3) {
      trend = 'downtrend';
    } else {
      trend = 'sideways';
    }
    
    // Build notes
    final notes = <String>[];
    notes.add('ATR=${latestAtr.toStringAsFixed(2)}, EMA20=${latestEma20.toStringAsFixed(2)}, EMA50=${latestEma50.toStringAsFixed(2)}');
    notes.add('TrendScore=$ts, breakout=${breakout ? 'yes' : 'no'}, volConfirm=${volConfirm ? 'yes' : 'no'}');
    
    final structStr = [
      if (structureSig['HH'] == true) 'HH',
      if (structureSig['HL'] == true) 'HL',
      if (structureSig['LH'] == true) 'LH',
      if (structureSig['LL'] == true) 'LL',
    ].join('+');
    if (structStr.isNotEmpty) notes.add('Structure: $structStr');
    
    return TrendAnalysisResult(
      trendScore: ts,
      trend: trend,
      atr: latestAtr,
      ema20: latestEma20,
      ema50: latestEma50,
      entryMin: entryMin,
      entryMax: entryMax,
      entryAdvice: entryAdvice,
      volumeConfirm: volConfirm,
      breakoutDetected: breakout,
      structure: structureSig,
      notes: notes,
    );
  }
}
