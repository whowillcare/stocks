import 'package:uuid/uuid.dart';

import '../domain/model/stock_data.dart';
import '../domain/analysis/trend_analyzer.dart';
import '../domain/analysis/monitor_engine.dart';

class StockSession {
  final String id;
  String? symbol;
  StockQuote? stockQuote;
  bool isLoading = false;
  String? errorMessage;

  int selectedStrategyIndex = 0;

  double? trailingStopPrice;
  double? cutLossPrice;
  String? equation;

  TrendAnalysisResult? trendAnalysis;
  MonitorResult? monitorResult;

  DateTime? entryDate;
  double? entryPrice;

  DateTime? lastRefreshedAt;

  TrendAnalysisResult? previousTrendAnalysis;
  double? previousTrailingStop;

  StockSession(this.id);

  String get title => symbol ?? 'New Tab';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'selectedStrategyIndex': selectedStrategyIndex,
      'entryDate': entryDate?.toIso8601String(),
      'entryPrice': entryPrice,
      'previousTrendAnalysis': previousTrendAnalysis?.toJson(),
      'previousTrailingStop': previousTrailingStop,
    };
  }

  factory StockSession.fromJson(Map<String, dynamic> json) {
    var session = StockSession(json['id'] ?? const Uuid().v4());
    session.symbol = json['symbol'];
    session.selectedStrategyIndex = json['selectedStrategyIndex'] ?? 0;
    if (json['entryDate'] != null) {
      session.entryDate = DateTime.tryParse(json['entryDate']);
    }
    session.entryPrice = (json['entryPrice'] as num?)?.toDouble();
    if (json['previousTrendAnalysis'] != null) {
      session.previousTrendAnalysis = TrendAnalysisResultParams.fromJson(
        json['previousTrendAnalysis'],
      );
    }
    session.previousTrailingStop = (json['previousTrailingStop'] as num?)
        ?.toDouble();
    return session;
  }
}
