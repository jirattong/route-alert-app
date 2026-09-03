import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'image_utils.dart';

class FaceDetectorService {
  late final FaceDetector _detector;

  FaceDetectorService() {
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false, // Disabled to save CPU and battery and eliminate green mesh
      enableLandmarks: false,
      enableClassification: false,
      enableTracking: true,
      minFaceSize: 0.12,
    );
    _detector = FaceDetector(options: options);
  }

  /// Detects faces from a live CameraImage stream
  Future<List<Face>> detectFacesFromCamera({
    required CameraImage cameraImage,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) async {
    final inputImage = ImageUtils.convertCameraImageToInputImage(
      image: cameraImage,
      camera: camera,
      deviceOrientation: deviceOrientation,
    );
    if (inputImage == null) return [];
    return await _detector.processImage(inputImage);
  }

  /// Detects faces from a static image file (InputImage from file path)
  Future<List<Face>> detectFacesFromPath(String filePath) async {
    final inputImage = InputImage.fromFilePath(filePath);
    return await _detector.processImage(inputImage);
  }

  void dispose() {
    _detector.close();
  }
}
