import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models/geological_point.dart';
import 'database/database_helper.dart';

void main() {
  runApp(const GeoFieldMapperApp());
}

class GeoFieldMapperApp extends StatelessWidget {
  const GeoFieldMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoFieldMapper',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  
  final TextEditingController _lithologyController = TextEditingController();
  final TextEditingController _structureController = TextEditingController();
  final TextEditingController _mineralController = TextEditingController();

  double _strike = 0.0;
  double _dipDirection = 0.0;
  double _dip = 0.0;

  List<GeologicalPoint> _pointsList = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadPoints();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoadingLocation = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoadingLocation = false);
        return;
      }
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
      _isLoadingLocation = false;
    });
  }

  Future<void> _loadPoints() async {
    final points = await DatabaseHelper.instance.getAllPoints();
    setState(() {
      _pointsList = points;
    });
  }

  Future<void> _savePoint() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未获取到有效定位！')),
      );
      return;
    }

    GeologicalPoint point = GeologicalPoint(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      altitude: _currentPosition!.altitude,
      lithology: _lithologyController.text.isEmpty ? '未命名岩性' : _lithologyController.text,
      structure: _structureController.text,
      mineralization: _mineralController.text,
      strike: _strike,
      dipDirection: _dipDirection,
      dip: _dip,
      timestamp: DateTime.now().toIso8601String(),
    );

    await DatabaseHelper.instance.insertPoint(point);
    await _loadPoints();

    _lithologyController.clear();
    _structureController.clear();
    _mineralController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('地质点数据离线保存成功！')),
    );
  }

  Future<void> _exportGeoJson() async {
    List<GeologicalPoint> points = await DatabaseHelper.instance.getAllPoints();
    List<Map<String, dynamic>> features = points.map((p) => p.toGeoJsonFeature()).toList();

    Map<String, dynamic> geoJsonCollection = {
      "type": "FeatureCollection",
      "features": features,
    };

    String jsonString = const JsonEncoder.withIndent('  ').convert(geoJsonCollection);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/geological_points.geojson');
    await file.writeAsString(jsonString);

    await Share.shareXFiles([XFile(file.path)], text: 'GeoFieldMapper 填图成果 (GeoJSON)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoFieldMapper 野外填图'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _exportGeoJson,
            tooltip: '导出 GeoJSON',
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ListView(
          children: [
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('GPS / RTK 实时定位', style: TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _getCurrentLocation,
                        ),
                      ],
                    ),
                    const Divider(),
                    _isLoadingLocation
                        ? const Text('正在搜索卫星定位...')
                        : Text(_currentPosition == null
                            ? '无定位信息'
                            : '纬度: ${_currentPosition!.latitude.toStringAsFixed(6)}\n经度: ${_currentPosition!.longitude.toStringAsFixed(6)}\n高程: ${_currentPosition!.altitude.toStringAsFixed(2)} m'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lithologyController,
              decoration: const InputDecoration(labelText: '岩性描述 (Lithology)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _structureController,
              decoration: const InputDecoration(labelText: '构造特征 (Structure)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mineralController,
              decoration: const InputDecoration(labelText: '矿化信息 (Mineralization)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            Text('产状测量: 走向 ${_strike.toStringAsFixed(0)}° / 倾向 ${_dipDirection.toStringAsFixed(0)}° / 倾角 ${_dip.toStringAsFixed(0)}°'),
            Row(
              children: [
                const Text('倾角: '),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 90,
                    divisions: 90,
                    label: _dip.round().toString(),
                    value: _dip,
                    onChanged: (val) => setState(() => _dip = val),
                  ),
                ),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: _savePoint,
              icon: const Icon(Icons.add_location),
              label: const Text('录入当前地质点'),
            ),
            const Divider(height: 30),
            Text('已采地质点列表 (${_pointsList.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pointsList.length,
              itemBuilder: (context, index) {
                final pt = _pointsList[index];
                return ListTile(
                  title: Text('${pt.id}. ${pt.lithology}'),
                  subtitle: Text('定位: ${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)} | 产状: ${pt.dip}°'),
                  trailing: Text(pt.timestamp.substring(11, 16)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
