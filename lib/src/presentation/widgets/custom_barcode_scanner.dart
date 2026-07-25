import 'dart:io';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'barcode_overlay_painter.dart';

class CustomBarcodeScanner extends StatefulWidget {
  final List<BarcodeFormat> formats;
  final Widget Function(BuildContext context, List<Barcode> barcodes, Size? imageSize)? overlayBuilder;
  final void Function(List<Barcode> barcodes) onDetect;
  final bool showBoundingBox;
  final Color boundingBoxColor;
  final Rect? scanWindow;
  final void Function()? onWindowScaleStart;
  final void Function(double scale)? onWindowScaleUpdate;
  final void Function(double zoomLevel)? onZoomChanged;
  
  const CustomBarcodeScanner({
    Key? key,
    required this.onDetect,
    this.formats = const [BarcodeFormat.all],
    this.showBoundingBox = true,
    this.boundingBoxColor = Colors.red,
    this.scanWindow,
    this.overlayBuilder,
    this.onWindowScaleStart,
    this.onWindowScaleUpdate,
    this.onZoomChanged,
  }) : super(key: key);

  @override
  State<CustomBarcodeScanner> createState() => CustomBarcodeScannerState();
}

class CustomBarcodeScannerState extends State<CustomBarcodeScanner> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;
  double _zoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  
  BarcodeScanner? _barcodeScanner;
  bool _isBusy = false;
  
  // Throttle variables for zoom
  int _lastZoomTime = 0;
  Timer? _zoomTimer;
  List<Barcode> _recognizedBarcodes = [];
  double _baseScale = 1.0;
  String? _cameraError;
  int _lastProcessTime = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeScanner = BarcodeScanner(formats: widget.formats);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_cameras.isEmpty) {
      try {
        _cameras = await availableCameras();
      } catch (e) {
        debugPrint('Error getting cameras: $e');
        if (mounted) {
          setState(() {
            _cameraError = 'Lỗi truy cập camera: $e';
          });
        }
        return;
      }
    }
    
    if (_cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _cameraError = 'Thiết bị không có camera khả dụng';
        });
      }
      return;
    }
    
    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.back) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex == -1) _cameraIndex = 0;
    
    await _startLiveFeed();
  }

  Future<void> _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      Platform.isAndroid ? ResolutionPreset.medium : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    
    try {
      await _controller?.initialize();
      _minZoomLevel = await _controller?.getMinZoomLevel() ?? 1.0;
      _maxZoomLevel = await _controller?.getMaxZoomLevel() ?? 1.0;
      
      _controller?.startImageStream(_processCameraImage);
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (e.toString().contains('used after being disposed')) return;
      
      if (mounted) {
        setState(() {
          _cameraError = 'Lỗi khởi tạo camera (Không hỗ trợ): $e';
        });
      }
    }
  }

  Future<void> _stopLiveFeed({bool isDisposing = false}) async {
    final cameraController = _controller;
    _controller = null;
    if (mounted && !isDisposing) setState(() {});
    
    if (cameraController != null) {
      try {
        if (cameraController.value.isStreamingImages) {
          await cameraController.stopImageStream();
        }
        await cameraController.dispose();
      } catch (e) {
        debugPrint('Error disposing camera: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveFeed(isDisposing: true);
    _barcodeScanner?.close();
    _zoomTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didUpdateWidget(CustomBarcodeScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formats != widget.formats) {
      _barcodeScanner?.close();
      _barcodeScanner = BarcodeScanner(formats: widget.formats);
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopLiveFeed();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraError != null || _cameras.isEmpty) {
        setState(() => _cameraError = null);
        _initializeCamera();
      } else if (_controller == null || !_controller!.value.isStreamingImages) {
        _startLiveFeed();
      }
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isBusy) return;
    
    // Giảm throttle xuống 150ms (khoảng ~7 khung hình/giây) để quét cực nhạy
    // Vì đã hạ độ phân giải xuống medium nên CPU dư sức xử lý mức này mà không nóng máy
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProcessTime < 150) return;
    
    _isBusy = true;
    _lastProcessTime = now;
    
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      _isBusy = false;
      return;
    }
    
    _processImage(inputImage);
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera = _cameras[_cameraIndex];
    
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.isEmpty) return null;

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }
  
  Future<void> _processImage(InputImage inputImage) async {
    try {
      if (_barcodeScanner == null) return;
      final barcodes = await _barcodeScanner!.processImage(inputImage);
      
      if (mounted) {
        if (barcodes.isNotEmpty) {
          final size = inputImage.metadata?.size;
          if (size != null) {
            final center = Offset(size.width / 2, size.height / 2);
            if (widget.scanWindow != null && context.mounted) {
              final screenSize = MediaQuery.of(context).size;
              final previewSize = _controller?.value.previewSize;
              
              if (previewSize != null) {
                // Trên Android chế độ dọc, previewSize gốc có dạng landscape, cần swap width/height
                final double imageWidth = Platform.isAndroid ? previewSize.height : previewSize.width;
                final double imageHeight = Platform.isAndroid ? previewSize.width : previewSize.height;

                final double scaleX = screenSize.width / imageWidth;
                final double scaleY = screenSize.height / imageHeight;

                barcodes.removeWhere((barcode) {
                  final boundingBox = barcode.boundingBox;
                  final rect = Rect.fromLTRB(
                    boundingBox.left * scaleX,
                    boundingBox.top * scaleY,
                    boundingBox.right * scaleX,
                    boundingBox.bottom * scaleY,
                  );

                  // Chỉ nhận mã vạch nếu tâm của nó nằm lọt trong khung quét (tránh quét dính mã bên ngoài)
                  return !widget.scanWindow!.contains(rect.center);
                });
              }
            }

            barcodes.sort((a, b) {
              final aCenter = a.boundingBox.center;
              final bCenter = b.boundingBox.center;
              final aDist = (aCenter.dx - center.dx) * (aCenter.dx - center.dx) + (aCenter.dy - center.dy) * (aCenter.dy - center.dy);
              final bDist = (bCenter.dx - center.dx) * (bCenter.dx - center.dx) + (bCenter.dy - center.dy) * (bCenter.dy - center.dy);
              return aDist.compareTo(bDist);
            });
          }
        }
        
        setState(() {
          _recognizedBarcodes = barcodes;
        });
        if (barcodes.isNotEmpty) {
          widget.onDetect(barcodes);
        }
      }
    } catch (e) {
      debugPrint('Error scanning barcodes: $e');
    } finally {
      _isBusy = false;
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _zoomLevel;
    if (widget.onWindowScaleStart != null) {
      widget.onWindowScaleStart!();
    }
  }

  void _updateZoomNative(double zoom) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomTime > 60) {
      _lastZoomTime = now;
      _controller?.setZoomLevel(zoom);
    } else {
      _zoomTimer?.cancel();
      _zoomTimer = Timer(const Duration(milliseconds: 60), () {
        if (mounted && _controller != null) {
          _controller!.setZoomLevel(zoom);
          _lastZoomTime = DateTime.now().millisecondsSinceEpoch;
        }
      });
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    if (details.pointerCount >= 2 || details.scale != 1.0) {
      // Zoom camera
      _zoomLevel = (_baseScale * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
      _updateZoomNative(_zoomLevel);
      
      if (widget.onZoomChanged != null) {
        widget.onZoomChanged!(_zoomLevel);
      }
      
      // Đồng thời thay đổi kích thước khung ngắm
      if (widget.onWindowScaleUpdate != null) {
        widget.onWindowScaleUpdate!(details.scale);
      }
    }
  }

  void setZoom(double zoom) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _zoomLevel = zoom.clamp(_minZoomLevel, _maxZoomLevel);
    _updateZoomNative(_zoomLevel);
  }

  Future<void> refocus() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusPoint(const Offset(0.5, 0.5)); // Focus vào chính giữa màn hình (nơi chứa vùng quét)
      await _controller!.setFocusMode(FocusMode.auto);
    } catch (_) {}
  }

  // Xóa hàm animateToZoom vì gọi API zoom phần cứng liên tục làm giật camera trên Android

  void _handleTapDown(TapDownDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPoint = box.globalToLocal(details.globalPosition);
    final Offset relativePoint = Offset(
      localPoint.dx / box.size.width,
      localPoint.dy / box.size.height,
    );
    
    _controller!.setFocusPoint(relativePoint);
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _cameraError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _cameraError = null);
                  _initializeCamera();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final size = MediaQuery.of(context).size;
    final imageSize = Size(
      _controller!.value.previewSize!.height,
      _controller!.value.previewSize!.width,
    );
    
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: (details) => refocus(),
          onTapDown: _handleTapDown,
          child: CameraPreview(_controller!),
        ),
        if (widget.showBoundingBox && _recognizedBarcodes.isNotEmpty)
          CustomPaint(
            painter: BarcodeOverlayPainter(
              barcodes: _recognizedBarcodes,
              imageSize: imageSize,
              screenSize: size,
              color: widget.boundingBoxColor,
            ),
          ),
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, _recognizedBarcodes, imageSize),
      ],
    );
  }
}
