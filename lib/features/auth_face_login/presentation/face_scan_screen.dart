import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../../core/ml/anti_spoofing_service.dart';
import '../../../../core/ml/face_detector_service.dart';
import '../../../../core/ml/face_recognition_service.dart';
import '../../../../core/ml/image_utils.dart';
import '../../agency/presentation/agency_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import 'user_type_screen.dart';

enum FaceScanMode { login, register }

class FaceScanScreen extends StatefulWidget {
  final FaceScanMode mode;
  final String? registrationEmail;
  final String? registrationName;

  const FaceScanScreen({
    super.key,
    required this.mode,
    this.registrationEmail,
    this.registrationName,
  });

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 1;

  final FaceDetectorService _detectorService = FaceDetectorService();
  final AntiSpoofingService _antiSpoofingService = AntiSpoofingService();
  final FaceRecognitionService _recognitionService = FaceRecognitionService();

  bool _isProcessingFrame = false;
  bool _isCameraInitialized = false;
  bool _hasCameraError = false;

  String _statusText = 'กำลังเตรียมกล้องและโหลดโมเดล AI...';
  Color _statusColor = const Color(0xFF5B9EE1);
  bool _isAuthenticating = false;

  // Interactive Liveness Challenge State
  final LivenessChallenge _currentChallenge = LivenessChallenge.blink;
  bool _challengePassed = false;

  // Multi-Angle Registration State (3 Angles: Center -> Left -> Right)
  int _currentEnrollStep = 0; // 0: Center, 1: Left, 2: Right
  final List<List<double>> _collectedEmbeddings = [];

  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _initServicesAndCamera();
  }

  Future<void> _initServicesAndCamera() async {
    await _antiSpoofingService.initialize();
    await _recognitionService.initialize();

    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final frontIndex = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.front);
        _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;
        await _initCamera(_cameras[_selectedCameraIndex]);
      } else {
        setState(() {
          _hasCameraError = true;
          _statusText = 'ไม่พบกล้อง (สามารถใช้โหมดเลือกภาพทดสอบแทนได้)';
        });
      }
    } catch (e) {
      setState(() {
        _hasCameraError = true;
        _statusText = 'ไม่สามารถเปิดกล้องได้: $e';
      });
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _updateInstructionText();
      });

      _cameraController!.startImageStream(_processCameraFrame);
    } catch (e) {
      setState(() {
        _hasCameraError = true;
        _statusText = 'เปิดใช้งานกล้องไม่สำเร็จ: $e';
      });
    }
  }

  void _updateInstructionText() {
    if (widget.mode == FaceScanMode.register) {
      switch (_currentEnrollStep) {
        case 0:
          _statusText = 'มุมที่ 1/3: กรุณามองตรงไปยังกล้อง';
          _statusColor = const Color(0xFF5B9EE1);
          break;
        case 1:
          _statusText = 'มุมที่ 2/3: กรุณาเอียงศีรษะไปทางซ้ายเล็กน้อย';
          _statusColor = Colors.orangeAccent;
          break;
        case 2:
          _statusText = 'มุมที่ 3/3: กรุณาเอียงศีรษะไปทางขวาเล็กน้อย';
          _statusColor = const Color(0xFF00A896);
          break;
      }
    } else {
      if (!_challengePassed) {
        _statusText = '👁️ กรุณากะพริบตา 1 ครั้งเพื่อยืนยันบุคคลจริง (Liveness)';
        _statusColor = const Color(0xFF00A896);
      } else {
        _statusText = 'ผ่าน Liveness! กำลังค้นหาบัญชีผู้ใช้...';
        _statusColor = const Color(0xFF52E197);
      }
    }
  }

  void _processCameraFrame(CameraImage cameraImage) async {
    if (_isProcessingFrame || _isAuthenticating || !mounted) return;
    _isProcessingFrame = true;

    try {
      final faces = await _detectorService.detectFacesFromCamera(
        cameraImage: cameraImage,
        camera: _cameras[_selectedCameraIndex],
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          _statusText = 'กำลังค้นหาใบหน้า... (BlazeFace / MediaPipe)';
          _statusColor = Colors.orangeAccent;
        });
        _isProcessingFrame = false;
        return;
      }

      if (faces.length > 1) {
        setState(() {
          _statusText = 'ตรวจพบมากกว่า 1 ใบหน้า กรุณาอยู่หน้ากล้องคนเดียว';
          _statusColor = Colors.amber;
        });
        _isProcessingFrame = false;
        return;
      }

      final Face face = faces.first;

      // Check Passive Liveness Texture & Spoof Model
      final fullImage = ImageUtils.convertCameraImage(cameraImage);
      final croppedFace = ImageUtils.cropFace(fullImage, face.boundingBox);

      final liveness = await _antiSpoofingService.checkLiveness(
        croppedFace: croppedFace,
        face: face,
      );

      if (!liveness.isReal) {
        setState(() {
          _statusText = liveness.message;
          _statusColor = Colors.redAccent;
        });
        _isProcessingFrame = false;
        return;
      }

      // LOGIN MODE: Perform Interactive Liveness Challenge (Blink)
      if (widget.mode == FaceScanMode.login) {
        if (!_challengePassed) {
          final isChallengeComplete = _antiSpoofingService
              .evaluateInteractiveChallenge(
                  face: face, challenge: _currentChallenge);

          if (!isChallengeComplete) {
            setState(() {
              _statusText = '👁️ กรุณากะพริบตา 1 ครั้งเพื่อยืนยันบุคคลจริง (Liveness)';
              _statusColor = const Color(0xFF00A896);
            });
            _isProcessingFrame = false;
            return;
          } else {
            _challengePassed = true;
          }
        }

        // Recognition Phase
        setState(() {
          _statusText = 'ผ่าน Liveness! กำลังจดจำใบหน้าด้วย MobileFaceNet...';
          _statusColor = const Color(0xFF52E197);
          _isAuthenticating = true;
        });

        final embedding =
            await _recognitionService.extractFaceEmbedding(croppedFace);
        final result =
            await FaceAuthRepository.authenticateWithFace(embedding);

        if (!mounted) return;

        if (result.isSuccess && result.matchedUser != null) {
          _showSuccessModal(result.matchedUser!, result.similarityScore);
        } else {
          _showErrorModal(result.message);
        }
      }
      // REGISTER MODE: Multi-Angle Capture Stepper (Center -> Left -> Right)
      else {
        final double angleY = face.headEulerAngleY ?? 0.0;

        bool angleMatched = false;
        if (_currentEnrollStep == 0 && angleY.abs() < 12.0) {
          angleMatched = true; // Looking straight
        } else if (_currentEnrollStep == 1 && angleY > 10.0) {
          angleMatched = true; // Turned Left
        } else if (_currentEnrollStep == 2 && angleY < -10.0) {
          angleMatched = true; // Turned Right
        }

        if (angleMatched) {
          final embedding =
              await _recognitionService.extractFaceEmbedding(croppedFace);
          _collectedEmbeddings.add(embedding);
          _currentEnrollStep++;

          if (_currentEnrollStep < 3) {
            setState(() {
              _updateInstructionText();
            });
            await Future.delayed(const Duration(milliseconds: 700));
            _isProcessingFrame = false;
            return;
          } else {
            // All 3 angles captured! Fuse embeddings
            setState(() {
              _isAuthenticating = true;
              _statusText = 'บันทึกใบหน้าครบทั้ง 3 มุมมองเรียบร้อย!';
              _statusColor = const Color(0xFF00A896);
            });

            final combinedEmbedding =
                FaceRecognitionService.combineMultiAngleEmbeddings(
                    _collectedEmbeddings);

            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              Navigator.pop(context, combinedEmbedding);
            }
          }
        } else {
          setState(() {
            _updateInstructionText();
          });
          _isProcessingFrame = false;
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'เกิดข้อผิดพลาด: $e';
          _statusColor = Colors.redAccent;
        });
      }
    } finally {
      if (mounted && !_isAuthenticating) {
        _isProcessingFrame = false;
      }
    }
  }

  Future<void> _processImageFromPicker() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _isAuthenticating = true;
      _statusText = 'กำลังวิเคราะห์ภาพจากคลังรูปภาพ...';
      _statusColor = const Color(0xFF5B9EE1);
    });

    try {
      final faces = await _detectorService.detectFacesFromPath(pickedFile.path);
      if (faces.isEmpty) {
        _showErrorModal('ไม่พบใบหน้าในรูปภาพที่เลือก');
        return;
      }

      final bytes = await File(pickedFile.path).readAsBytes();
      final fullImage = img.decodeImage(bytes);
      if (fullImage == null) {
        _showErrorModal('ไม่สามารถประมวลผลรูปภาพได้');
        return;
      }

      final croppedFace =
          ImageUtils.cropFace(fullImage, faces.first.boundingBox);
      final liveness = await _antiSpoofingService.checkLiveness(
        croppedFace: croppedFace,
        face: faces.first,
      );

      if (!liveness.isReal) {
        _showErrorModal(liveness.message);
        return;
      }

      final embedding =
          await _recognitionService.extractFaceEmbedding(croppedFace);

      if (widget.mode == FaceScanMode.register) {
        if (mounted) Navigator.pop(context, embedding);
      } else {
        final result =
            await FaceAuthRepository.authenticateWithFace(embedding);
        if (!mounted) return;
        if (result.isSuccess && result.matchedUser != null) {
          _showSuccessModal(result.matchedUser!, result.similarityScore);
        } else {
          _showErrorModal(result.message);
        }
      }
    } catch (e) {
      _showErrorModal('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  void _showSuccessModal(UserFaceProfile user, double similarityScore) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00A896).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF00A896),
                size: 64,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'จดจำใบหน้าสำเร็จ!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'ยินดีต้อนรับคุณ ${user.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF00A896),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.email,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_rounded,
                      size: 16, color: Color(0xFF00A896)),
                  const SizedBox(width: 6),
                  Text(
                    'ความแม่นยำ AI: ${(similarityScore * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Automatic role-based routing
                  Widget targetScreen;
                  switch (user.role) {
                    case 'ambulance':
                      targetScreen = const AmbulanceMainScreen();
                      break;
                    case 'agency':
                      targetScreen = const AgencyMainScreen();
                      break;
                    case 'driver':
                      targetScreen = const DriverMainScreen();
                      break;
                    default:
                      targetScreen = const UserTypeScreen();
                  }

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => targetScreen),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A896),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'เข้าสู่ระบบทันที',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorModal(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 64),
            const SizedBox(height: 16),
            const Text(
              'การยืนยันตัวตนไม่สำเร็จ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isAuthenticating = false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B9EE1),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('ลองใหม่อีกครั้ง',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _cameraController?.dispose();
    setState(() => _isCameraInitialized = false);
    await _initCamera(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _detectorService.dispose();
    _antiSpoofingService.dispose();
    _recognitionService.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera View
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Container(
              color: const Color(0xFF1E293B),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_rounded,
                        color: Colors.white54, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      _hasCameraError
                          ? 'กล้องไม่พร้อมใช้งาน (โหมด Simulator)'
                          : 'กำลังเตรียมระบบสแกน...',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Semi-transparent Face Hole Overlay
          CustomPaint(
            size: Size.infinite,
            painter: FaceHolePainter(),
          ),

          // 3. Laser Scan Bar
          AnimatedBuilder(
            animation: _scanLineAnimation,
            builder: (context, child) {
              final height = MediaQuery.of(context).size.height;
              final ovalTop = height * 0.22;
              final ovalHeight = height * 0.45;
              final topOffset =
                  ovalTop + (ovalHeight * _scanLineAnimation.value);

              return Positioned(
                top: topOffset,
                left: MediaQuery.of(context).size.width * 0.15,
                right: MediaQuery.of(context).size.width * 0.15,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _statusColor.withValues(alpha: 0.9),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _statusColor.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // 4. Header Bar with Multi-Angle Stepper
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        widget.mode == FaceScanMode.login
                            ? 'Face Login & Liveness'
                            : 'ลงทะเบียนใบหน้า 3 มุมมอง',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_cameras.length > 1)
                        IconButton(
                          icon: const Icon(Icons.cameraswitch_rounded,
                              color: Colors.white),
                          onPressed: _switchCamera,
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),

                  // Stepper for multi-angle registration
                  if (widget.mode == FaceScanMode.register)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAngleStepBadge('1. หน้าตรง', _currentEnrollStep >= 0, _currentEnrollStep == 0),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, color: Colors.white38, size: 14),
                          const SizedBox(width: 8),
                          _buildAngleStepBadge('2. หันซ้าย', _currentEnrollStep >= 1, _currentEnrollStep == 1),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, color: Colors.white38, size: 14),
                          const SizedBox(width: 8),
                          _buildAngleStepBadge('3. หันขวา', _currentEnrollStep >= 2, _currentEnrollStep == 2),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 5. Bottom Status Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.88),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: _statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_rounded,
                            size: 18, color: _statusColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModelChip('BlazeFace', Icons.center_focus_strong),
                      const SizedBox(width: 8),
                      _buildModelChip(
                          'Anti-Spoofing & Liveness', Icons.verified_user),
                      const SizedBox(width: 8),
                      _buildModelChip('MobileFaceNet', Icons.memory),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _processImageFromPicker,
                    icon: const Icon(Icons.photo_library_rounded,
                        color: Colors.white70, size: 18),
                    label: const Text(
                      'เลือกรูปภาพทดสอบ (Simulator Fallback)',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleStepBadge(String title, bool isCompleted, bool isCurrent) {
    final color = isCurrent
        ? const Color(0xFF00A896)
        : (isCompleted ? const Color(0xFF52E197) : Colors.white38);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF00A896).withValues(alpha: 0.25)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildModelChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white60),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class FaceHolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.72,
      height: size.height * 0.46,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = const Color(0xFF00A896)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
