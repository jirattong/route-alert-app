import 'package:flutter/material.dart';

class IncidentListScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  const IncidentListScreen({super.key, this.onOpenSos});

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  String _selectedProvince = 'เชียงใหม่';
  int _selectedTab = 0; // 0 = เหตุในบริเวณพื้นที่, 1 = รายงานของฉัน (SOS)

  final List<Map<String, dynamic>> _incidents = [
    {
      'id': 'Case #AVCB00021',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'carPlate': 'กขค123',
      'status': 'กำลังรอยืนยัน',
      'statusColor': const Color(0xFF5B9EE1),
      'hasAmbulance': true,
      'hasPolice': true,
    },
    {
      'id': 'Case #AVCB00019',
      'location': 'อ.เมือง จ.เชียงใหม่',
      'type': 'การจราจรติดขัดรุนแรง',
      'carPlate': 'ขก4567',
      'status': 'กำลังดำเนินการ',
      'statusColor': const Color(0xFFF59E0B),
      'hasAmbulance': false,
      'hasPolice': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 14),

                // ตัวเลือกจังหวัด
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, color: Color(0xFFEB5757), size: 20),
                          SizedBox(width: 4),
                          Text(
                            'พื้นที่แสดงเหตุ:',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedProvince,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF5B9EE1)),
                            items: ['เชียงใหม่', 'พะเยา', 'เชียงราย', 'ลำปาง']
                                .map((prov) => DropdownMenuItem(value: prov, child: Text(prov)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedProvince = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // แท็บสลับประเภทเหตุ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0 ? const Color(0xFF5B9EE1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'เหตุในบริเวณพื้นที่',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 0 ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1 ? const Color(0xFF5B9EE1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'รายงานของฉัน (SOS)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 1 ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // รายการเหตุ
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    itemCount: _incidents.length,
                    itemBuilder: (context, index) => _buildIncidentCard(_incidents[index]),
                  ),
                ),
              ],
            ),

            // ปุ่ม SOS ลอยขวาล่าง
            Positioned(
              right: 20,
              bottom: 20,
              child: InkWell(
                onTap: widget.onOpenSos,
                borderRadius: BorderRadius.circular(35),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEB5757), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEB5757).withValues(alpha: 0.35),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'SOS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFEB5757),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['location'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                item['id'],
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                item['type'],
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              if (item['carPlate'] != null) ...[
                const SizedBox(height: 2),
                Text(
                  'เลขรถรับเคส : ${item['carPlate']}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    item['status'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: item['statusColor'],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item['hasAmbulance'] == true) const Text('🚑', style: TextStyle(fontSize: 16)),
                  if (item['hasPolice'] == true) const Text('🚓', style: TextStyle(fontSize: 16)),
                ],
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
            ),
            child: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF5B9EE1), size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined, size: 18, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(Icons.wifi, size: 8, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'RouteAlert',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }
}