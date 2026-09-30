import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';

/// ปุ่มลอยบนแผนที่ "ไปตำแหน่งปัจจุบัน" — ใช้ในหน้าปักหมุดตำแหน่งโรงพยาบาล
class MyLocationButton extends StatefulWidget {
  final ValueChanged<LatLng> onLocated;

  const MyLocationButton({super.key, required this.onLocated});

  @override
  State<MyLocationButton> createState() => _MyLocationButtonState();
}

class _MyLocationButtonState extends State<MyLocationButton> {
  bool _loading = false;

  Future<void> _locate() async {
    if (_loading) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final position = await LocationService.getCurrentLocationOrNull();
    if (!mounted) return;
    setState(() => _loading = false);
    if (position == null) {
      messenger?.showSnackBar(const SnackBar(
        content: Text('หาตำแหน่งปัจจุบันไม่ได้ — เช็คว่าเปิด GPS และอนุญาตให้แอปใช้ตำแหน่งแล้ว'),
      ));
      return;
    }
    widget.onLocated(position);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _locate,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF00A896)),
                  )
                : const Icon(Icons.my_location_rounded, color: Color(0xFF00A896), size: 24),
          ),
        ),
      ),
    );
  }
}
