import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkCompletionPage extends StatefulWidget {
  final int activityId;
  final String activityTitle;

  const WorkCompletionPage({
    super.key,
    required this.activityId,
    required this.activityTitle,
  });

  @override
  State<WorkCompletionPage> createState() => _WorkCompletionPageState();
}

class _WorkCompletionPageState extends State<WorkCompletionPage> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _surface = Color(0xFFF5FBF4);

  final List<File> _selectedImages = [];
  bool _isSubmitting = false;
  int _uploadedCount = 0;

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() {
        for (final f in picked) {
          _selectedImages.add(File(f.path));
        }
      });
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _selectedImages.add(File(picked.path)));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  Future<void> _submit() async {
    if (_selectedImages.isEmpty) {
      _showError('Please add at least one after-photo before submitting.');
      return;
    }

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _showError('Not authenticated.');
      return;
    }

    setState(() { _isSubmitting = true; _uploadedCount = 0; });

    try {
      // Upload all images to Supabase Storage, tracking progress per image
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _selectedImages.length; i++) {
        final file = _selectedImages[i];
        final ext = file.path.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
        final fileName =
            'apres_${widget.activityId}_${DateTime.now().millisecondsSinceEpoch}_$i.$safeExt';
        final bytes = await file.readAsBytes();

        // Retry up to 2 times on transient upload errors
        String? url;
        for (int attempt = 0; attempt < 3; attempt++) {
          try {
            await Supabase.instance.client.storage
                .from('activity_image')
                .uploadBinary(
                  fileName,
                  bytes,
                  fileOptions: FileOptions(
                    contentType: 'image/$safeExt',
                    upsert: true,
                  ),
                );
            url = Supabase.instance.client.storage
                .from('activity_image')
                .getPublicUrl(fileName);
            break;
          } catch (uploadErr) {
            if (attempt == 2) rethrow;
            // Brief pause before retry (avoids busy-wait with Future.delayed)
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        uploadedUrls.add(url!);
        if (mounted) setState(() => _uploadedCount = i + 1);
      }

      // Insert preuve rows — 'preuve' table has no id_utilisateur column
      final preuveRows = uploadedUrls
          .map((url) => {
                'id_act': widget.activityId,
                'url': url,
                'type': 'apres',
              })
          .toList();
      await Supabase.instance.client.from('preuve').insert(preuveRows);

      // Call the RPC to mark as pending_validation
      final dynamic rpcResult = await Supabase.instance.client.rpc(
        'submit_work_completion',
        params: {'p_act_id': widget.activityId, 'p_user_id': uid},
      );
      final res = rpcResult as Map<String, dynamic>? ?? {};

      if (res['error'] != null) {
        _showError(_rpcErrorMsg(res['error'] as String));
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Completion submitted! The community will now validate your work.'),
          backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[WorkCompletion] Submit error: $e');
      _showError('An error occurred. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() { _isSubmitting = false; _uploadedCount = 0; });
    }
  }

  String _rpcErrorMsg(String code) => switch (code) {
        'not_assigned_worker' =>
          'You are not the assigned worker for this activity.',
        'not_in_progress' =>
          'This activity is not in progress — completion cannot be submitted.',
        'activity_not_found' => 'Activity not found.',
        _ => 'Could not submit. Please try again.',
      };

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        title: const Text(
          'Submit Completion',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity info banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x141B5E20),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.eco_rounded,
                              color: _deepGreen, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Activity',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF607060),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                widget.activityTitle,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF163217),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Instructions
                  _sectionLabel('Instructions'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFFFFD54F), width: 1.5),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BulletPoint(
                            'Upload clear after-photos showing the completed work.'),
                        SizedBox(height: 6),
                        _BulletPoint(
                            'Photos should show the same location/area as the activity.'),
                        SizedBox(height: 6),
                        _BulletPoint(
                            'At least 1 photo is required; up to 5 recommended.'),
                        SizedBox(height: 6),
                        _BulletPoint(
                            'Once submitted, the community will vote to validate your work and award XP.'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Photo picker
                  _sectionLabel(
                      'After Photos (${_selectedImages.length} selected)'),
                  const SizedBox(height: 12),

                  // Thumbnails grid
                  if (_selectedImages.isNotEmpty) ...[
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: _selectedImages.length,
                      itemBuilder: (_, i) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedImages[i],
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeImage(i),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Add photos buttons
                  Row(
                    children: [
                      Expanded(
                        child: _photoBtn(
                          icon: Icons.photo_library_rounded,
                          label: 'Gallery',
                          onTap: _pickImages,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _photoBtn(
                          icon: Icons.camera_alt_rounded,
                          label: 'Camera',
                          onTap: _takePhoto,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Submit button
          Container(
            padding:
                const EdgeInsets.fromLTRB(20, 14, 20, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  disabledBackgroundColor: Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                          if (_selectedImages.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Uploading $_uploadedCount / ${_selectedImages.length}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Submit for Community Validation',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Color(0xFF163217),
      ),
    );
  }

  Widget _photoBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB0D4B0), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _deepGreen, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _deepGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ',
            style: TextStyle(
                color: Color(0xFFF57F17),
                fontWeight: FontWeight.w800,
                fontSize: 14)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4A3800),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
