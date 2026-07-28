import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/geological_point.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('geofield_mapper.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE geological_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL NOT NULL,
        lithology TEXT NOT NULL,
        structure TEXT NOT NULL,
        mineralization TEXT NOT NULL,
        strike REAL NOT NULL,
        dipDirection REAL NOT NULL,
        dip REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertPoint(GeologicalPoint point) async {
    final db = await instance.database;
    return await db.insert('geological_points', point.toMap());
  }

  Future<List<GeologicalPoint>> getAllPoints() async {
    final db = await instance.database;
    final result = await db.query('geological_points', orderBy: 'id DESC');
    return result.map((json) => GeologicalPoint.fromMap(json)).toList();
  }
}
