
import 'package:uuid/uuid.dart';

import '../domain/model/stock_data.dart';
import '../domain/analysis/trend_analyzer.dart';


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

  DateTime? entryDate;
  double? entryPrice;

  StockSession(this.id);
  
  String get title => symbol ?? 'New Tab';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'selectedStrategyIndex': selectedStrategyIndex,
      'entryDate': entryDate?.toIso8601String(),
      'entryPrice': entryPrice,
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
    return session;
  }
}
