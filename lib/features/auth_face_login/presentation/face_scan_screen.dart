import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Instant Attention & Multi-frame Login
  bool _challengePassed = false;
  final List<List<double>> _loginFrameEmbeddings = [];
  double _scanProgress = 0.0;

  String _statusText = 'วางใบหน้าให้อยู่ในกรอบ';
  Color _statusColor = Colors.white;

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
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
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
          _statusText = 'ไม่พบกล้อง (เลือกรูปภาพทดสอบแทนได้)';
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
          _statusText = 'มองตรงไปยังกล้อง';
          _statusColor = Colors.white;
          break;
        case 1:
          _statusText = 'หันศีรษะไปทางซ้ายช้าๆ';
          _statusColor = const Color(0xFF60A5FA);
          break;
        case 2:
          _statusText = 'หันศีรษะไปทางขวาช้าๆ';
          _statusColor = const Color(0xFF60A5FA);
          break;
      }
    } else {
      if (!_challengePassed) {
        _statusText = 'วางใบหน้าให้อยู่ในกรอบ';
        _statusColor = Colors.white;
      } else {
        _statusText = 'กำลังสแกน Face ID (${(_scanProgress * 100).toInt()}%)...';
        _statusColor = const Color(0xFF34D399);
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
          _statusText = 'วางใบหน้าให้อยู่ในกรอบ';
          _statusColor = Colors.white70;
          _scanProgress = 0.0;
          _loginFrameEmbeddings.clear();
        });
        _isProcessingFrame = false;
        return;
      }

      if (faces.length > 1) {
        setState(() {
          _statusText = 'กรุณาอยู่หน้ากล้องคนเดียว';
          _statusColor = const Color(0xFFFBBF24);
          _scanProgress = 0.0;
          _loginFrameEmbeddings.clear();
        });
        _isProcessingFrame = false;
        return;
      }

      final face = faces.first;
      final imageWidth = cameraImage.width.toDouble();
      final imageHeight = cameraImage.height.toDouble();

      // 2. Validate Face Distance
      final faceBox = face.boundingBox;
      final faceRatio = faceBox.width / (imageWidth > imageHeight ? imageHeight : imageWidth);

      if (faceRatio < 0.20) {
        setState(() {
          _statusText = 'ขยับเข้ามาใกล้ขึ้นอีกนิด';
          _statusColor = const Color(0xFFFBBF24);
        });
        _isProcessingFrame = false;
        return;
      } else if (faceRatio > 0.88) {
        setState(() {
          _statusText = 'ถอยห่างออกมาอีกนิด';
          _statusColor = const Color(0xFFFBBF24);
        });
        _isProcessingFrame = false;
        return;
      }

      // 3. Extract Cropped Face Image
      final fullImage = ImageUtils.convertCameraImage(cameraImage);
      final croppedFace = ImageUtils.cropFace(fullImage, face.boundingBox);

      // 4. Liveness Texture & Eye Check
      final liveness = await _antiSpoofingService.checkLiveness(
        croppedFace: croppedFace,
        face: face,
      );

      if (!liveness.isReal) {
        setState(() {
          _statusText = liveness.message;
          _statusColor = const Color(0xFFF87171);
        });
        _isProcessingFrame = false;
        return;
      }

      // ================= LOGIN MODE =================
      if (widget.mode == FaceScanMode.login) {
        final isAttentive = _antiSpoofingService.isUserAttentive(face: face);

        if (!isAttentive) {
          setState(() {
            _statusText = 'มองตรงมายังหน้าจอ';
            _statusColor = Colors.white;
          });
          _isProcessingFrame = false;
          return;
        }

        _challengePassed = true;

        final embedding =
            await _recognitionService.extractFaceEmbedding(croppedFace);
        _loginFrameEmbeddings.add(embedding);

        final currentProgress = (_loginFrameEmbeddings.length / 3.0).clamp(0.0, 1.0);

        setState(() {
          _scanProgress = currentProgress;
          _statusText = 'กำลังสแกน Face ID...';
          _statusColor = const Color(0xFF34D399);
        });

        if (_loginFrameEmbeddings.length < 3) {
          await Future.delayed(const Duration(milliseconds: 70));
          _isProcessingFrame = false;
          return;
        }

        // Authenticate
        _isAuthenticating = true;
        final fusedEmbedding =
            FaceRecognitionService.combineMultiAngleEmbeddings(_loginFrameEmbeddings);

        final result =
            await FaceAuthRepository.authenticateWithFace(fusedEmbedding);

        if (!mounted) return;

        if (result.isSuccess && result.matchedUser != null) {
          HapticFeedback.heavyImpact();
          // Adaptive Learning in background
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
          angleMatched = true;
        } else if (_currentEnrollStep == 1 && angleY < -10.0) {
          angleMatched = true;
        } else if (_currentEnrollStep == 2 && angleY > 10.0) {
          angleMatched = true;
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
            await Future.delayed(const Duration(milliseconds: 700));
            _isProcessingFrame = false;
          } else {
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
    } catch (_) {
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
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: const BoxDecoration(
                color: Color(0xFF34D399),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.black, size: 44),
            ),
            const SizedBox(height: 18),
            Text(
              isNewRegistration ? 'ลงทะเบียน Face ID สำเร็จ' : 'ปลดล็อก Face ID สำเร็จ',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              user.name,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'AI Match ${(score * 100).toStringAsFixed(1)}% • ${user.role.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF34D399),
                ),
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 52,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'เข้าสู่ระบบ',
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
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.redAccent, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'ไม่สามารถยืนยันตัวตนได้',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _resetScanState();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23)),
                  elevation: 0,
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
      if (mounted) _showErrorModal('ไม่พบใบหน้าในรูปภาพที่เลือก');
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
          // 1. Fullscreen Native Quality Camera View
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
              color: Colors.black,
              child: Center(
                child: _hasCameraError
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_rounded,
                              color: Colors.white54, size: 56),
                          SizedBox(height: 12),
                          Text(
                            'กล้องไม่พร้อมใช้งาน (เลือกภาพทดสอบด้านล่างได้)',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(
                        color: Color(0xFF00A896)),
              ),
            ),

          // 2. Apple Face ID Minimalist Overlay Mask
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: AppleFaceIdCleanPainter(
                  statusColor: _statusColor,
                  pulseScale: _pulseAnimation.value,
                  scanProgress: _scanProgress,
                ),
              );
            },
          ),

          // 3. Apple Face ID Subtle Laser Sweep
          AnimatedBuilder(
            animation: _scanLineAnimation,
            builder: (context, child) {
              final height = MediaQuery.of(context).size.height;
              final ovalTop = height * 0.23;
              final ovalHeight = height * 0.40;
              final topOffset =
                  ovalTop + (ovalHeight * _scanLineAnimation.value);

              return Positioned(
                top: topOffset,
                left: MediaQuery.of(context).size.width * 0.20,
                right: MediaQuery.of(context).size.width * 0.20,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _statusColor.withValues(alpha: 0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // 4. Sleek Top Glassmorphic Navigation Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back Button (Glass Pill)
                      _buildGlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.pop(context),
                      ),

                      // Title (Apple Style)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.face_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            widget.mode == FaceScanMode.login
                                ? 'Face ID'
                                : 'ลงทะเบียนใบหน้า',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),

                      // Switch Camera Button
                      if (_cameras.length > 1)
                        _buildGlassIconButton(
                          icon: Icons.flip_camera_ios_rounded,
                          onTap: _switchCamera,
                        )
                      else
                        const SizedBox(width: 44),
                    ],
                  ),

                  // Minimalist Step Indicators for Registration
                  if (widget.mode == FaceScanMode.register)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStepDot(0, 'หน้าตรง'),
                          _buildStepLine(),
                          _buildStepDot(1, 'หันซ้าย'),
                          _buildStepLine(),
                          _buildStepDot(2, 'หันขวา'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 5. Floating Clean Apple Status Pill (Positioned right below oval)
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).size.height * 0.16,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      _statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 6. Minimal Bottom Fallback Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 34,
            child: Center(
              child: TextButton.icon(
                onPressed: _processImageFromPicker,
                icon: const Icon(Icons.photo_outlined,
                    color: Colors.white54, size: 16),
                label: const Text(
                  'เลือกภาพจากคลังภาพ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton(
      {required IconData icon, required VoidCallback onTap}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildStepDot(int stepIndex, String label) {
    final bool isDone = _currentEnrollStep > stepIndex;
    final bool isCurrent = _currentEnrollStep == stepIndex;

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
                ? const Color(0xFF00A896)
                : (isDone ? const Color(0xFF34D399) : Colors.white24),
          ),
          child: isDone
              ? const Icon(Icons.check, size: 10, color: Colors.black)
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: isCurrent ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine() {
    return Container(
      width: 16,
      height: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
  }
}

/// Authentic Clean Apple Face ID Painter with Smooth Corner Brackets
class AppleFaceIdCleanPainter extends CustomPainter {
  final Color statusColor;
  final double pulseScale;
  final double scanProgress;

  AppleFaceIdCleanPainter({
    required this.statusColor,
    required this.pulseScale,
    required this.scanProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.50)
      ..style = PaintingStyle.fill;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.43),
      width: size.width * 0.70 * pulseScale,
      height: size.height * 0.42 * pulseScale,
    );

    // Dark Background with Oval Window
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, bgPaint);

    // Sleek Apple Face ID Corner Brackets
    final cornerPaint = Paint()
      ..color = statusColor.withValues(alpha: 0.90)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final r = ovalRect;
    const cornerW = 28.0;
    const cornerH = 28.0;

    // Top-Left Corner
    final tlPath = Path()
      ..moveTo(r.left + 24, r.top + 6)
      ..lineTo(r.left + 24 + cornerW, r.top + 6)
      ..moveTo(r.left + 8, r.top + 22)
      ..lineTo(r.left + 8, r.top + 22 + cornerH);
    canvas.drawPath(tlPath, cornerPaint);

    // Top-Right Corner
    final trPath = Path()
      ..moveTo(r.right - 24, r.top + 6)
      ..lineTo(r.right - 24 - cornerW, r.top + 6)
      ..moveTo(r.right - 8, r.top + 22)
      ..lineTo(r.right - 8, r.top + 22 + cornerH);
    canvas.drawPath(trPath, cornerPaint);

    // Bottom-Left Corner
    final blPath = Path()
      ..moveTo(r.left + 24, r.bottom - 6)
      ..lineTo(r.left + 24 + cornerW, r.bottom - 6)
      ..moveTo(r.left + 8, r.bottom - 22)
      ..lineTo(r.left + 8, r.bottom - 22 - cornerH);
    canvas.drawPath(blPath, cornerPaint);

    // Bottom-Right Corner
    final brPath = Path()
      ..moveTo(r.right - 24, r.bottom - 6)
      ..lineTo(r.right - 24 - cornerW, r.bottom - 6)
      ..moveTo(r.right - 8, r.bottom - 22)
      ..lineTo(r.right - 8, r.bottom - 22 - cornerH);
    canvas.drawPath(brPath, cornerPaint);

    // Subtle Oval Border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant AppleFaceIdCleanPainter oldDelegate) => true;
}
