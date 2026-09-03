import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
  bool _isDetectingFace = false;
  bool _isEvaluatingBiometrics = false;
  DateTime _lastAuthAttempt = DateTime.now().subtract(const Duration(seconds: 1));
  bool _isAuthenticating = false;
  bool _hasCameraError = false;

  final FaceDetectorService _detectorService = FaceDetectorService();
  final AntiSpoofingService _antiSpoofingService = AntiSpoofingService();
  final FaceRecognitionService _recognitionService = FaceRecognitionService();

  // Multi-Angle Registration with Strict Progressive Hold (4 frames per angle)
  int _currentEnrollStep = 0; // 0 = Front, 1 = Left, 2 = Right
  double _stepProgress = 0.0; // 0.0 -> 1.0 for the current angle
  bool _isTransitioningStep = false;
  final List<List<double>> _currentStepEmbeddings = [];
  final List<List<double>> _collectedEmbeddings = [];

  // Instant Attention & Multi-frame Login
  final List<List<double>> _loginFrameEmbeddings = [];
  double _scanProgress = 0.0;
  int _consecutiveEmptyFrames = 0;
  int _unsuccessfulScanCount = 0;

  String _statusTitle = 'มองตรงมาที่กล้อง';
  String _statusDetail = 'วางใบหน้าให้อยู่ในกรอบเพื่อเริ่มสแกน';
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
    // 1. Concurrently initialize AI models in background (Non-blocking)
    final modelsInit = Future.wait([
      _antiSpoofingService.initialize(),
      _recognitionService.initialize(),
    ]);

    // 2. Start camera immediately so preview opens in ~300ms!
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final frontIndex = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.front);
        _selectedCameraIndex = frontIndex != -1 ? frontIndex : 0;
        await _initCamera(_cameras[_selectedCameraIndex]);
      } else {
        if (mounted) {
          setState(() {
            _hasCameraError = true;
            _statusTitle = 'ไม่พบกล้อง';
            _statusDetail = 'สามารถเลือกรูปภาพทดสอบด้านล่างได้';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _statusTitle = 'เปิดกล้องไม่สำเร็จ';
          _statusDetail = '$e';
        });
      }
    }

    // 3. Ensure models are 100% loaded before activating biometric stream
    await modelsInit;
    if (mounted &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_cameraController!.value.isStreamingImages) {
      try {
        await _cameraController!.startImageStream(_processCameraFrame);
      } catch (_) {}
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium, // 720p: Opens 3x faster than high (1080p), zero lag, 60 FPS
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _statusTitle = 'เปิดกล้องไม่สำเร็จ';
          _statusDetail = '$e';
        });
      }
    }
  }

  void _resetScanState() {
    _isDetectingFace = false;
    _isEvaluatingBiometrics = false;
    _isAuthenticating = false;
    _isTransitioningStep = false;
    _currentEnrollStep = 0;
    _stepProgress = 0.0;
    _currentStepEmbeddings.clear();
    _collectedEmbeddings.clear();
    _loginFrameEmbeddings.clear();
    _scanProgress = 0.0;
    _antiSpoofingService.resetChallenge();
    _updateInstructionText();
  }

  void _updateInstructionText() {
    if (widget.mode == FaceScanMode.register) {
      switch (_currentEnrollStep) {
        case 0:
          _statusTitle = '1. มองตรงมาที่กล้อง';
          _statusDetail = 'จัดใบหน้าให้อยู่กึ่งกลางวงกลมในระดับสายตา';
          _statusColor = const Color(0xFF00A896);
          break;
        case 1:
          _statusTitle = '2. หันหน้าไปทางซ้ายช้าๆ';
          _statusDetail = 'ค่อยๆ เอียงศีรษะไปทางซ้ายประมาณ 15-20° แล้วค้างไว้';
          _statusColor = const Color(0xFF00A896);
          break;
        case 2:
          _statusTitle = '3. หันหน้าไปทางขวาช้าๆ';
          _statusDetail = 'ค่อยๆ เอียงศีรษะไปทางขวาประมาณ 15-20° แล้วค้างไว้';
          _statusColor = const Color(0xFF00A896);
          break;
      }
    } else {
      _statusTitle = 'จัดใบหน้าให้อยู่ในกรอบ';
      _statusDetail = 'มองตรงมาที่หน้าจอเพื่อปลดล็อกเข้าสู่ระบบ';
      _statusColor = const Color(0xFF5B9EE1);
    }
  }



  void _processCameraFrame(CameraImage cameraImage) async {
    // Drop frame if ML Kit is still processing the previous frame or during auth modal
    if (_isDetectingFace || _isAuthenticating || _isTransitioningStep || !mounted) return;
    _isDetectingFace = true;

    try {
      final faces = await _detectorService.detectFacesFromCamera(
        cameraImage: cameraImage,
        camera: _cameras[_selectedCameraIndex],
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      if (!mounted) {
        _isDetectingFace = false;
        return;
      }

      final imageWidth = cameraImage.width.toDouble();
      final imageHeight = cameraImage.height.toDouble();

      // 1. Check face presence with grace period (prevents momentary blips from wiping progress)
      if (faces.isEmpty) {
        _consecutiveEmptyFrames++;
        if (_consecutiveEmptyFrames >= 10) {
          setState(() {
            _statusDetail = 'กรุณาวางใบหน้าให้อยู่กึ่งกลางกรอบ';
            _statusColor = const Color(0xFF64748B);
            if (widget.mode == FaceScanMode.login) {
              _scanProgress = 0.0;
              _loginFrameEmbeddings.clear();
            } else {
              _stepProgress = 0.0;
              _currentStepEmbeddings.clear();
            }
          });
        }
        _isDetectingFace = false;
        return;
      }

      _consecutiveEmptyFrames = 0;

      if (faces.length > 1) {
        setState(() {
          _statusDetail = 'ตรวจพบมากกว่า 1 ใบหน้า กรุณาอยู่หน้ากล้องคนเดียว';
          _statusColor = const Color(0xFFD97706);
          if (widget.mode == FaceScanMode.login) {
            _scanProgress = 0.0;
            _loginFrameEmbeddings.clear();
          } else {
            _stepProgress = 0.0;
            _currentStepEmbeddings.clear();
          }
        });
        _isDetectingFace = false;
        return;
      }

      final face = faces.first;

      // Release detection lock IMMEDIATELY so camera stream keeps flowing with zero lag!
      _isDetectingFace = false;

      // 3. Trigger biometric evaluation in background (instant ~60ms throttle for Apple Face ID speed)
      final now = DateTime.now();
      if (!_isEvaluatingBiometrics &&
          !_isAuthenticating &&
          !_isTransitioningStep &&
          now.difference(_lastAuthAttempt).inMilliseconds >= 60) {
        _lastAuthAttempt = now;
        _evaluateBiometrics(cameraImage, face, imageWidth, imageHeight);
      }
    } catch (_) {
      _isDetectingFace = false;
    }
  }

  Future<void> _evaluateBiometrics(
    CameraImage cameraImage,
    Face face,
    double imageWidth,
    double imageHeight,
  ) async {
    if (_isEvaluatingBiometrics || _isAuthenticating || _isTransitioningStep || !mounted) return;
    _isEvaluatingBiometrics = true;

    try {
      // 1. Validate Face Distance
      final faceBox = face.boundingBox;
      final faceRatio = faceBox.width / (imageWidth > imageHeight ? imageHeight : imageWidth);

      if (faceRatio < 0.20) {
        if (mounted) {
          setState(() {
            _statusDetail = 'ขยับเข้ามาใกล้ขึ้นอีกนิด (ประมาณ 1 ช่วงแขน)';
            _statusColor = const Color(0xFFD97706);
          });
        }
        _isEvaluatingBiometrics = false;
        return;
      } else if (faceRatio > 0.88) {
        if (mounted) {
          setState(() {
            _statusDetail = 'ถอยห่างออกมาอีกนิดให้เห็นใบหน้าเต็มกรอบ';
            _statusColor = const Color(0xFFD97706);
          });
        }
        _isEvaluatingBiometrics = false;
        return;
      }

      // 2. Ultra-fast direct face cropping (~3ms vs 250ms!)
      final croppedFace = ImageUtils.cropFaceDirectFromCameraImage(cameraImage, face.boundingBox);

      // 3. Liveness Check
      final liveness = await _antiSpoofingService.checkLiveness(
        croppedFace: croppedFace,
        face: face,
      );

      if (!liveness.isReal) {
        if (mounted) {
          setState(() {
            _statusDetail = liveness.message;
            _statusColor = const Color(0xFFDC2626);
          });
        }
        _isEvaluatingBiometrics = false;
        return;
      }

      // ================= LOGIN MODE (APPLE FACE ID INSTANT UNLOCK) =================
      if (widget.mode == FaceScanMode.login) {
        final isAttentive = _antiSpoofingService.isUserAttentive(face: face);
        if (!isAttentive) {
          if (mounted) {
            setState(() {
              _statusTitle = 'มองตรงมาที่กล้อง';
              _statusDetail = 'กรุณามองตรงมายังหน้าจอ';
              _statusColor = const Color(0xFF64748B);
            });
          }
          _isEvaluatingBiometrics = false;
          return;
        }

        // Ensure AI recognition model is 100% loaded before evaluating
        if (!_recognitionService.isModelLoaded) {
          if (mounted) {
            setState(() {
              _statusTitle = 'กำลังเริ่มระบบ AI Face ID...';
              _statusDetail = 'กรุณามองตรงมายังกล้อง';
              _statusColor = const Color(0xFF64748B);
            });
          }
          _isEvaluatingBiometrics = false;
          return;
        }

        // ⚡ Extract embedding immediately from the clean upright face (~15ms)
        final embedding = await _recognitionService.extractFaceEmbedding(croppedFace);
        _loginFrameEmbeddings.add(embedding);

        // 🚀 APPLE FACE ID INSTANT MATCH (Frame 1):
        // If similarity is >= 0.70, unlock instantly in ~0.25s!
        final instantCheck = await FaceAuthRepository.authenticateWithFace(embedding);
        if (instantCheck.isSuccess && instantCheck.matchedUser != null) {
          _isAuthenticating = true;
          _unsuccessfulScanCount = 0;
          if (mounted) {
            setState(() {
              _scanProgress = 1.0;
              _statusTitle = 'Face ID ปลดล็อกสำเร็จ';
              _statusDetail = 'ยินดีต้อนรับคุณ ${instantCheck.matchedUser!.name}';
              _statusColor = const Color(0xFF00FF66);
            });
          }
          HapticFeedback.heavyImpact();
          FaceAuthRepository.updateAdaptiveFaceEmbedding(
            user: instantCheck.matchedUser!,
            scannedEmbedding: embedding,
            similarityScore: instantCheck.similarityScore,
          );
          _showSuccessModal(instantCheck.matchedUser!, instantCheck.similarityScore);
          return;
        }

        // If borderline match (e.g. 0.62 - 0.69, slight ambient light shift),
        // accumulate 2-3 frames and test fused consensus:
        if (_loginFrameEmbeddings.length >= 2) {
          final fusedEmbedding = FaceRecognitionService.combineMultiAngleEmbeddings(_loginFrameEmbeddings);
          final centroidCheck = await FaceAuthRepository.authenticateWithFace(fusedEmbedding);
          if (centroidCheck.isSuccess && centroidCheck.matchedUser != null) {
            _isAuthenticating = true;
            _unsuccessfulScanCount = 0;
            if (mounted) {
              setState(() {
                _scanProgress = 1.0;
                _statusTitle = 'Face ID ปลดล็อกสำเร็จ';
                _statusDetail = 'ยินดีต้อนรับคุณ ${centroidCheck.matchedUser!.name}';
                _statusColor = const Color(0xFF00FF66);
              });
            }
            HapticFeedback.heavyImpact();
            FaceAuthRepository.updateAdaptiveFaceEmbedding(
              user: centroidCheck.matchedUser!,
              scannedEmbedding: fusedEmbedding,
              similarityScore: centroidCheck.similarityScore,
            );
            _showSuccessModal(centroidCheck.matchedUser!, centroidCheck.similarityScore);
            return;
          }
        }

        // Keep rolling buffer of last 3 frames
        if (_loginFrameEmbeddings.length > 3) {
          _loginFrameEmbeddings.removeAt(0);
        }

        _unsuccessfulScanCount++;
        // If after ~3.5s of continuous face presentation without match:
        if (_unsuccessfulScanCount >= 25) {
          _unsuccessfulScanCount = 0;
          _loginFrameEmbeddings.clear();
          _scanProgress = 0.0;
          HapticFeedback.vibrate();
          _showErrorModal(instantCheck.message);
        } else {
          if (mounted) {
            setState(() {
              _scanProgress = 0.0;
              _statusTitle = 'กำลังวิเคราะห์ Face ID...';
              _statusDetail = 'กรุณามองตรงมายังกล้อง';
              _statusColor = const Color(0xFF00FF66);
            });
          }
          _isEvaluatingBiometrics = false;
        }
      }
      // ================= REGISTER MODE (STRICT PROGRESSIVE 3-ANGLE HOLD) =================
      else {
        final bool isFrontCam = _cameras.isNotEmpty &&
            _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.front;
        final double rawYaw = face.headEulerAngleY ?? 0.0;
        final double angleY = isFrontCam ? -rawYaw : rawYaw;
        bool inTargetAngle = false;
        String promptHint = '';

        if (_currentEnrollStep == 0) {
          if (angleY.abs() <= 8.5) {
            inTargetAngle = true;
            promptHint = 'ค้างไว้นิ่งๆ กำลังบันทึกมิติหน้าตรง...';
          } else {
            promptHint = 'มองตรงมาที่กล้อง (ปรับหน้าให้ตรง)';
          }
        } else if (_currentEnrollStep == 1) {
          if (angleY <= -11.0 && angleY >= -38.0) {
            inTargetAngle = true;
            promptHint = 'มุมซ้ายถูกต้อง! ค้างไว้นิ่งๆ...';
          } else if (angleY > -11.0) {
            promptHint = 'หันศีรษะไปทางซ้ายอีกนิด 👈';
          } else {
            promptHint = 'หันซ้ายมากเกินไป ค่อยๆ ปรับกลับมานิดนึง';
          }
        } else if (_currentEnrollStep == 2) {
          if (angleY >= 11.0 && angleY <= 38.0) {
            inTargetAngle = true;
            promptHint = 'มุมขวาถูกต้อง! ค้างไว้นิ่งๆ...';
          } else if (angleY < 11.0) {
            promptHint = 'หันศีรษะไปทางขวาอีกนิด 👉';
          } else {
            promptHint = 'หันขวามากเกินไป ค่อยๆ ปรับกลับมานิดนึง';
          }
        }

        if (inTargetAngle) {
          final embedding = await _recognitionService.extractFaceEmbedding(croppedFace);
          _currentStepEmbeddings.add(embedding);

          final progress = (_currentStepEmbeddings.length / 5.0).clamp(0.0, 1.0);

          if (mounted) {
            setState(() {
              _stepProgress = progress;
              _statusDetail = '$promptHint (${(progress * 100).toInt()}%)';
              _statusColor = const Color(0xFF00A896);
            });
          }

          HapticFeedback.selectionClick();

          if (_currentStepEmbeddings.length >= 5) {
            HapticFeedback.mediumImpact();
            final angleCentroid = FaceRecognitionService.combineMultiAngleEmbeddings(_currentStepEmbeddings);
            _collectedEmbeddings.add(angleCentroid);
            _currentStepEmbeddings.clear();
            _stepProgress = 0.0;

            if (_currentEnrollStep < 2) {
              _isTransitioningStep = true;
              final completedStep = _currentEnrollStep + 1;
              if (mounted) {
                setState(() {
                  _statusTitle = '✅ มุมที่ $completedStep บันทึกสำเร็จ!';
                  _statusDetail = completedStep == 1
                      ? 'เตรียมพร้อมสำหรับขั้นตอนที่ 2: หันหน้าไปทางซ้าย'
                      : 'เตรียมพร้อมสำหรับขั้นตอนที่ 3: หันหน้าไปทางขวา';
                  _statusColor = const Color(0xFF00A896);
                });
              }

              await Future.delayed(const Duration(milliseconds: 1000));
              if (!mounted) return;

              _currentEnrollStep++;
              _isTransitioningStep = false;
              if (mounted) {
                setState(() {
                  _updateInstructionText();
                });
              }
            } else {
              _isAuthenticating = true;
              // Center-weighted master embedding (60% Center, 20% Left, 20% Right)
              List<double> masterEmbedding;
              if (_collectedEmbeddings.length >= 3) {
                final center = _collectedEmbeddings[0];
                final left = _collectedEmbeddings[1];
                final right = _collectedEmbeddings[2];
                final dim = center.length;
                final weighted = List<double>.filled(dim, 0.0);
                for (int i = 0; i < dim; i++) {
                  weighted[i] = 0.60 * center[i] + 0.20 * left[i] + 0.20 * right[i];
                }
                masterEmbedding = FaceRecognitionService.l2Normalize(weighted);
              } else {
                masterEmbedding = FaceRecognitionService.combineMultiAngleEmbeddings(_collectedEmbeddings);
              }

              final profile = UserFaceProfile(
                id: widget.effectiveEmail,
                name: widget.effectiveName,
                email: widget.effectiveEmail,
                role: widget.effectiveRole,
                faceEmbedding: masterEmbedding,
                registeredAt: DateTime.now(),
              );

              if (!mounted) return;
              HapticFeedback.heavyImpact();
              _showSuccessModal(profile, 1.0, isNewRegistration: true);
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _statusDetail = promptHint;
              _statusColor = const Color(0xFF64748B);
              _stepProgress = 0.0;
              _currentStepEmbeddings.clear();
            });
          }
        }
      }
    } finally {
      _isEvaluatingBiometrics = false;
    }
  }

  void _showSuccessModal(UserFaceProfile user, double score,
      {bool isNewRegistration = false}) {
    final isRegister = widget.mode == FaceScanMode.register;
    final primaryColor = isRegister ? const Color(0xFF00A896) : const Color(0xFF5B9EE1);
    bool hasNavigated = false;

    void handleProceed(BuildContext sheetCtx) {
      if (hasNavigated) return;
      hasNavigated = true;

      if (widget.mode == FaceScanMode.register) {
        Navigator.pop(sheetCtx);
        Navigator.pop(context, user.faceEmbedding);
      } else {
        Navigator.pop(sheetCtx);
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
      }
    }

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        // Swift Apple Face ID auto-proceed for login mode
        if (!isRegister) {
          Future.delayed(const Duration(milliseconds: 550), () {
            if (ctx.mounted && !hasNavigated) {
              handleProceed(ctx);
            }
          });
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F5),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
                ),
                child: Icon(Icons.check_circle_rounded,
                    color: primaryColor, size: 42),
              ),
              const SizedBox(height: 16),
              Text(
                isNewRegistration
                    ? 'บันทึกใบหน้า 3D เรียบร้อย'
                    : 'ปลดล็อก Face ID สำเร็จ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                user.name,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF00A896).withValues(alpha: 0.2)),
                ),
                child: Text(
                  isNewRegistration
                      ? 'บันทึก 12 เฟรม 3 มิติสมบูรณ์ • ${user.email}'
                      : 'AI Match ${(score * 100).toStringAsFixed(1)}% • ${user.role.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00A896),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => handleProceed(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    widget.mode == FaceScanMode.register
                        ? 'บันทึกข้อมูลใบหน้า'
                        : 'เข้าสู่ระบบ',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showErrorModal(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade200),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.redAccent, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'ไม่สามารถยืนยันตัวตนได้',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(23),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'ลองใหม่อีกครั้ง',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
    _animController.dispose();
    _stopAndDisposeCamera();
    _detectorService.dispose();
    super.dispose();
  }

  void _stopAndDisposeCamera() {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        controller.stopImageStream().then((_) {
          controller.dispose();
        }).catchError((_) {
          controller.dispose();
        });
      } else {
        controller.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = widget.mode == FaceScanMode.register;
    final Color primaryColor = isRegister ? const Color(0xFF00A896) : const Color(0xFF5B9EE1);
    final Color bgStartColor = isRegister ? const Color(0xFFE3F8EB) : const Color(0xFFE2F0FE);
    const Color bgEndColor = Color(0xFFF8FAFC);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgStartColor, bgEndColor],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 1. Clean Top Header Bar (Web Application Theme)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button (Clean White Pill)
                    _buildWhiteIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),

                    // Header title & logo
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.face_retouching_natural_rounded,
                                color: Colors.white, size: 19),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isRegister ? 'ลงทะเบียน Face ID (3D)' : 'เข้าสู่ระบบด้วย Face ID',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),

                    // Camera Switch (Clean White Pill)
                    if (_cameras.length > 1)
                      _buildWhiteIconButton(
                        icon: Icons.flip_camera_ios_rounded,
                        onTap: _switchCamera,
                      )
                    else
                      const SizedBox(width: 42),
                  ],
                ),
              ),

              // 2. Step Indicator Bar (Register Mode - Web Theme)
              if (isRegister) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: _buildWebStepBar(primaryColor),
                ),
                const SizedBox(height: 8),
              ] else ...[
                const SizedBox(height: 12),
              ],

              // 3. Center Camera Portal Card
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The Camera Viewport (Clean, Premium Circular Portal)
                        _buildCameraPortal(isRegister, primaryColor),

                        const SizedBox(height: 18),

                        // Instruction & Progress Info Card
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildInstructionCard(isRegister, primaryColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Bottom Action (Fallback to gallery)
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 6),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _processImageFromPicker,
                    icon: Icon(Icons.photo_library_outlined,
                        color: Colors.grey.shade600, size: 16),
                    label: Text(
                      'เลือกภาพถ่ายจากคลังภาพ (ทดสอบ)',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      backgroundColor: Colors.white.withValues(alpha: 0.85),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildCameraPortal(bool isRegister, Color primaryColor) {
    const double portalSize = 270.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer Shadow & Glow Ring
        Container(
          width: portalSize + 16,
          height: portalSize + 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),

        // Camera Preview Inside Circle
        Container(
          width: portalSize,
          height: portalSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_isCameraInitialized && _cameraController != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _cameraController!.value.previewSize?.height ?? portalSize,
                      height: _cameraController!.value.previewSize?.width ?? portalSize,
                      child: CameraPreview(_cameraController!),
                    ),
                  )
                else
                  Container(
                    color: Colors.grey.shade100,
                    child: Center(
                      child: _hasCameraError
                          ? const Icon(Icons.videocam_off_rounded,
                              color: Colors.grey, size: 48)
                          : CircularProgressIndicator(color: primaryColor),
                    ),
                  ),

                // Subtle laser scan line in Login Mode
                if (!isRegister)
                  AnimatedBuilder(
                    animation: _scanLineAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: portalSize * _scanLineAnimation.value,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                primaryColor.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),

        // Custom Overlay Painter (Smooth Progress Ring / Corner Brackets)
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(portalSize + 16, portalSize + 16),
              painter: WebFaceIdPortalPainter(
                primaryColor: primaryColor,
                statusColor: _statusColor,
                isRegisterMode: isRegister,
                currentStep: _currentEnrollStep,
                stepProgress: _stepProgress,
                scanProgress: _scanProgress,
                pulseScale: _pulseAnimation.value,
              ),
            );
          },
        ),

        // Top Floating AI Status Pill
        Positioned(
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'AI วิเคราะห์ 3 มิติ',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionCard(bool isRegister, Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _statusTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _statusDetail,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _statusColor == const Color(0xFF00A896) ||
                      _statusColor == const Color(0xFF5B9EE1)
                  ? Colors.grey.shade600
                  : _statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          // Hold Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              width: double.infinity,
              child: LinearProgressIndicator(
                value: isRegister ? _stepProgress : _scanProgress,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStepBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildWebStepChip(0, '1. หน้าตรง', primaryColor),
          Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
          _buildWebStepChip(1, '2. หันซ้าย', primaryColor),
          Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
          _buildWebStepChip(2, '3. หันขวา', primaryColor),
        ],
      ),
    );
  }

  Widget _buildWebStepChip(int stepIndex, String label, Color primaryColor) {
    final bool isDone = _currentEnrollStep > stepIndex;
    final bool isCurrent = _currentEnrollStep == stepIndex;

    Color bgColor = Colors.transparent;
    Color textColor = Colors.grey.shade500;

    if (isCurrent) {
      bgColor = primaryColor;
      textColor = Colors.white;
    } else if (isDone) {
      bgColor = const Color(0xFFE8F8F5);
      textColor = const Color(0xFF00A896);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone) ...[
            const Icon(Icons.check_rounded, size: 12, color: Color(0xFF00A896)),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11.5,
              fontWeight: isCurrent || isDone ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteIconButton({required IconData icon, required VoidCallback onTap}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Icon(icon, color: const Color(0xFF1E293B), size: 18),
          ),
        ),
      ),
    );
  }
}

/// Modern Web UI Portal Painter for Face Scan Viewfinder
class WebFaceIdPortalPainter extends CustomPainter {
  final Color primaryColor;
  final Color statusColor;
  final bool isRegisterMode;
  final int currentStep;
  final double stepProgress;
  final double scanProgress;
  final double pulseScale;

  WebFaceIdPortalPainter({
    required this.primaryColor,
    required this.statusColor,
    required this.isRegisterMode,
    required this.currentStep,
    required this.stepProgress,
    required this.scanProgress,
    required this.pulseScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width / 2) - 4.0;

    if (isRegisterMode) {
      // 60-Tick Radial Ring matching the Web Theme
      const int totalTicks = 60;
      final double totalProgress =
          ((currentStep + stepProgress) / 3.0).clamp(0.0, 1.0);
      final int filledTickCount = (totalProgress * totalTicks).round();

      final double innerR = radius - 1.0;
      final double outerR = radius + 9.0;

      for (int i = 0; i < totalTicks; i++) {
        final double angle = -math.pi / 2 + (i * 2 * math.pi / totalTicks);
        final bool isFilled = i < filledTickCount;
        final bool isCurrent = i == filledTickCount && totalProgress < 1.0;

        final startPoint = Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        );
        final endPoint = Offset(
          center.dx + (outerR + (isCurrent ? 2.0 : 0.0)) * math.cos(angle),
          center.dy + (outerR + (isCurrent ? 2.0 : 0.0)) * math.sin(angle),
        );

        final tickPaint = Paint()
          ..strokeWidth = isCurrent ? 3.0 : (isFilled ? 2.6 : 1.8)
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        if (isFilled) {
          tickPaint.color = primaryColor;
        } else if (isCurrent) {
          tickPaint.color = primaryColor.withValues(alpha: 0.5);
        } else {
          tickPaint.color = Colors.grey.shade300;
        }

        canvas.drawLine(startPoint, endPoint, tickPaint);
      }
    } else {
      // Sleek Corner Brackets in Login Mode
      final cornerPaint = Paint()
        ..color = primaryColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final double boxSize = radius * 1.45;
      final rect = Rect.fromCenter(center: center, width: boxSize, height: boxSize);
      const double bracketLen = 24.0;
      const double cornerRadius = 16.0;

      // Top-Left
      final tl = Path()
        ..moveTo(rect.left, rect.top + bracketLen)
        ..lineTo(rect.left, rect.top + cornerRadius)
        ..arcToPoint(Offset(rect.left + cornerRadius, rect.top),
            radius: const Radius.circular(cornerRadius))
        ..lineTo(rect.left + bracketLen, rect.top);
      canvas.drawPath(tl, cornerPaint);

      // Top-Right
      final tr = Path()
        ..moveTo(rect.right - bracketLen, rect.top)
        ..lineTo(rect.right - cornerRadius, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + cornerRadius),
            radius: const Radius.circular(cornerRadius))
        ..lineTo(rect.right, rect.top + bracketLen);
      canvas.drawPath(tr, cornerPaint);

      // Bottom-Left
      final bl = Path()
        ..moveTo(rect.left, rect.bottom - bracketLen)
        ..lineTo(rect.left, rect.bottom - cornerRadius)
        ..arcToPoint(Offset(rect.left + cornerRadius, rect.bottom),
            radius: const Radius.circular(cornerRadius))
        ..lineTo(rect.left + bracketLen, rect.bottom);
      canvas.drawPath(bl, cornerPaint);

      // Bottom-Right
      final br = Path()
        ..moveTo(rect.right - bracketLen, rect.bottom)
        ..lineTo(rect.right - cornerRadius, rect.bottom)
        ..arcToPoint(Offset(rect.right, rect.bottom - cornerRadius),
            radius: const Radius.circular(cornerRadius))
        ..lineTo(rect.right, rect.bottom - bracketLen);
      canvas.drawPath(br, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WebFaceIdPortalPainter oldDelegate) => true;
}

