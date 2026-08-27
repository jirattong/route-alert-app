import 'dart:ui';
import 'package:flutter/material.dart';

class HomeScreenSimulationView extends StatelessWidget {
  final int distanceMeters;
  final bool isCritical;
  final double yieldProbability;
  final String statusText;
  final VoidCallback onReturnToApp;

  const HomeScreenSimulationView({
    super.key,
    required this.distanceMeters,
    required this.isCritical,
    required this.yieldProbability,
    required this.statusText,
    required this.onReturnToApp,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. iOS / Mobile Wallpaper Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF818CF8), // Indigo
                  Color(0xFF38BDF8), // Sky Blue
                  Color(0xFF0284C7), // Ocean Blue
                  Color(0xFF0369A1),
                ],
              ),
            ),
          ),

          // 2. iOS Home Screen Grid with App Icons
          SafeArea(
            child: Column(
              children: [
                // Top Status Bar (Time 9:41, Cellular, Wifi, Battery)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '9:41',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.signal_cellular_4_bar, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          const Icon(Icons.wifi, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Container(
                            width: 22,
                            height: 11,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 1.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            padding: const EdgeInsets.all(1.5),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // 3. 🚨 ULTRA-PREMIUM LIVE ACTIVITY FLOATING CARD (เด้งเตือนลอยอยู่บนหน้าจอหลัก)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLiveActivityWidget(context),
                ),

                const SizedBox(height: 24),

                // 4. iOS Home Screen Icons Grid
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 22,
                      crossAxisSpacing: 18,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildAppIcon(Icons.camera_alt_rounded, 'Camera', const Color(0xFF64748B)),
                        _buildAppIcon(Icons.photo_library_rounded, 'Photos', const Color(0xFFF59E0B)),
                        _buildAppIcon(Icons.mail_rounded, 'Mail', const Color(0xFF3B82F6)),
                        _buildAppIcon(Icons.notes_rounded, 'Notes', const Color(0xFFFBBF24)),

                        _buildAppIcon(Icons.newspaper_rounded, 'News', const Color(0xFFEF4444)),
                        _buildAppIcon(Icons.tv_rounded, 'TV', const Color(0xFF1E293B)),
                        _buildAppIcon(Icons.rocket_launch_rounded, 'Games', const Color(0xFFF97316)),
                        _buildAppIcon(Icons.storefront_rounded, 'App Store', const Color(0xFF0284C7)),

                        _buildAppIcon(Icons.explore_rounded, 'Maps', const Color(0xFF10B981)),
                        _buildAppIcon(Icons.favorite_rounded, 'Health', const Color(0xFFEC4899)),
                        _buildAppIcon(Icons.account_balance_wallet_rounded, 'Wallet', const Color(0xFF475569)),
                        _buildAppIcon(Icons.settings_rounded, 'Settings', const Color(0xFF64748B)),

                        _buildRouteAlertAppIcon(context),
                      ],
                    ),
                  ),
                ),

                // 5. iOS Dock at Bottom
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildDockIcon(Icons.phone_rounded, const Color(0xFF22C55E)),
                            _buildDockIcon(Icons.public_rounded, const Color(0xFF38BDF8)),
                            _buildDockIcon(Icons.chat_bubble_rounded, const Color(0xFF22C55E)),
                            _buildDockIcon(Icons.music_note_rounded, const Color(0xFFEF4444)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Bottom Home Bar Indicator
                Container(
                  width: 140,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),

          // Return Button Floating Top
          Positioned(
            bottom: 95,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: onReturnToApp,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'กดเพื่อกลับสู่หน้าจอแอพหลัก (Return to App)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🌟 Ultra-Premium Live Activity Glassmorphism Widget
  Widget _buildLiveActivityWidget(BuildContext context) {
    return InkWell(
      onTap: onReturnToApp,
      borderRadius: BorderRadius.circular(28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isCritical ? const Color(0xFFEF4444) : Colors.white,
                width: isCritical ? 2.5 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isCritical
                      ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                Row(
                  children: [
                    // App Logo Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00A896), Color(0xFF0284C7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00A896).withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.airport_shuttle_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isCritical ? 'เตือนภัยฉุกเฉินระดับวิกฤต' : 'แจ้งเตือนมีรถพยาบาล',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('🚑', style: TextStyle(fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isCritical ? 'อยู่ในช่องทางเดียวกัน • ชะลอและเบี่ยงซ้าย' : statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCritical ? const Color(0xFFB91C1C) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCritical ? const Color(0xFFFFE4E6) : const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 12),

                // Giant Real-Time Distance Counter (ตรงตามที่ผู้ใช้ส่งตัวอย่างมาเป๊ะๆ แต่สวยและโมเดิร์นกว่า)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'ระยะ',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$distanceMeters',
                        key: ValueKey<int>(distanceMeters),
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
                          letterSpacing: -1,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'M',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Mini Dynamic Route Progress Bar
                Stack(
                  children: [
                    Container(
                      height: 6,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: (1.0 - (distanceMeters / 3000.0)).clamp(0.1, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCritical
                                ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                                : [const Color(0xFF38BDF8), const Color(0xFF0284C7)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // AI Confidence Footnote
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🧠 AI Trajectory: ${(yieldProbability * 100).toInt()}% Yield Risk',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                      ),
                    ),
                    Text(
                      'แตะเพื่อเปิดแอพเต็มจอ ↗',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteAlertAppIcon(BuildContext context) {
    return InkWell(
      onTap: onReturnToApp,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00A896), Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00A896).withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.airport_shuttle_rounded, color: Colors.white, size: 28),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'RouteAlert',
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockIcon(IconData icon, Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}
