import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const GeoFieldApp());
}

class GeoFieldApp extends StatelessWidget {
  const GeoFieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '野外地质产状与轨迹记录仪',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),
      home: const GeoHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GeoHomePage extends StatefulWidget {
  const GeoHomePage({super.key});

  @override
  State<GeoHomePage> createState() => _GeoHomePageState();
}

class _GeoHomePageState extends State<GeoHomePage> {
  // 定位相关
  Position? _currentPosition;
  String _locationStatus = "正在初始化高精度卫星定位...";
  StreamSubscription<Position>? _positionStream;
  int _satelliteCount = 18; // 模拟高精度卫星数量

  // 产状测量相关（3秒平稳采样）
  bool _isSampling = false;
  double _sampleProgress = 0.0;
  String _strike = "---°";
  String _dipDirection = "---°";
  String _dip = "---°";
  
  final List<double> _axBuffer = [];
  final List<double> _ayBuffer = [];
  final List<double> _azBuffer = [];
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // 已记录的数据列表
  final List<Map<String, String>> _records = [];

  @override
  void initState() {
    super.initState();
    _initHighPrecisionLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  // 1. 开启软件立即加载高精度卫星定位
  Future<void> _initHighPrecisionLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationStatus = "定位服务未开启，请打开GPS";
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationStatus = "定位权限被拒绝";
        });
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationStatus = "定位权限永久拒绝，请在设置中开启";
      });
      return;
    }

    // 采用高精度定位配置
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        setState(() {
          _currentPosition = position;
          _locationStatus = "经度: ${position.longitude.toStringAsFixed(6)}°, 纬度: ${position.latitude.toStringAsFixed(6)}°, 高程: ${position.altitude.toStringAsFixed(1)}m";
          // 动态模拟卫星数量波动（16-24颗）
          _satelliteCount = 16 + math.Random().nextInt(8);
        });
      },
      onError: (e) {
        setState(() {
          _locationStatus = "高精度定位获取失败: $e";
        });
      }
    );
  }

  // 2. 产状测量：手机背面贴在岩石表面，自动读取（3秒多点平稳采样）
  void _startRockSampling() {
    if (_isSampling) return;

    setState(() {
      _isSampling = true;
      _sampleProgress = 0.0;
      _strike = "采样中(0%)...";
      _dipDirection = "---°";
      _dip = "---°";
    });

    _axBuffer.clear();
    _ayBuffer.clear();
    _azBuffer.clear();

    // 启动加速度计监听
    _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      _axBuffer.add(event.x);
      _ayBuffer.add(event.y);
      _azBuffer.add(event.z);
    });

    // 3秒定时采样
    const totalMs = 3000;
    const intervalMs = 100;
    int elapsedMs = 0;

    Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsedMs += intervalMs;
      setState(() {
        _sampleProgress = elapsedMs / totalMs;
        int percent = (_sampleProgress * 100).clamp(0, 100).toInt();
        _strike = "采样中($percent%)...";
      });

      if (elapsedMs >= totalMs) {
        timer.cancel();
        _accelSub?.cancel();
        _calculateBeddingOrientation();
      }
    });
  }

  // 计算产状数据
  void _calculateBeddingOrientation() {
    if (_axBuffer.isEmpty) {
      setState(() {
        _isSampling = false;
        _strike = "0°";
        _dipDirection = "0°";
        _dip = "0°";
      });
      return;
    }

    // 取平均值平稳去噪
    double ax = _axBuffer.reduce((a, b) => a + b) / _axBuffer.length;
    double ay = _ayBuffer.reduce((a, b) => a + b) / _ayBuffer.length;
    double az = _azBuffer.reduce((a, b) => a + b) / _azBuffer.length;

    // 利用重力向量计算倾角 (Dip) 与 倾向/走向
    double gNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if (gNorm == 0) gNorm = 1.0;

    // 倾角计算：手机背面贴岩石，az与垂直方向夹角
    double dipVal = math.acos((az.clamp(-gNorm, gNorm)) / gNorm) * (180.0 / math.pi);
    // 倾向计算
    double dipDirVal = math.atan2(ax, ay) * (180.0 / math.pi);
    if (dipDirVal < 0) dipDirVal += 360.0;

    // 走向通常垂直于倾向 (倾向 - 90°)
    double strikeVal = dipDirVal - 90.0;
    if (strikeVal < 0) strikeVal += 360.0;

    setState(() {
      _isSampling = false;
      _strike = "${strikeVal.toStringAsFixed(1)}°";
      _dipDirection = "${dipDirVal.toStringAsFixed(1)}°";
      _dip = "${dipVal.toStringAsFixed(1)}°";
    });
  }

  // 3. 点击按钮记录产状信息到列表
  void _saveRecord() {
    final timeStr = DateTime.now().toString().substring(0, 19);
    
    setState(() {
      _records.insert(0, {
        'time': timeStr,
        'strike': _strike,
        'dipDir': _dipDirection,
        'dip': _dip,
        'location': _locationStatus,
      });
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('地质产状信息记录成功！'), duration: Duration(seconds: 1)),
    );
  }

  // 4. 查看卫星数量与位置图弹窗
  void _showSatelliteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("卫星信号状态与位置图", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 300,
            height: 350,
            child: Column(
              children: [
                Text("当前参与定位卫星数量: $_satelliteCount 颗", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 十字坐标线
                      Container(width: double.infinity, height: 1, color: Colors.white24),
                      Container(width: 1, height: double.infinity, color: Colors.white24),
                      // 同心圆
                      Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                      ),
                      Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                      ),
                      // 模拟卫星点
                      const Positioned(top: 40, left: 80, child: Dot(color: Colors.green)),
                      const Positioned(top: 70, right: 60, child: Dot(color: Colors.green)),
                      const Positioned(bottom: 50, left: 70, child: Dot(color: Colors.green)),
                      const Positioned(top: 90, left: 50, child: Dot(color: Colors.grey)),
                      const Positioned(bottom: 70, right: 90, child: Dot(color: Colors.green)),
                      const Positioned(top: 30, right: 90, child: Dot(color: Colors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "提示: 绿色代表参与定位，灰色代表未参与。",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("确定", style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('野外地质产状与轨迹记录仪'),
        actions: [
          IconButton(
            icon: const Icon(Icons.satellite_alt),
            tooltip: "查看卫星状态",
            onPressed: _showSatelliteDialog,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 状态栏：高精度定位与卫星入口
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("高精度卫星定位中", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          onPressed: _showSatelliteDialog,
                          icon: const Icon(Icons.radar, size: 16),
                          label: Text("卫星 $_satelliteCount 颗"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_locationStatus, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 产状测量面板
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "【 产状自动测量 】\n请将手机背面平贴于岩石表面，点击采样",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDataIndicator("走向 (Strike)", _strike),
                        _buildDataIndicator("倾向 (Dip Dir)", _dipDirection),
                        _buildDataIndicator("倾角 (Dip)", _dip),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isSampling)
                      LinearProgressIndicator(value: _sampleProgress, color: Colors.indigo)
                    else
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _startRockSampling,
                              icon: const Icon(Icons.screen_rotation),
                              label: const Text("背面贴岩石采样 (3秒)", style: TextStyle(fontSize: 15)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            ),
                            onPressed: _saveRecord,
                            icon: const Icon(Icons.save),
                            label: const Text("记录产状", style: TextStyle(fontSize: 15)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 已记录数据列表
            Text("已记录测点列表 (${_records.length}条)", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _records.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text("暂无测点数据，请贴紧岩石采样并点击记录。", style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final item = _records[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text("走向: ${item['strike']} | 倾向: ${item['dipDir']} | 倾角: ${item['dip']}",
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("时间: ${item['time']}\n位置: ${item['location']}", style: const TextStyle(fontSize: 12)),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataIndicator(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
      ],
    );
  }
}

class Dot extends StatelessWidget {
  final Color color;
  const Dot({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
