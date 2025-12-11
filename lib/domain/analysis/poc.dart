// trade_engine.dart
// Pure-Dart implementation of the full decision tree & TrendScore
// Drop into Flutter or Dart backend. No external libs required.

import 'dart:math';

class OHLCV {
  final DateTime date;
  final double open, high, low, close;
  final double volume;
  OHLCV(this.date, this.open, this.high, this.low, this.close, this.volume);
}

class AnalysisResult {
  final String symbol;
  final DateTime asOf;
  final String trend; // uptrend / downtrend / sideways / unknown
  final int trendScore;
  final double atr;
  final double ema20, ema50;
  final double entryMin, entryMax;
  final String entryAdvice;
  final double suggestedEntry;
  final double initialStop; // ISL (entry - k * ATR)
  final double
  trailingStop; // current tractioned trailing stop (never decreases)
  final double highestCloseSinceEntry;
  final List<String> notes;
  AnalysisResult({
    required this.symbol,
    required this.asOf,
    required this.trend,
    required this.trendScore,
    required this.atr,
    required this.ema20,
    required this.ema50,
    required this.entryMin,
    required this.entryMax,
    required this.entryAdvice,
    required this.suggestedEntry,
    required this.initialStop,
    required this.trailingStop,
    required this.highestCloseSinceEntry,
    required this.notes,
  });
}

class Indicator {
  // EMA (period N) - returns list where index i corresponds to same index in closes
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

  // True Range series
  static List<double> tr(List<OHLCV> bars) {
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

  // ATR (simple Wilder smoothing style)
  static List<double> atr(List<OHLCV> bars, {int period = 14}) {
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

  static double rollingHighestClose(
    List<double> closes,
    int idx,
    int lookback,
  ) {
    final start = max(0, idx - (lookback - 1));
    double hi = double.negativeInfinity;
    for (int i = start; i <= idx; i++) {
      hi = max(hi, closes[i]);
    }
    return hi.isFinite ? hi : double.nan;
  }

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

// Detect swing peaks/troughs (local)
List<int> localPeaks(List<double> arr) {
  final idx = <int>[];
  for (int i = 1; i < arr.length - 1; i++) {
    if (arr[i] > arr[i - 1] && arr[i] > arr[i + 1]) idx.add(i);
  }
  return idx;
}

List<int> localTroughs(List<double> arr) {
  final idx = <int>[];
  for (int i = 1; i < arr.length - 1; i++) {
    if (arr[i] < arr[i - 1] && arr[i] < arr[i + 1]) idx.add(i);
  }
  return idx;
}

// Check HH/HL/LH/LL over last lookback days
Map<String, bool> structureSignals(List<OHLCV> bars, {int lookback = 14}) {
  if (bars.length < 5)
    return {'HH': false, 'HL': false, 'LH': false, 'LL': false};
  final sliceStart = max(0, bars.length - lookback);
  final sub = bars.sublist(sliceStart);
  final highs = sub.map((b) => b.high).toList();
  final lows = sub.map((b) => b.low).toList();
  final pk = localPeaks(highs).map((i) => i + sliceStart).toList();
  final tr = localTroughs(lows).map((i) => i + sliceStart).toList();
  bool hh = false, hl = false, lh = false, ll = false;
  if (pk.length >= 2) {
    // last two peaks increasing?
    final last = pk.takeLast(3);
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
    final last = tr.takeLast(3);
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
  List<E> takeLast(int n) => sublist(max(0, length - n));
}

// TrendScore (balanced)
int calcTrendScore(List<OHLCV> bars, {int lookback = 14}) {
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
    if (closes[last] > ema20[last]) {
      score += 1;
    } else {
      score -= 1;
    }
    if (ema20[last] > ema50[last]) {
      score += 1;
    } else {
      score -= 1;
    }
    // slope check (ema20 slope over 3 periods)
    final prevIdx = max(0, last - 3);
    if (!ema20[prevIdx].isNaN && !ema20[last].isNaN) {
      if (ema20[last] > ema20[prevIdx]) {
        score += 1;
      } else {
        score -= 1;
      }
    }
  }
  return score;
}

class StrategyEngine {
  final String symbol;
  final List<OHLCV> bars;
  final int atrPeriod;
  final double entryAtrFactor; // e.g., 0.5 for EMA20 - 0.5*ATR
  final double entryUpperFactor; // e.g., 0.2 * ATR above EMA20
  final double stopAtrK; // ISL k
  final double trailAtrK; // trailing k
  final int breakoutLookback; // e.g., 20
  final int volLookback; // e.g., 20
  StrategyEngine({
    required this.symbol,
    required this.bars,
    this.atrPeriod = 14,
    this.entryAtrFactor = 0.5,
    this.entryUpperFactor = 0.2,
    this.stopAtrK = 2.0,
    this.trailAtrK = 3.0,
    this.breakoutLookback = 20,
    this.volLookback = 20,
  }) {
    if (bars.isEmpty) throw ArgumentError('bars cannot be empty');
  }

  AnalysisResult analyze({double? entryPriceIfAlreadyIn, DateTime? entryDate}) {
    final closes = bars.map((b) => b.close).toList();
    final volumes = bars.map((b) => b.volume).toList();
    final atrSeries = Indicator.atr(bars, period: atrPeriod);
    final ema20 = Indicator.ema(closes, 20);
    final ema50 = Indicator.ema(closes, 50);
    final last = bars.length - 1;
    final latestAtr = atrSeries[last];
    final latestEma20 = ema20[last];
    final latestEma50 = ema50[last];
    final ts = calcTrendScore(bars);
    // safe entry range
    final entryMin = latestEma20 - entryAtrFactor * latestAtr;
    final entryMax = latestEma20 + entryUpperFactor * latestAtr;
    String entryAdvice = 'No opinion';
    final priceNow = closes[last];
    // volume check
    final vol20 = Indicator.rollingAvgVolume(volumes, last, volLookback);
    final volConfirm = volumes[last] >= vol20 * 1.2;
    // entry decision
    if (ts >= 3 && priceNow >= entryMin && priceNow <= entryMax && volConfirm) {
      entryAdvice = 'Good entry zone';
    } else if (ts >= 2 && priceNow <= entryMin) {
      entryAdvice = 'Potential dip; entry with smaller size';
    } else if (ts < 1) {
      entryAdvice = 'Avoid entry: weak trend';
    } else if (!volConfirm) {
      entryAdvice = 'Avoid entry: volume weak';
    } else {
      entryAdvice = 'Wait or small position';
    }

    // suggested entry default
    double suggestedEntry = priceNow;
    // breakout check
    final prevHigh = Indicator.rollingHighestClose(
      closes,
      last - 1,
      breakoutLookback,
    );
    bool breakout = false;
    if (!prevHigh.isNaN && priceNow > prevHigh) {
      breakout = true;
      suggestedEntry = max(suggestedEntry, prevHigh);
    }

    // initial stop (based on entry)
    final entryForStop = entryPriceIfAlreadyIn ?? suggestedEntry;
    final initialStop = entryForStop - stopAtrK * latestAtr;

    // trailing stop uses highest close since entry or since lookback
    final highestClose60 = Indicator.rollingHighestClose(closes, last, 60);
    final trailingCalc = highestClose60 - trailAtrK * latestAtr;
    // lock trailing stop to never decrease; we simulate last knownTrailingStop or assume initialStop
    // For demo: set trailingStop = max(initialStop, trailingCalc)
    double trailingStop = max(initialStop, trailingCalc);

    // notes
    final notes = <String>[];
    notes.add(
      'ATR=${latestAtr.toStringAsFixed(4)}, EMA20=${latestEma20.toStringAsFixed(2)}, EMA50=${latestEma50.toStringAsFixed(2)}',
    );
    notes.add(
      'TrendScore=$ts, breakout=${breakout ? 'yes' : 'no'}, volConfirm=${volConfirm ? 'yes' : 'no'}',
    );
    if (entryPriceIfAlreadyIn != null) {
      // evaluate confirmation since entryDate
      final entryIdx = entryDate == null
          ? (bars.length - 1)
          : bars.indexWhere(
              (b) =>
                  b.date.isAtSameMomentAs(entryDate) ||
                  b.date.isAfter(entryDate),
            );
      if (entryIdx > 0 && entryIdx < bars.length) {
        // check for higher low and higher high since entry
        final post = bars.sublist(entryIdx);
        final postSig = structureSignals(post, lookback: post.length);
        if (postSig['HL'] == true && postSig['HH'] == true) {
          notes.add('Confirmed since entry (HH+HL).');
        } else {
          notes.add('Not yet confirmed since entry.');
        }
      } else {
        notes.add('Entry index not found in history for confirmation check.');
      }
    }

    return AnalysisResult(
      symbol: symbol,
      asOf: bars[last].date,
      trend: ts >= 3 ? 'uptrend' : (ts <= -3 ? 'downtrend' : 'sideways'),
      trendScore: ts,
      atr: latestAtr,
      ema20: latestEma20,
      ema50: latestEma50,
      entryMin: entryMin,
      entryMax: entryMax,
      entryAdvice: entryAdvice,
      suggestedEntry: suggestedEntry,
      initialStop: initialStop,
      trailingStop: trailingStop,
      highestCloseSinceEntry: highestClose60,
      notes: notes,
    );
  }
}

// Example usage (pseudo):
/*
final bars = loadBars("CRML"); // populate List<OHLCV> ascending by date
final engine = StrategyEngine(symbol: 'CRML', bars: bars);
final analysis = engine.analyze();
print(analysis.entryAdvice);
print('SuggestedEntry ${analysis.suggestedEntry}, ISL ${analysis.initialStop}, Trailing ${analysis.trailingStop}');
if (analysis.notes.isNotEmpty) analysis.notes.forEach(print);
*/
