import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  /// Converts CameraImage to InputImage for Google ML Kit Face Detection (MediaPipe/BlazeFace)
  static InputImage? convertCameraImageToInputImage({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
  }) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
        break;
      case DeviceOrientation.landscapeLeft:
        rotation = InputImageRotationValue.fromRawValue((sensorOrientation + 90) % 360);
        break;
      case DeviceOrientation.portraitDown:
        rotation = InputImageRotationValue.fromRawValue((sensorOrientation + 180) % 360);
        break;
      case DeviceOrientation.landscapeRight:
        rotation = InputImageRotationValue.fromRawValue((sensorOrientation + 270) % 360);
        break;
    }
    if (rotation == null) return null;

    final bytes = plane.bytes;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Converts CameraImage (Android YUV420 or iOS BGRA8888) to an img.Image instance
  static img.Image convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      // iOS Format
      return img.Image.fromBytes(
        width: width,
        height: height,
        bytes: image.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } else {
      // Android YUV420 Format
      final img.Image resultImage = img.Image(width: width, height: height);
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yRowStride = yPlane.bytesPerRow;
      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

          final int yValue = yPlane.bytes[yIndex];
          final int uValue = uPlane.bytes[uvIndex];
          final int vValue = vPlane.bytes[uvIndex];

          int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
          int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
          int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

          resultImage.setPixelRgb(x, y, r, g, b);
        }
      }
      return resultImage;
    }
  }

  /// Crops face from image using bounding box, with safety clamping and margin
  static img.Image cropFace(img.Image srcImage, ui.Rect boundingBox, {double margin = 0.15}) {
    final double marginW = boundingBox.width * margin;
    final double marginH = boundingBox.height * margin;

    final int left = (boundingBox.left - marginW).toInt().clamp(0, srcImage.width - 1);
    final int top = (boundingBox.top - marginH).toInt().clamp(0, srcImage.height - 1);
    final int right = (boundingBox.right + marginW).toInt().clamp(1, srcImage.width);
    final int bottom = (boundingBox.bottom + marginH).toInt().clamp(1, srcImage.height);

    final int width = (right - left).clamp(1, srcImage.width - left);
    final int height = (bottom - top).clamp(1, srcImage.height - top);

    return img.copyCrop(srcImage, x: left, y: top, width: width, height: height);
  }

  /// Converts img.Image to normalized Float32List Tensor [1, height, width, 3]
  /// Normalization: (pixel - mean) / std (MobileFaceNet uses mean=127.5, std=128.0)
  static Float32List imageToTensor(img.Image image, {double mean = 127.5, double std = 128.0}) {
    final Float32List tensor = Float32List(1 * image.height * image.width * 3);
    int tensorIndex = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        tensor[tensorIndex++] = (pixel.r - mean) / std;
        tensor[tensorIndex++] = (pixel.g - mean) / std;
        tensor[tensorIndex++] = (pixel.b - mean) / std;
      }
    }
    return tensor;
  }

  /// CLAHE & Auto-Brightness Balance: Normalizes facial illumination and contrast
  static img.Image enhanceContrastAndLighting(img.Image srcImage) {
    double totalLuminance = 0.0;
    final int numPixels = srcImage.width * srcImage.height;
    if (numPixels == 0) return srcImage;

    for (int y = 0; y < srcImage.height; y++) {
      for (int x = 0; x < srcImage.width; x++) {
        final p = srcImage.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        totalLuminance += lum;
      }
    }

    final double avgLum = totalLuminance / numPixels;
    // Calculate adaptive gamma factor based on average scene brightness
    final double gamma = (avgLum > 0)
        ? (0.693147 / (-(math.log((avgLum / 255.0).clamp(0.08, 0.92))))).clamp(0.65, 1.45)
        : 1.0;
    const double contrastFactor = 1.15;

    final img.Image enhanced = img.Image(width: srcImage.width, height: srcImage.height);

    for (int y = 0; y < srcImage.height; y++) {
      for (int x = 0; x < srcImage.width; x++) {
        final p = srcImage.getPixel(x, y);

        double rNorm = math.pow((p.r / 255.0).clamp(0.0, 1.0), gamma).toDouble();
        double gNorm = math.pow((p.g / 255.0).clamp(0.0, 1.0), gamma).toDouble();
        double bNorm = math.pow((p.b / 255.0).clamp(0.0, 1.0), gamma).toDouble();

        int r = (((rNorm - 0.5) * contrastFactor + 0.5) * 255.0).round().clamp(0, 255);
        int g = (((gNorm - 0.5) * contrastFactor + 0.5) * 255.0).round().clamp(0, 255);
        int b = (((bNorm - 0.5) * contrastFactor + 0.5) * 255.0).round().clamp(0, 255);

        enhanced.setPixelRgb(x, y, r, g, b);
      }
    }

    return enhanced;
  }
}
