
import 'dart:math';
import '../model/stock_data.dart';


class TrendAnalysisResult {
  final double score;
  final String riskLevel;
  final String trend;
  final String details;
  
  // Safe Entry Analysis
  final bool isSafeEntry;
  final String safeEntrySignal; // "PASS" or fail reason
  final double safeRangeLow;
  final double safeRangeHigh;

  TrendAnalysisResult({
    required this.score,
    required this.riskLevel,
    required this.trend,
    required this.details,
    required this.isSafeEntry,
    required this.safeEntrySignal,
    required this.safeRangeLow,
    required this.safeRangeHigh,
  });
}

class TrendAnalyzer {
  // Configurable Scores
  double scoreFomo;          // Price > EMA20 + ATR
  double scoreSlightlyAbove; // EMA20 < Price <= EMA20 + ATR
  double scoreOptimal;       // Price ~= EMA20
  double scoreFallingKnife;  // Price < EMA20
  double scoreVolumeSpike;   // Volume Spike
  double scoreSideways;      // Sideways Trend

  TrendAnalyzer({
    this.scoreFomo = 3.0,
    this.scoreSlightlyAbove = 1.0,
    this.scoreOptimal = 0.0,
    this.scoreFallingKnife = 2.0,
    this.scoreVolumeSpike = -1.0,
    this.scoreSideways = 2.0,
  });

  TrendAnalysisResult analyze(List<Candle> candles, List<double?> ema20Series, List<double?> ema50Series, double atr) {
    if (candles.isEmpty || ema20Series.isEmpty || ema20Series.last == null) {
      return TrendAnalysisResult(score: 0, riskLevel: 'Unknown', trend: 'Unknown', details: 'Insufficient Data', isSafeEntry: false, safeEntrySignal: 'No Data', safeRangeLow: 0, safeRangeHigh: 0);
    }

    final currentPrice = candles.last.close;
    final ema20 = ema20Series.last!;
    final sb = StringBuffer();
    double currentScore = 0.0;
    
    // --- Risk Scoring (Previous Logic) ---

    // 1. Price Position vs EMA20
    if (currentPrice > ema20 + atr) {
      currentScore += scoreFomo;
      sb.writeln('• Price >> EMA20 (FOMO): +$scoreFomo');
    } else if (currentPrice > ema20) {
      if (currentPrice <= ema20 + (0.3 * atr)) {
         currentScore += scoreOptimal;
         sb.writeln('• Price near EMA20: +$scoreOptimal');
      } else {
         currentScore += scoreSlightlyAbove;
         sb.writeln('• Price > EMA20: +$scoreSlightlyAbove');
      }
    } else {
       currentScore += scoreFallingKnife;
       sb.writeln('• Price < EMA20 (Falling Knife): +$scoreFallingKnife');
    }

    // 2. Trend Classification
    String trend = 'Neutral';
    if (ema20Series.length >= 5) {
        final prevEma = ema20Series[ema20Series.length - 5];
        if (prevEma != null) {
            final change = (ema20 - prevEma) / prevEma; 
            if (change.abs() < 0.005) {
                trend = 'Sideways';
                currentScore += scoreSideways;
                sb.writeln('• Sideways Trend: +$scoreSideways');
            } else if (change > 0) {
                trend = 'Uptrend';
            } else {
                trend = 'Downtrend';
            }
        }
    }

    // 3. Volume Spike
    double avgVol20 = 0;
    int count = 0;
    for (int i = max(0, candles.length - 20); i < candles.length - 1; i++) {
        avgVol20 += candles[i].volume;
        count++;
    }
    if (count > 0) avgVol20 /= count;
    
    if (candles.last.volume > avgVol20 * 1.5) {
        currentScore += scoreVolumeSpike;
        sb.writeln('• Volume Spike: $scoreVolumeSpike');
    }

    // Risk Level Classification
    String riskLevel = 'Low';
    if (currentScore >= 4) {
        riskLevel = 'Very High';
    } else if (currentScore >= 2) {
        riskLevel = 'High';
    } else if (currentScore >= 1) {
        riskLevel = 'Moderate';
    } else if (currentScore <= 0) {
        riskLevel = 'Low (Optimal)';
    }
    
    // --- Safe Entry Analysis ---
    // Safe Range: [EMA20 - 0.5*ATR, EMA20 + 0.2*ATR]
    double safeLow = ema20 - (0.5 * atr);
    double safeHigh = ema20 + (0.2 * atr);
    
    bool isSafe = true;
    String signalReason = 'PASS';
    
    // Condition A: Trend Direction (Price > EMA20 > EMA50)
    double ema50 = (ema50Series.isNotEmpty && ema50Series.last != null) ? ema50Series.last! : 0.0;
    if (ema50 > 0) {
        if (!(currentPrice > ema20 && ema20 > ema50)) {
            isSafe = false;
            signalReason = 'FAIL: No Uptrend (Price > EMA20 > EMA50)';
        }
    } else {
        // If no EMA50 data yet (not enough candles), strictly fail or be lenient?
        // Logic says "If this is not true -> No entry".
        isSafe = false;
        signalReason = 'FAIL: Insufficient Data for Trend';
    }
    
    // Condition B: Price within Safe Range Logic
    // "Acceptable = Safe Range ... Reject if > EMA20 + 1ATR or < EMA20 - 1ATR"
    // Requirement says: "Price must be within the Safe Range". 
    // BUT strictly being within [EMA20-0.5ATR, EMA20+0.2ATR] is the "Safe Range".
    // The "Reject if" implies a wider tolerance for rejection, but "Acceptable" is the specific range.
    // Let's stick to the "Safe Range" definition for "Optimal" entry.
    // If requirement means ONLY enter if within that strict range, then use that.
    // "Acceptable = Safe Range ... Reject if ..." implies:
    // Ideally inside Safe Range. If outside, definitely reject if > +1ATR or < -1ATR. 
    // What if it's between +0.2ATR and +1ATR? It says "Not too stretched".
    // I will enforce the strict "Safe Range" as the condition for "Safe Entry" for now as per "Price must be within the 'Safe Range'".
    
    if (isSafe) {
        if (currentPrice > safeHigh) {
            isSafe = false;
            signalReason = 'FAIL: Price above Safe Range';
        } else if (currentPrice < safeLow) {
             isSafe = false;
            signalReason = 'FAIL: Price below Safe Range';
        }
    }
    
    // Condition C: Volume not dropping
    // "If live volume is < 40% of expected daily volume by midday -> avoid"
    // "Midday" is hard to check without time context relative to market open.
    // Simple check: Is current volume > 40% of AvgVol20?
    // Note: AvgVol20 is daily average. Current candle might be "today" so far.
    // If it's early morning, volume will be low naturally.
    // Let's just implement the check as requested: Volume > 0.4 * AvgVol20
    if (isSafe) {
        if (candles.last.volume < avgVol20 * 0.4) {
             isSafe = false;
             signalReason = 'FAIL: Weak Volume (< 40% Avg)';
        }
    }

    return TrendAnalysisResult(
        score: currentScore,
        riskLevel: riskLevel,
        trend: trend,
        details: sb.toString().trim(),
        isSafeEntry: isSafe,
        safeEntrySignal: signalReason,
        safeRangeLow: safeLow,
        safeRangeHigh: safeHigh,
    );
  }
}

