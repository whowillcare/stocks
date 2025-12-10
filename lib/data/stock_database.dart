
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../domain/model/stock_data.dart';

class StockDatabase {
  static final StockDatabase instance = StockDatabase._init();
  static Database? _database;

  StockDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('stocks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE candles (
        symbol TEXT NOT NULL,
        date INTEGER NOT NULL,
        open REAL NOT NULL,
        high REAL NOT NULL,
        low REAL NOT NULL,
        close REAL NOT NULL,
        volume INTEGER NOT NULL,
        PRIMARY KEY (symbol, date)
      )
    ''');
  }

  Future<void> insertCandles(String symbol, List<Candle> candles) async {
    final db = await instance.database;
    final batch = db.batch();

    for (final candle in candles) {
      final map = candle.toMap();
      map['symbol'] = symbol;
      batch.insert(
        'candles',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Candle>> getCandles(String symbol) async {
    final db = await instance.database;
    final result = await db.query(
      'candles',
      where: 'symbol = ?',
      whereArgs: [symbol],
      orderBy: 'date ASC',
    );

    return result.map((json) => Candle.fromMap(json)).toList();
  }
}
