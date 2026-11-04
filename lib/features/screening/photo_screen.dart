import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/screening_draft.dart';

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _photoBytes;
  String? _photoName;

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600, // keeps the upload small
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoName = picked.name;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the photo. Check the camera permission.',
          ),
        ),
      );
    }
  }

  void _continue() {
    ScreeningDraft.photoBytes = _photoBytes;
    ScreeningDraft.photoName = _photoName;
    context.go('/screening/steps/scoliometer');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Back Photo'),
        leading: BackButton(
          onPressed: () => context.go('/screening/steps/pose'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _photoBytes == null ? _buildGuidelines() : _buildReview(),
        ),
      ),
    );
  }

  Widget _buildGuidelines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Photo guidelines',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Patient stands straight, feet together'),
                SizedBox(height: 8),
                Text('• Back faces the camera'),
                SizedBox(height: 8),
                Text('• Upper back clearly visible (no loose clothing)'),
                SizedBox(height: 8),
                Text('• Whole back from neck to hips is in the frame'),
                SizedBox(height: 8),
                Text('• Good lighting, plain background'),
                SizedBox(height: 8),
                Text('• Camera held level with the middle of the back'),
              ],
            ),
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Choose from Gallery'),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Is the image clear and within the guidelines?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(child: Image.memory(_photoBytes!, fit: BoxFit.contain)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _continue, child: const Text('Yes, continue')),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() {
            _photoBytes = null;
            _photoName = null;
          }),
          child: const Text('No, retake'),
        ),
      ],
    );
  }
}
