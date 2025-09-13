// lib/scan_qr_page.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';

import 'package:anydrop/pages/receiver_page.dart';

class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  bool _awaitingImageAnalysis = false;

  @override
  void initState() {
    super.initState();
    // Ensure controller is started; ignore errors on emulators with no camera
    _controller.start().catchError((_) => null);
  }

  Future<void> _scanFromImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    setState(() {
      _awaitingImageAnalysis = true;
      _handled = false;
    });

    try {
      final ok = await _controller.analyzeImage(img.path); // triggers onDetect
      if (!ok) {
        if (!mounted) return;
        setState(() => _awaitingImageAnalysis = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR found in image')),
        );
      } else {
        // Give onDetect a short window to fire; if not, notify the user.
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (_awaitingImageAnalysis && !_handled) {
            setState(() => _awaitingImageAnalysis = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Couldnt read manifest from image')),
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _awaitingImageAnalysis = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to analyze image: $e')),
      );
    }
  }

  void _handleDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (_handled || barcodes.isEmpty) return;

    final value = barcodes.first.rawValue ?? '';
    if ((value.startsWith('http://') || value.startsWith('https://')) &&
        value.contains('/manifest')) {
      _handled = true;
      _awaitingImageAnalysis = false;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiverPage(manifestUrl: value)),
      );
    } else if (_awaitingImageAnalysis) {
      _awaitingImageAnalysis = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR is not a manifest link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        actions: [
          if (_awaitingImageAnalysis)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: Text('Analyzing…')),
            ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(controller: _controller, onDetect: _handleDetect),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanFromImage,
        icon: const Icon(Icons.photo),
        label: const Text('Scan from image'),
      ),
    );
  }
}
