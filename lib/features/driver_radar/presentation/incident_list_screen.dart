import 'package:flutter/material.dart';
import 'sos_report_screen.dart';
import 'incident_detail_screen.dart';

class IncidentListScreen extends StatefulWidget {
  const IncidentListScreen({super.key});

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  // สลับแท็บสโคปเหตุการณ์ (0: เหตุในบริเวณพื้นที่, 1: รายงานของฉัน)
  int _selectedTab = 0;

  // ตัวแปรเก็บจังหวัดที่เลือก (Default เป็น 'เชียงใหม่')
  String _selectedProvince = 'เชียงใหม่';

  // รายการจังหวัดสำหรับ Dropdown Filter
  final List<String> _provinces = [
    'ทั้งหมด',
    'เชียงใหม่',
    'เชียงราย',
    'พะเยา',
    'กรุงเทพมหานคร',
  ];

  // ตัวอย่างข้อมูลเคสในบริเวณพื้นที่
  final List<Map<String, dynamic>> _nearbyIncidents = [
    {
      'id': 'Case #AVCB00021',
      'province': 'เชียงใหม่',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'vehiclePlate': 'กขค123',
      'status': 'กำลังรอยืนยัน',
      'statusColor': const Color(0xFF5B9EE1),
      'hasPolice': true,
      'hasAmbulance': true,
    },
    {
      'id': 'Case #AVCB00025',
      'province': 'พะเยา',
      'location': 'หน้า ม.พะเยา ถ.พหลโยธิน',
      'type': 'สิ่งกีดขวางบนท้องถนน',
      'vehiclePlate': 'ผก9988',
      'status': 'กำลังดำเนินการ',
      'statusColor': Colors.orange,
      'hasPolice': true,
      'hasAmbulance': false,
    },
    {
      'id': 'Case #AVCB00019',
      'province': 'เชียงใหม่',
      'location': 'อ.เมือง จ.เชียงใหม่',
      'type': 'การจราจรติดขัดรุนแรง',
      'vehiclePlate': 'ขก4567',
      'status': 'กำลังดำเนินการ',
      'statusColor': Colors.orange,
      'hasPolice': true,
      'hasAmbulance': false,
    },
  ];

  // ตัวอย่างข้อมูลเคสที่ผู้ใช้คนนี้กดส่ง SOS เอง
  final List<Map<String, dynamic>> _mySosIncidents = [
    {
      'id': 'Case #MY00892',
      'province': 'พะเยา',
      'location': 'หน้า ม.พะเยา ถ.พหลโยธิน',
      'type': 'สิ่งกีดขวางบนท้องถนน',
      'vehiclePlate': 'กำลังจัดสรรรถ',
      'status': 'รับแจ้งเหตุแล้ว',
      'statusColor': Colors.green,
      'hasPolice': false,
      'hasAmbulance': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    // 1. เลือกลิสต์ข้อมูลตามแท็บที่กด
    final rawList = _selectedTab == 0 ? _nearbyIncidents : _mySosIncidents;

    // 2. กรองข้อมูลเฉพาะจังหวัดที่เลือก (ถ้าเลือก 'ทั้งหมด' ให้แสดงทุกเคส)
    final activeList = _selectedProvince == 'ทั้งหมด'
        ? rawList
        : rawList
            .where((item) => item['province'] == _selectedProvince)
            .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. แถบเลือกจังหวัด (Province Selector Bar) ---
            const SizedBox(height: 12),
            _buildProvinceSelectorBar(),

            // --- 3. แท็บสลับประเภทเคส ---
            const SizedBox(height: 12),
            _buildCategoryTabs(),
            const SizedBox(height: 16),

            // --- 4. รายการการ์ดแสดงเหตุการณ์ที่ผ่านการกรองแล้ว ---
            Expanded(
              child: Stack(
                children: [
                  activeList.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          itemCount: activeList.length,
                          itemBuilder: (context, index) {
                            final item = activeList[index];
                            return _buildIncidentCard(item);
                          },
                        ),

                  // --- ปุ่ม SOS ฉุกเฉินลอยมุมขวาล่าง ---
                  Positioned(
                    right: 20,
                    bottom: 20,
                    child: _buildSosFloatingButton(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // ❌ ถอด bottomNavigationBar ออกเพื่อใช้ Shell ร่วมกันใน DriverMainScreen
    );
  }

  // --- Header แถบบนพร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined,
                    size: 20, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.wifi,
                      size: 9, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // --- แถบเลือกจังหวัด (Province Selector Bar) ---
  Widget _buildProvinceSelectorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFFEB5757), size: 22),
              const SizedBox(width: 6),
              Text(
                'พื้นที่แสดงเหตุ:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF5B9EE1).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF5B9EE1), width: 1.2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProvince,
                icon: const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xFF5B9EE1), size: 24),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5B9EE1),
                ),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedProvince = newValue);
                  }
                },
                items: _provinces.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- แท็บสลับระหว่าง "เหตุในบริเวณพื้นที่" กับ "รายงานของฉัน" ---
  Widget _buildCategoryTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 0
                      ? const Color(0xFF5B9EE1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'เหตุในบริเวณพื้นที่',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _selectedTab == 0 ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _selectedTab == 1
                      ? const Color(0xFF5B9EE1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'รายงานของฉัน (SOS)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _selectedTab == 1 ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- การ์ดเคสเหตุการณ์ (กดแล้วเปิดหน้า IncidentDetailScreen) ---
  Widget _buildIncidentCard(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => IncidentDetailScreen(incidentData: item),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['location'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['id'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['type'],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'เลขรถรับเคส : ${item['vehiclePlate']}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
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
                          if (item['hasAmbulance'] == true)
                            const Text('🚑 ', style: TextStyle(fontSize: 16)),
                          if (item['hasPolice'] == true)
                            const Text('🚓', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF5B9EE1),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- กรณีไม่มีเคส ---
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'ไม่มีรายการเหตุการณ์ในขณะนี้',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // --- ปุ่ม SOS ลอยฉุกเฉิน ---
  Widget _buildSosFloatingButton() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SosReportScreen(),
              ),
            );
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEB5757), width: 2.5),
            ),
            child: const Center(
              child: Text(
                'SOS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEB5757),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}