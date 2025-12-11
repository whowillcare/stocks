// monitor_engine.dart\n// Post-entry trend monitoring engine

/// Monitor result from post-entry analysis
class MonitorResult {
  final String
  state; // trend_continuation, trend_failure, sideways_consolidation, neutral_wait
  final Map<String, dynamic> continuation;
  final Map<String, dynamic> failure;
  final Map<String, dynamic> sideways;

  MonitorResult({
    required this.state,
    required this.continuation,
    required this.failure,
    required this.sideways,
  });

  String get stateEmoji {
    switch (state) {
      case 'trend_continuation':
        return '✅';
      case 'trend_failure':
        return '❌';
      case 'sideways_consolidation':
        return '⏸️';
      default:
        return '⏳';
    }
  }

  String get stateLabel {
    switch (state) {
      case 'trend_continuation':
        return 'Trend Continuation';
      case 'trend_failure':
        return 'Trend Failure';
      case 'sideways_consolidation':
        return 'Sideways Consolidation';
      default:
        return 'Neutral/Waiting';
    }
  }
}

class MonitorEngine {
  final List<double> closes;
  final List<double> highs;
  final List<double> lows;
  final List<double> volumes;

  late List<double> obv;

  MonitorEngine({
    required this.closes,
    required this.highs,
    required this.lows,
    required this.volumes,
  }) {
    obv = _calculateOBV(closes, volumes);
  }

  // === LOCAL HELPER METHODS ===

  /// OBV Indicator
  static List<double> _calculateOBV(List<double> closes, List<double> volumes) {
    List<double> obv = [0];
    for (int i = 1; i < closes.length; i++) {
      if (closes[i] > closes[i - 1]) {
        obv.add(obv.last + volumes[i]);
      } else if (closes[i] < closes[i - 1]) {
        obv.add(obv.last - volumes[i]);
      } else {
        obv.add(obv.last);
      }
    }
    return obv;
  }

  /// Detect Higher Low pattern
  bool _isHigherLow() {
    if (lows.length < 2) return false;
    return lows[lows.length - 1] > lows[lows.length - 2];
  }

  /// Price falling while volume rising → bearish pressure
  bool _isPriceDownVolumeUp() {
    if (closes.length < 2) return false;
    bool priceDown = closes.last < closes[closes.length - 2];
    bool volumeUp = volumes.last > volumes[volumes.length - 2];
    return priceDown && volumeUp;
  }

  /// Volume rising on green days
  bool _isVolumeRisingOnGreen() {
    if (closes.length < 2) return false;
    bool greenDay = closes.last > closes[closes.length - 2];
    bool volumeUp = volumes.last > volumes[volumes.length - 2];
    return greenDay && volumeUp;
  }

  /// OBV bearish divergence
  bool _isObvBearishDivergence() {
    if (closes.length < 2 || obv.length < 2) return false;
    bool priceFlatUp = closes.last >= closes[closes.length - 2];
    bool obvDown = obv.last < obv[obv.length - 2];
    return priceFlatUp && obvDown;
  }

  /// Volume dry-up (consolidation)
  bool _dryingVolume({int lookback = 5}) {
    if (volumes.length < lookback + 1) return false;
    double recent = volumes.last;
    double avgPast =
        volumes
            .sublist(volumes.length - lookback - 1, volumes.length - 1)
            .reduce((a, b) => a + b) /
        lookback;
    return recent < avgPast * 0.6;
  }

  /// Volume spike down (panic)
  bool _isVolumeSpikeDown({int lookback = 5}) {
    if (volumes.length < lookback + 1) return false;
    double recent = volumes.last;
    double avgPast =
        volumes
            .sublist(volumes.length - lookback - 1, volumes.length - 1)
            .reduce((a, b) => a + b) /
        lookback;
    return recent < avgPast * 0.4;
  }

  // === ANALYSIS CHECKS ===

  /// A. TREND CONTINUATION CHECK
  Map<String, dynamic> checkTrendContinuation() {
    bool hl = _isHigherLow();
    bool volGreenUp = _isVolumeRisingOnGreen();
    bool continuation = hl && volGreenUp;

    return {
      "continuation": continuation,
      "higherLow": hl,
      "volumeUpOnGreen": volGreenUp,
    };
  }

  /// B. TREND FAILURE CONDITIONS
  Map<String, dynamic> checkTrendFailure() {
    bool priceDownVolUp = _isPriceDownVolumeUp();
    bool obvDivergence = _isObvBearishDivergence();
    bool hlBroken = lows.length >= 2 && closes.last < lows[lows.length - 2];
    bool failure = priceDownVolUp || obvDivergence || hlBroken;

    return {
      "failure": failure,
      "priceDownVolumeUp": priceDownVolUp,
      "obvBearishDivergence": obvDivergence,
      "higherLowBroken": hlBroken,
    };
  }

  /// C. SIDEWAYS DETECTION
  Map<String, dynamic> checkSideways() {
    bool dry = _dryingVolume();
    bool spikeDown = _isVolumeSpikeDown();
    bool sideways = dry && !spikeDown;

    return {
      "sideways": sideways,
      "volumeDry": dry,
      "volumeSpikeDown": spikeDown,
    };
  }

  /// FINAL DECISION - returns MonitorResult
  MonitorResult evaluate() {
    final cont = checkTrendContinuation();
    final fail = checkTrendFailure();
    final side = checkSideways();

    String state = "neutral_wait";

    if (fail["failure"] == true) {
      state = "trend_failure";
    } else if (cont["continuation"] == true) {
      state = "trend_continuation";
    } else if (side["sideways"] == true) {
      state = "sideways_consolidation";
    }

    return MonitorResult(
      state: state,
      continuation: cont,
      failure: fail,
      sideways: side,
    );
  }
}
