import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Eyes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: MyHomePage(cameras: cameras),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MyHomePage({super.key, required this.cameras});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {

  final AudioRecorder _recorder = AudioRecorder();
  final Dio _dio = Dio();
  final AudioPlayer _audioPlayer = AudioPlayer(); // ← NOUVEAU

  String _status = 'Initializing...';
  String _model = '';
  CameraController? _cameraController;
  bool _cameraActive = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  static const Color kPrimary   = Color(0xFF6C63FF);
  static const Color kSecondary = Color(0xFFFF6584);
  static const Color kBg        = Color(0xFF0A0A1A);
  static const Color kSurface   = Color(0xFF1E1E2F);
  static const Color kSuccess   = Color(0xFF4CD964);
  static const Color kDanger    = Color(0xFFFF3B5C);
  static const Color kWarn      = Color(0xFFFFCC00);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );
    _start();
  }

  Future<void> _start() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/audio.m4a';

    if (await _recorder.hasPermission()) {
      while (mounted) {
        if (_cameraActive) {
          await _cameraController?.dispose();
          if (mounted) setState(() => _cameraActive = false);
        }
        if (mounted) setState(() => _status = 'Listening...');
        await _recorder.start(const RecordConfig(), path: path);
        await Future.delayed(const Duration(seconds: 3));
        await _recorder.stop();
        await _sendAudio(path);
      }
    } else {
      if (mounted) setState(() => _status = 'Mic permission denied');
    }
  }

  Future<void> _sendAudio(String path) async {
    if (mounted) setState(() => _status = 'Processing voice...');
    try {
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(path),
      });
      final res = await _dio.post(
        'http://172.20.10.4:8000/listen',
        data: form,
      );
      if (!mounted) return;
      _model = res.data['model'] ?? '';
      setState(() => _status = 'Model selected: $_model');
      await _openCamera();
    } catch (_) {
      if (mounted) setState(() => _status = 'Connection error');
    }
  }

  Future<void> _openCamera() async {
    if (mounted) setState(() => _status = 'Camera activating...');
    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _cameraActive = true);
    await Future.delayed(const Duration(seconds: 2));
    await _capture();
  }

  Future<void> _capture() async {
    if (mounted) setState(() => _status = 'Analyzing scene...');
    try {
      final img = await _cameraController!.takePicture();
      await _sendImage(img.path);
    } catch (_) {
      if (mounted) setState(() => _status = 'Capture error');
    }
  }

  // ← FONCTION MODIFIÉE
  Future<void> _sendImage(String path) async {
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(path),
        'model': _model,
      });

      // Recevoir l'audio en bytes
      final res = await _dio.post(
        'http://172.20.10.4:8000/predict',
        data: form,
        options: Options(responseType: ResponseType.bytes), // ← IMPORTANT
      );

      if (!mounted) return;
      setState(() => _status = 'Playing result...');

      // Sauvegarder l'audio reçu dans un fichier temporaire
      final dir = await getTemporaryDirectory();
      final audioPath = '${dir.path}/result.wav';
      final audioFile = File(audioPath);
      await audioFile.writeAsBytes(res.data);

      // Jouer l'audio
      await _audioPlayer.play(DeviceFileSource(audioPath));

      // Attendre la fin de la lecture
      await Future.delayed(const Duration(seconds: 4));

    } catch (e) {
      if (mounted) setState(() => _status = 'Analysis error: $e');
    }
  }

  Color get _statusColor {
    if (_status.contains('error') || _status.contains('denied')) return kDanger;
    if (_status.contains('selected') || _status.contains('Playing')) return kSuccess;
    if (_status.contains('Analyzing')) return kWarn;
    return kPrimary;
  }

  Color get _modelColor {
    if (_model == 'CNN')  return const Color(0xFFB794F4);
    if (_model == 'YOLO') return const Color(0xFFFFB74D);
    if (_model == 'HSV')  return kSuccess;
    return kPrimary;
  }

  IconData get _statusIcon {
    if (_status.contains('Listening'))  return Icons.mic_none_rounded;
    if (_status.contains('Camera'))     return Icons.camera_alt_outlined;
    if (_status.contains('Analyzing') || _status.contains('Capturing'))
      return Icons.biotech_rounded;
    if (_status.contains('Playing'))    return Icons.volume_up_rounded;
    if (_status.contains('error') || _status.contains('denied'))
      return Icons.warning_amber_rounded;
    return Icons.check_circle_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _BackgroundDotsPainter(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildMainArea()),
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildModelRow(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimary, kSecondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.visibility_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Digital Eyes', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              Text('AI VISION ASSISTANT', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: kSuccess.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: kSuccess.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: kSuccess, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('LIVE', style: TextStyle(color: kSuccess, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: _cameraActive && _cameraController != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_cameraController!),
                  Positioned(top: 16, left: 16, child: _cornerWidget()),
                  Positioned(top: 16, right: 16, child: Transform(alignment: Alignment.center, transform: Matrix4.rotationY(3.14159), child: _cornerWidget())),
                  Positioned(bottom: 16, left: 16, child: Transform(alignment: Alignment.center, transform: Matrix4.rotationX(3.14159), child: _cornerWidget())),
                  Positioned(bottom: 16, right: 16, child: Transform(alignment: Alignment.center, transform: Matrix4.rotationZ(3.14159), child: _cornerWidget())),
                ],
              )
            : Container(
                color: kSurface,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (context, child) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: _pulseAnim.value,
                              child: Container(
                                width: 170, height: 170,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(colors: [kPrimary.withOpacity(0.2), Colors.transparent], stops: const [0.6, 1.0]),
                                ),
                              ),
                            ),
                            Container(
                              width: 120, height: 120,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimary.withOpacity(0.3), width: 1.5)),
                            ),
                            Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kPrimary, kSecondary]),
                                boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.5), blurRadius: 25, spreadRadius: 5)],
                              ),
                              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 34),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text('say something...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('"soda" → CNN   •   "color" → HSV   •   other → YOLO',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11, letterSpacing: 0.4)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _cornerWidget() {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: kSecondary, width: 2.5), left: BorderSide(color: kSecondary, width: 2.5)),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _statusColor.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: _statusColor.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: _statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(_statusIcon, color: _statusColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(_status, style: TextStyle(color: _statusColor, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.2)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _modelChip('CNN', const Color(0xFFB794F4)),
          const SizedBox(width: 8),
          _modelChip('YOLO', const Color(0xFFFFB74D)),
          const SizedBox(width: 8),
          _modelChip('HSV', kSuccess),
          const Spacer(),
          if (_model.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_modelColor, _modelColor.withOpacity(0.7)]),
                borderRadius: BorderRadius.circular(40),
                boxShadow: [BoxShadow(color: _modelColor.withOpacity(0.3), blurRadius: 8)],
              ),
              child: Text('$_model active', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _modelChip(String label, Color color) {
    final active = _model == label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: active ? color.withOpacity(0.6) : Colors.white.withOpacity(0.1), width: 1.2),
      ),
      child: Text(label, style: TextStyle(color: active ? color : Colors.white.withOpacity(0.4), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorder.dispose();
    _cameraController?.dispose();
    _audioPlayer.dispose(); // ← NOUVEAU
    super.dispose();
  }
}

class _BackgroundDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.03)..style = PaintingStyle.fill;
    final random = math.Random(42);
    for (int i = 0; i < 200; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 2 + 1;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}