import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../core/ml/anti_spoofing_service.dart';
import '../../../core/ml/face_detector_service.dart';
import '../../../core/ml/face_recognition_service.dart';
import '../../../core/ml/image_utils.dart';
import '../../agency/presentation/agency_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';

enum FaceScanMode { login, register }

class FaceScanScreen extends StatefulWidget {
  final FaceScanMode mode;
  final String? registrationName;
  final String? registrationEmail;
  final String? registrationRole;

  // Compatibility aliases
  final String? registerName;
  final String? registerEmail;
  final String? registerRole;

  const FaceScanScreen({
    super.key,
    required this.mode,
    this.registrationName,
    this.registrationEmail,
    this.registrationRole,
    this.registerName,
    this.registerEmail,
    this.registerRole,
  });

  String get effectiveName => registrationName ?? registerName ?? 'ผู้ใช้ RouteAlert';
  String get effectiveEmail => registrationEmail ?? registerEmail ?? 'user@routealert.com';
  String get effectiveRole => registrationRole ?? registerRole ?? 'driver';

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  bool _isAuthenticating = false;
  bool _hasCameraError = false;

  final FaceDetectorService _detectorService = FaceDetectorService();
  final AntiSpoofingService _antiSpoofingService = AntiSpoofingService();
  final FaceRecognitionService _recognitionService = FaceRecognitionService();

  // Multi-Angle Registration: 0 = Front, 1 = Left, 2 = Right
  int _currentEnrollStep = 0;
  final List<List<double>> _collectedEmbeddings = [];

  // Interactive Liveness & Multi-frame Login
  final LivenessChallenge _currentChallenge = LivenessChallenge.blink;
  bool _challengePassed = false;
  final List<List<double>> _loginFrameEmbeddings = [];
  double _scanProgress = 0.0;

  String _statusText = 'กำลังเตรียมระบบ Face ID...';
  Color _statusColor = const Color(0xFF00A896);

  late AnimationController _animController;
  late Animation<double> _scanLineAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initServicesAndCamera();
  }

  void _initAnimations() {
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
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
      ResolutionPreset.high,
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
        _resetScanState();
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

  void _resetScanState() {
    _isProcessingFrame = false;
    _isAuthenticating = false;
    _challengePassed = false;
    _loginFrameEmbeddings.clear();
    _scanProgress = 0.0;
    _antiSpoofingService.resetChallenge();
    _updateInstructionText();
  }

  void _updateInstructionText() {
    if (widget.mode == FaceScanMode.register) {
      switch (_currentEnrollStep) {
        case 0:
          _statusText = 'มุมที่ 1/3: กรุณามองตรงไปยังกล้อง';
          _statusColor = const Color(0xFF00A896);
          break;
        case 1:
          _statusText = 'มุมที่ 2/3: กรุณาหันศีรษะไปทางซ้ายช้าๆ';
          _statusColor = const Color(0xFF5B9EE1);
          break;
        case 2:
          _statusText = 'มุมที่ 3/3: กรุณาหันศีรษะไปทางขวาช้าๆ';
          _statusColor = const Color(0xFF5B9EE1);
          break;
      }
    } else {
      if (!_challengePassed) {
        _statusText = '👁️ กรุณากะพริบตา 1 ครั้งเพื่อยืนยันบุคคลจริง (Liveness)';
        _statusColor = const Color(0xFF00A896);
      } else {
        _statusText = 'กำลังสแกนวิเคราะห์ใบหน้า 3 มิติ (${(_scanProgress * 100).toInt()}%)...';
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

      if (!mounted) {
        _isProcessingFrame = false;
        return;
      }

      // 1. Check face presence
      if (faces.isEmpty) {
        setState(() {
          _statusText = 'กรุณาวางใบหน้าให้อยู่กึ่งกลางกรอบสแกน';
          _statusColor = Colors.orangeAccent;
          _scanProgress = 0.0;
          _loginFrameEmbeddings.clear();
        });
        _isProcessingFrame = false;
        return;
      }

      if (faces.length > 1) {
        setState(() {
          _statusText = 'ตรวจพบมากกว่า 1 ใบหน้า กรุณาอยู่หน้ากล้องคนเดียว';
          _statusColor = Colors.amber;
          _scanProgress = 0.0;
          _loginFrameEmbeddings.clear();
        });
        _isProcessingFrame = false;
        return;
      }

      final Face face = faces.first;
      final imageWidth = cameraImage.width.toDouble();
      final imageHeight = cameraImage.height.toDouble();

      // 2. Validate Face Size & Distance
      final faceBox = face.boundingBox;
      final faceRatio = faceBox.width / (imageWidth > imageHeight ? imageHeight : imageWidth);

      if (faceRatio < 0.20) {
        setState(() {
          _statusText = 'ขยับใบหน้าเข้ามาใกล้กล้องอีกนิด';
          _statusColor = Colors.orangeAccent;
        });
        _isProcessingFrame = false;
        return;
      } else if (faceRatio > 0.88) {
        setState(() {
          _statusText = 'ถอยใบหน้าห่างออกมาอีกนิด';
          _statusColor = Colors.orangeAccent;
        });
        _isProcessingFrame = false;
        return;
      }

      // 3. Extract Cropped Face Image
      final fullImage = ImageUtils.convertCameraImage(cameraImage);
      final croppedFace = ImageUtils.cropFace(fullImage, face.boundingBox);

      // 4. Liveness Texture & Eye Open Check
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

      // ================= LOGIN MODE =================
      if (widget.mode == FaceScanMode.login) {
        // Step A: Interactive Liveness Challenge
        if (!_challengePassed) {
          final isChallengeComplete = _antiSpoofingService
              .evaluateInteractiveChallenge(
                  face: face, challenge: _currentChallenge);

          if (!isChallengeComplete) {
            setState(() {
              _statusText = '👁️ กรุณากะพริบตา 1 ครั้งเพื่อยืนยันบุคคลจริง';
              _statusColor = const Color(0xFF00A896);
            });
            _isProcessingFrame = false;
            return;
          } else {
            HapticFeedback.mediumImpact();
            _challengePassed = true;
          }
        }

        // Step B: Multi-Frame Temporal Fusion (Collect 3 high-quality frames for 100% precision)
        final embedding =
            await _recognitionService.extractFaceEmbedding(croppedFace);
        _loginFrameEmbeddings.add(embedding);

        final currentProgress = (_loginFrameEmbeddings.length / 3.0).clamp(0.0, 1.0);

        setState(() {
          _scanProgress = currentProgress;
          _statusText = 'กำลังสแกน MobileFaceNet (${(currentProgress * 100).toInt()}%)...';
          _statusColor = const Color(0xFF52E197);
        });

        if (_loginFrameEmbeddings.length < 3) {
          await Future.delayed(const Duration(milliseconds: 100));
          _isProcessingFrame = false;
          return;
        }

        // Authenticate with Fused Embedding
        _isAuthenticating = true;
        final fusedEmbedding =
            FaceRecognitionService.combineMultiAngleEmbeddings(_loginFrameEmbeddings);

        final result =
            await FaceAuthRepository.authenticateWithFace(fusedEmbedding);

        if (!mounted) return;

        if (result.isSuccess && result.matchedUser != null) {
          HapticFeedback.heavyImpact();
          // Adaptive Learning: Continuous Vector Refinement in background
          FaceAuthRepository.updateAdaptiveFaceEmbedding(
            user: result.matchedUser!,
            scannedEmbedding: fusedEmbedding,
            similarityScore: result.similarityScore,
          );
          _showSuccessModal(result.matchedUser!, result.similarityScore);
        } else {
          HapticFeedback.vibrate();
          _showErrorModal(result.message);
        }
      }
      // ================= REGISTER MODE =================
      else {
        final double angleY = face.headEulerAngleY ?? 0.0;

        bool angleMatched = false;
        if (_currentEnrollStep == 0 && angleY.abs() < 10.0) {
          angleMatched = true; // Looking straight
        } else if (_currentEnrollStep == 1 && angleY < -10.0) {
          angleMatched = true; // Turned Left (User's perspective)
        } else if (_currentEnrollStep == 2 && angleY > 10.0) {
          angleMatched = true; // Turned Right (User's perspective)
        }

        if (angleMatched) {
          HapticFeedback.mediumImpact();
          final embedding =
              await _recognitionService.extractFaceEmbedding(croppedFace);
          _collectedEmbeddings.add(embedding);
          _currentEnrollStep++;

          if (_currentEnrollStep < 3) {
            setState(() {
              _updateInstructionText();
            });
            await Future.delayed(const Duration(milliseconds: 800));
            _isProcessingFrame = false;
          } else {
            // Finished 3 Angles: Combine & Save Profile
            _isAuthenticating = true;
            final masterEmbedding =
                FaceRecognitionService.combineMultiAngleEmbeddings(
                    _collectedEmbeddings);

            final profile = UserFaceProfile(
              id: widget.effectiveEmail,
              name: widget.effectiveName,
              email: widget.effectiveEmail,
              role: widget.effectiveRole,
              faceEmbedding: masterEmbedding,
              registeredAt: DateTime.now(),
            );

            await FaceAuthRepository.registerUser(profile);

            if (!mounted) return;
            HapticFeedback.heavyImpact();
            _showSuccessModal(profile, 1.0, isNewRegistration: true);
          }
        } else {
          _isProcessingFrame = false;
        }
      }
    } catch (e) {
      _isProcessingFrame = false;
    }
  }

  void _showSuccessModal(UserFaceProfile user, double score,
      {bool isNewRegistration = false}) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFE6F7F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF00A896), size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              isNewRegistration
                  ? 'ลงทะเบียน Face ID สำเร็จ!'
                  : 'ยืนยันตัวตนสำเร็จ (Face ID Match)',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'ยินดีต้อนรับคุณ ${user.name}',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 16, color: Color(0xFF00A896)),
                  const SizedBox(width: 6),
                  Text(
                    'ความแม่นยำ AI: ${(score * 100).toStringAsFixed(1)}% | บทบาท: ${user.role.toUpperCase()}',
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
                      targetScreen = const DriverMainScreen();
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
                ),
                child: const Text(
                  'เข้าสู่หน้าหลัก',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
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
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 40),
            ),
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
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _resetScanState();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A896),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                child: const Text('ลองใหม่อีกครั้ง',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
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
    setState(() {
      _isCameraInitialized = false;
      _resetScanState();
    });
    await _initCamera(_cameras[_selectedCameraIndex]);
  }

  void _processImageFromPicker() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1000,
      maxHeight: 1000,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;

    final faces = await _detectorService.detectFacesFromPath(picked.path);

    if (faces.isEmpty) {
      if (mounted) _showErrorModal('ไม่พบใบหน้าในรูปภาพที่เลือก กรุณาเลือกรูปใหม่');
      return;
    }

    final cropped = ImageUtils.cropFace(decoded, faces.first.boundingBox);
    final embedding = await _recognitionService.extractFaceEmbedding(cropped);

    if (widget.mode == FaceScanMode.register) {
      final profile = UserFaceProfile(
        id: widget.effectiveEmail,
        name: widget.effectiveName,
        email: widget.effectiveEmail,
        role: widget.effectiveRole,
        faceEmbedding: embedding,
        registeredAt: DateTime.now(),
      );
      await FaceAuthRepository.registerUser(profile);
      if (mounted) _showSuccessModal(profile, 1.0, isNewRegistration: true);
    } else {
      final result = await FaceAuthRepository.authenticateWithFace(embedding);
      if (mounted) {
        if (result.isSuccess && result.matchedUser != null) {
          _showSuccessModal(result.matchedUser!, result.similarityScore);
        } else {
          _showErrorModal(result.message);
        }
      }
    }
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
          // 1. Fullscreen Native Quality Camera View (Aspect-Ratio Preserved)
          if (_isCameraInitialized && _cameraController != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final cameraAspect = _cameraController!.value.aspectRatio;

                return SizedBox(
                  width: size.width,
                  height: size.height,
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: size.width,
                        height: size.width * cameraAspect,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                );
              },
            )
          else
            Container(
              color: const Color(0xFF0F172A),
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

          // 2. Apple Face ID Style Biometric Ring Overlay
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: AppleFaceIdPainter(
                  statusColor: _statusColor,
                  pulseScale: _pulseAnimation.value,
                  scanProgress: _scanProgress,
                  isPassed: _challengePassed,
                ),
              );
            },
          ),

          // 3. Apple Face ID Laser Scan Sweep
          AnimatedBuilder(
            animation: _scanLineAnimation,
            builder: (context, child) {
              final height = MediaQuery.of(context).size.height;
              final ovalTop = height * 0.20;
              final ovalHeight = height * 0.44;
              final topOffset =
                  ovalTop + (ovalHeight * _scanLineAnimation.value);

              return Positioned(
                top: topOffset,
                left: MediaQuery.of(context).size.width * 0.16,
                right: MediaQuery.of(context).size.width * 0.16,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _statusColor.withValues(alpha: 0.95),
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
                            ? 'Apple Face ID Biometrics'
                            : 'ลงทะเบียนใบหน้า 3 มุมมอง',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
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
                          _buildAngleStepBadge('1. หน้าตรง',
                              _currentEnrollStep >= 0, _currentEnrollStep == 0),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              color: Colors.white38, size: 14),
                          const SizedBox(width: 8),
                          _buildAngleStepBadge('2. หันซ้าย',
                              _currentEnrollStep >= 1, _currentEnrollStep == 1),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward,
                              color: Colors.white38, size: 14),
                          const SizedBox(width: 8),
                          _buildAngleStepBadge('3. หันขวา',
                              _currentEnrollStep >= 2, _currentEnrollStep == 2),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 5. Apple Face ID Live Status Indicator
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
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _statusColor.withValues(alpha: 0.6),
                          width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _challengePassed
                              ? Icons.verified_user_rounded
                              : Icons.face_retouching_natural_rounded,
                          size: 20,
                          color: _statusColor,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _statusText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
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
                          'Anti-Spoofing', Icons.verified_user_rounded),
                      const SizedBox(width: 8),
                      _buildModelChip('MobileFaceNet AI', Icons.memory_rounded),
                    ],
                  ),
                  const SizedBox(height: 16),
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

/// Custom Painter creating the Apple Face ID Biometric Ring & Mask
class AppleFaceIdPainter extends CustomPainter {
  final Color statusColor;
  final double pulseScale;
  final double scanProgress;
  final bool isPassed;

  AppleFaceIdPainter({
    required this.statusColor,
    required this.pulseScale,
    required this.scanProgress,
    required this.isPassed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.58)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.72 * pulseScale,
      height: size.height * 0.44 * pulseScale,
    );

    // Darkened Background with Oval Window
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, bgPaint);

    // Outer Glow Ring
    final glowPaint = Paint()
      ..color = statusColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawOval(ovalRect, glowPaint);

    // Base Frame Oval
    final borderPaint = Paint()
      ..color = statusColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    canvas.drawOval(ovalRect, borderPaint);

    // Face ID 4-Corner Tick Marks (Apple Style)
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const cornerLength = 24.0;
    final r = ovalRect;

    // Top-Left
    canvas.drawLine(Offset(r.left + 20, r.top), Offset(r.left + 20 + cornerLength, r.top), tickPaint);
    canvas.drawLine(Offset(r.left, r.top + 20), Offset(r.left, r.top + 20 + cornerLength), tickPaint);

    // Top-Right
    canvas.drawLine(Offset(r.right - 20, r.top), Offset(r.right - 20 - cornerLength, r.top), tickPaint);
    canvas.drawLine(Offset(r.right, r.top + 20), Offset(r.right, r.top + 20 + cornerLength), tickPaint);

    // Bottom-Left
    canvas.drawLine(Offset(r.left + 20, r.bottom), Offset(r.left + 20 + cornerLength, r.bottom), tickPaint);
    canvas.drawLine(Offset(r.left, r.bottom - 20), Offset(r.left, r.bottom - 20 - cornerLength), tickPaint);

    // Bottom-Right
    canvas.drawLine(Offset(r.right - 20, r.bottom), Offset(r.right - 20 - cornerLength, r.bottom), tickPaint);
    canvas.drawLine(Offset(r.right, r.bottom - 20), Offset(r.right, r.bottom - 20 - cornerLength), tickPaint);
  }

  @override
  bool shouldRepaint(covariant AppleFaceIdPainter oldDelegate) => true;
}
