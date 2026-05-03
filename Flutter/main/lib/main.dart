import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

class _MyHomePageState extends State<MyHomePage> {

  final record = AudioRecorder();
  final dio = Dio();
  String _status = 'Démarrage...';
  String _model = '';
  CameraController? _cameraController;
  bool _cameraActive = false;

  @override
  void initState() {
    super.initState();
    startRecording();
  }

  // ─── ÉTAPE 1 : ENREGISTREMENT ────────────────
  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/audio.m4a';

    if (await record.hasPermission()) {
      while (true) {

        // ferme caméra si elle était active
        if (_cameraActive) {
          await _cameraController?.dispose();
          setState(() => _cameraActive = false);
        }

        setState(() => _status = '🎤 Enregistrement en cours...');
        await record.start(const RecordConfig(), path: path);
        await Future.delayed(const Duration(seconds: 5));
        await record.stop();

        // ─── ÉTAPE 2 : envoie audio ──────────
        await sendAudioToFastAPI(path);
      }
    } else {
      setState(() => _status = '❌ Permission micro refusée !');
    }
  }

  // ─── ÉTAPE 2 : ENVOIE AUDIO ──────────────────
  Future<void> sendAudioToFastAPI(String audioPath) async {
    setState(() => _status = '📤 Envoi audio...');

    try {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(audioPath),
      });

      final response = await dio.post(
        'http://192.168.0.98:8000/listen',
        data: formData,
      );

      _model = response.data['model'];
      setState(() => _status = '✅ Modèle choisi : $_model');

      // ─── ÉTAPE 3 : active caméra ─────────
      await _activateCamera();

    } catch (e) {
      setState(() => _status = '❌ Erreur audio : $e');
    }
  }

  // ─── ÉTAPE 3 : ACTIVE CAMÉRA ─────────────────
  Future<void> _activateCamera() async {
    setState(() => _status = '📷 Activation caméra...');

    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );

    await _cameraController!.initialize();
    setState(() => _cameraActive = true);

    // stabilise la caméra avant capture
    await Future.delayed(const Duration(seconds: 2));

    // ─── ÉTAPE 4 : capture image ─────────
    await _captureAndSend();
  }

  // ─── ÉTAPE 4 : CAPTURE + ENVOIE IMAGE ────────
  Future<void> _captureAndSend() async {
    setState(() => _status = '📸 Capture image...');

    try {
      final image = await _cameraController!.takePicture();
      await sendImageToFastAPI(image.path);
    } catch (e) {
      setState(() => _status = '❌ Erreur capture : $e');
    }
  }

  // ─── ÉTAPE 5 : ENVOIE IMAGE + MODÈLE ─────────
  Future<void> sendImageToFastAPI(String imagePath) async {
    setState(() => _status = '📤 Envoi image...');

    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imagePath),
        'model': _model, // ← CNN ou YOLO
      });

      final response = await dio.post(
        'http://192.168.0.98:8000/predict',
        data: formData,
      );

      setState(() => _status = '✅ Résultat : ${response.data}');

      // attend 3 sec puis recommence
      await Future.delayed(const Duration(seconds: 3));

    } catch (e) {
      setState(() => _status = '❌ Erreur image : $e');
    }
  }

  // ─── INTERFACE ────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Digital Eyes'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // affiche caméra si active
            if (_cameraActive && _cameraController != null)
              SizedBox(
                height: 400,
                child: CameraPreview(_cameraController!),
              ),

            const SizedBox(height: 20),

            Text(
              _status,
              style: const TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            if (_model.isNotEmpty)
              Text(
                'Modèle : $_model',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    record.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
}