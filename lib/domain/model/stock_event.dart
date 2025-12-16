class StockEvent {
  final DateTime timestamp;
  final String symbol;
  final String message;
  final String type; // 'stop_loss', 'trend', 'info'

  StockEvent({
    required this.timestamp,
    required this.symbol,
    required this.message,
    this.type = 'info',
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'symbol': symbol,
      'message': message,
      'type': type,
    };
  }

  factory StockEvent.fromJson(Map<String, dynamic> json) {
    return StockEvent(
      timestamp: DateTime.parse(json['timestamp']),
      symbol: json['symbol'],
      message: json['message'],
      type: json['type'] ?? 'info',
    );
  }
}
