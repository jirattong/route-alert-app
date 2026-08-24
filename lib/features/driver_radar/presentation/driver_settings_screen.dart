import 'package:flutter/material.dart';
import '../../../core/services/driver_storage_service.dart';

class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  bool _isBackgroundMode = true;
  double _volume = 80.0;
  double _outerMeters = 1500.0; // 500 - 3000 เมตร
  double _innerMeters = 400.0;  // 100 - 800 เมตร

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final settings = await DriverStorageService.loadSettings();
    if (mounted) {
      setState(() {
        _isBackgroundMode = settings['background'];
        _volume = settings['volume'];
        _outerMeters = settings['outerMeters'];
        _innerMeters = settings['innerMeters'];
      });
    }
  }

  void _persistSettings() {
    DriverStorageService.saveSettings(
      background: _isBackgroundMode,
      volume: _volume,
      outerMeters: _outerMeters,
      innerMeters: _innerMeters,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  _buildCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ทำงานเบื้องหลัง',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              '(Background)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5B9EE1),
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isBackgroundMode,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF5B9EE1),
                          onChanged: (val) {
                            setState(() => _isBackgroundMode = val);
                            _persistSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text(
                              'ระดับเสียง',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Volume',
                              style: TextStyle(fontSize: 12, color: Color(0xFF5B9EE1), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.volume_up_rounded, color: Colors.black87),
                            Expanded(
                              child: Slider(
                                value: _volume,
                                min: 0,
                                max: 100,
                                activeColor: const Color(0xFF5B9EE1),
                                inactiveColor: const Color(0xFFD6E9FF),
                                onChanged: (val) => setState(() => _volume = val),
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              '${_volume.round()}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ระยะตรวจจับเรดาร์ (วงนอกสีฟ้า)
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text(
                              'ระยะตรวจจับเรดาร์',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '(วงนอกสีฟ้า)',
                              style: TextStyle(fontSize: 12, color: Color(0xFF5B9EE1), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.radar_rounded, color: Color(0xFF5B9EE1)),
                            Expanded(
                              child: Slider(
                                value: _outerMeters,
                                min: 300,
                                max: 3000,
                                divisions: 27,
                                activeColor: const Color(0xFF5B9EE1),
                                inactiveColor: const Color(0xFFD6E9FF),
                                onChanged: (val) {
                                  setState(() {
                                    _outerMeters = val;
                                    if (_innerMeters >= _outerMeters) {
                                      _innerMeters = _outerMeters - 100;
                                    }
                                  });
                                },
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              _outerMeters >= 1000
                                  ? '${(_outerMeters / 1000).toStringAsFixed(1)} KM'
                                  : '${_outerMeters.round()} M',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ระยะแจ้งเตือนวิกฤต (วงในสีแดง)
                  _buildCard(
                    borderColor: const Color(0xFFEB5757),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text(
                              'ระยะแจ้งเตือนวิกฤต',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '(วงในสีแดง)',
                              style: TextStyle(fontSize: 12, color: Color(0xFFEB5757), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEB5757)),
                            Expanded(
                              child: Slider(
                                value: _innerMeters,
                                min: 100,
                                max: 1200,
                                divisions: 11,
                                activeColor: const Color(0xFFEB5757),
                                inactiveColor: const Color(0xFFFFD6D6),
                                onChanged: (val) {
                                  setState(() {
                                    _innerMeters = val;
                                    if (_innerMeters >= _outerMeters) {
                                      _outerMeters = _innerMeters + 100;
                                    }
                                  });
                                },
                                onChangeEnd: (_) => _persistSettings(),
                              ),
                            ),
                            Text(
                              '${_innerMeters.round()} M',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFEB5757)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child, Color borderColor = const Color(0xFF5B9EE1)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: const Center(
        child: Text(
          'RouteAlert',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
    );
  }
}