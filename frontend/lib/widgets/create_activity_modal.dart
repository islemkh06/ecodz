import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_picker.dart';
import 'duplicate_check_modal.dart';
import '../services/activity_duplicate_service.dart';
import '../services/photo_metadata_service.dart';
import '../services/user_service.dart';

class CreateActivityModal extends StatefulWidget {
  final VoidCallback onActivityCreated;

  const CreateActivityModal({super.key, required this.onActivityCreated});

  @override
  State<CreateActivityModal> createState() => _CreateActivityModalState();
}

class _CreateActivityModalState extends State<CreateActivityModal> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);

  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  final _titreController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _xpFinalController = TextEditingController();

  LocationResult? _selectedLocation;
  XFile? _pickedImage;
  final _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _niveaux = [];
  int? _selectedType;
  int? _selectedNiveau;

  bool _submitting = false;
  bool _loadingData = true;
  String? _loadError;

  // XP range for the selected level
  int? _xpMin;
  int? _xpMax;

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  @override
  void dispose() {
    _titreController.dispose();
    _descriptionController.dispose();
    _xpFinalController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(initial: _selectedLocation),
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedLocation = result);
    }
  }

  Future<void> _loadDropdownData() async {
    try {
      final results = await Future.wait([
        _supabase.from('type_activite').select(),
        _supabase.from('niveau_activite').select().order('xpmin'),
      ]);
      if (mounted) {
        setState(() {
          _types = List<Map<String, dynamic>>.from(results[0] as List);
          _niveaux = List<Map<String, dynamic>>.from(results[1] as List);
          _loadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load form data. Please try again.';
          _loadingData = false;
        });
      }
    }
  }

  // ── Duplicate check ────────────────────────────────────────────────────────

  /// Returns true if the user wants to proceed with creation,
  /// false if they cancelled or chose to join an existing activity.
  Future<bool> _runDuplicateCheck() async {
    final loc = _selectedLocation;
    if (loc == null || _selectedType == null) return true; // skip if no location/type

    final result = await ActivityDuplicateService.instance.check(
      lat:       loc.latitude,
      lon:       loc.longitude,
      typeId:    _selectedType!,
      radius:    500,
      titleHint: _titreController.text.trim().isEmpty
                     ? null
                     : _titreController.text.trim(),
    );

    if (!result.hasDuplicates) return true;
    if (!mounted) return false;

    final choice = await showDuplicateCheckModal(
      context,
      checkResult: result,
    );

    if (choice == null || choice.action == DuplicateAction.cancel) return false;
    if (choice.action == DuplicateAction.joinExisting) {
      // User wants to participate in the existing activity — close modal
      if (mounted) Navigator.of(context).pop();
      return false;
    }
    // DuplicateAction.proceedCreate — user confirmed creating a new one
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Check level permission (Level 1 cannot create single activities)
    final userLevel = UserService.instance.profile?.level ?? 1;
    if (userLevel < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to reach Level 2 (Sprout) to create activities.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to create an activity.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ── Anti-duplication check ───────────────────────────────────────────────
    setState(() => _submitting = true);
    final shouldProceed = await _runDuplicateCheck();
    if (!shouldProceed) {
      if (mounted) setState(() => _submitting = false);
      return;
    }

    try {
      // 0. Ensure a profiles row exists (guards against the FK violation
      //    that occurs when the DB trigger hasn't run yet for this user).
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': (user.userMetadata?['name'] as String?)?.isNotEmpty == true
            ? user.userMetadata!['name'] as String
            : user.email?.split('@').first ?? 'User',
        'email': user.email ?? '',
        'phone_number': user.userMetadata?['phone'] as String?,
        'level': 1,
        'reputation': 0,
      }, onConflict: 'id');

      // 1. Insert activity and retrieve its generated ID
      final response = await _supabase.from('activite').insert({
        'titre': _titreController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'localisation': _selectedLocation?.address,
        'latitude': _selectedLocation?.latitude,
        'longitude': _selectedLocation?.longitude,
        'status': 'waiting',
        'xpfinal': _xpFinalController.text.trim().isEmpty
            ? null
            : int.parse(_xpFinalController.text.trim()),
        'id_type_act': _selectedType,
        'id_niv_act': _selectedNiveau,
        'id_utilisateur': user.id,
      }).select('id_act').single();

      final activityId = response['id_act'] as int;

      // 2. Upload image if selected and link it as a preuve (type='avant')
      // Requires a public Supabase Storage bucket named 'activity-images'.
      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        final ext = _pickedImage!.name.split('.').last.toLowerCase();
        final path =
            '${user.id}/${activityId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _supabase.storage.from('activity_image').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: 'image/$ext'),
            );
        final imageUrl =
            _supabase.storage.from('activity_image').getPublicUrl(path);
        final preuveRow = await _supabase.from('preuve').insert({
          'url': imageUrl,
          'type': 'avant',
          'id_act': activityId,
        }).select('id_preuve').single();

        // 2a. Extract & persist EXIF metadata (non-blocking, best-effort)
        final preuveId = preuveRow['id_preuve'] as int?;
        if (preuveId != null) {
          final meta = await PhotoMetadataService.instance.extractMetadata(bytes);
          await PhotoMetadataService.instance.saveMetadata(
            preuveId:  preuveId,
            actId:     activityId,
            photoType: 'avant',
            meta:      meta,
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onActivityCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Activity created successfully!'),
            backgroundColor: Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on StorageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: ${e.message}'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: _loadingData
            ? const _LoadingBody()
            : _loadError != null
                ? _ErrorBody(
                    message: _loadError!,
                    onRetry: () {
                      setState(() {
                        _loadingData = true;
                        _loadError = null;
                      });
                      _loadDropdownData();
                    },
                  )
                : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'New Activity',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 8),
          const SizedBox(height: 12),

          // Title
          _buildTextField(
            controller: _titreController,
            label: 'Title',
            icon: Icons.title_rounded,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Title is required' : null,
          ),
          const SizedBox(height: 14),

          // Description
          _buildTextField(
            controller: _descriptionController,
            label: 'Description',
            icon: Icons.notes_rounded,
            maxLines: 3,
          ),
          const SizedBox(height: 14),

          // Location picker
          _buildLocationButton(),
          const SizedBox(height: 14),

          // Type dropdown
          _buildDropdown<int>(
            label: 'Activity Type',
            icon: Icons.category_outlined,
            value: _selectedType,
            items: _types
                .map((t) => DropdownMenuItem<int>(
                      value: t['id_type_act'] as int,
                      child: Text(t['nom'] as String? ?? ''),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedType = v),
            validator: (v) => v == null ? 'Please select a type' : null,
          ),
          const SizedBox(height: 14),

          // Level dropdown (must appear before XP)
          _buildDropdown<int>(
            label: 'Level',
            icon: Icons.bar_chart_rounded,
            value: _selectedNiveau,
            items: _niveaux
                .map((n) => DropdownMenuItem<int>(
                      value: n['id_niv_act'] as int,
                      child: Text(
                        n['description'] as String? ??
                            'Level ${n['id_niv_act']}',
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedNiveau = v;
                if (v != null) {
                  final row = _niveaux.firstWhere(
                    (n) => n['id_niv_act'] == v,
                    orElse: () => {},
                  );
                  _xpMin = row['xpmin'] as int?;
                  _xpMax = row['xpmax'] as int?;
                } else {
                  _xpMin = null;
                  _xpMax = null;
                }
              });
            },
            validator: (v) => v == null ? 'Please select a level' : null,
          ),
          const SizedBox(height: 14),

          // XP Final
          _buildTextField(
            controller: _xpFinalController,
            label: 'XP Final',
            icon: Icons.star_outline_rounded,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            helperText: (_xpMin != null && _xpMax != null)
                ? 'Allowed range: ‎$_xpMin – $_xpMax XP'
                : null,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final val = int.tryParse(v.trim());
              if (val == null) return 'Enter a valid number';
              if (_xpMin != null && val < _xpMin!)
                return 'Minimum XP for this level is $_xpMin';
              if (_xpMax != null && val > _xpMax!)
                return 'Maximum XP for this level is $_xpMax';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Activity photo (optional)
          _buildImagePicker(),
          const SizedBox(height: 8),

          // Status note
          Row(
            children: const [
              Icon(Icons.info_outline, size: 13, color: Colors.black38),
              SizedBox(width: 6),
              Text(
                'Status will be set to "pending" automatically.',
                style: TextStyle(fontSize: 12, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _deepGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.green.shade200,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      'Create Activity',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Image picker ─────────────────────────────────────────────

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _pickedImage = picked);
    }
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photo',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _lightGreen,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _deepGreen.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: _pickedImage != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.file(
                          File(_pickedImage!.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 150,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() => _pickedImage = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: Color(0xFF1B5E20),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap to add a photo',
                        style: TextStyle(color: Colors.black54),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '(optional)',
                        style: TextStyle(color: Colors.black38, fontSize: 12),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationButton() {
    final hasLocation = _selectedLocation != null;
    return FormField<LocationResult>(
      validator: (_) =>
          _selectedLocation == null ? 'Please pick a location on the map' : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _pickLocation,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: _lightGreen,
                borderRadius: BorderRadius.circular(14),
                border: state.hasError
                    ? Border.all(color: Colors.red)
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: _deepGreen,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasLocation
                          ? _selectedLocation!.address
                          : 'Tap to pick location on map',
                      style: TextStyle(
                        color: hasLocation ? Colors.black87 : Colors.black45,
                        fontWeight: hasLocation
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.map_outlined,
                    color: Color(0xFF1B5E20),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(
                state.errorText!,
                style:
                    const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: _inputDecoration(label, icon, helperText: helperText),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {String? helperText}) {
    const radius = BorderRadius.all(Radius.circular(14));
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperStyle: const TextStyle(
          color: Color(0xFF2E7D32), fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: _deepGreen),
      filled: true,
      fillColor: _lightGreen,
      border: const OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: Color(0xFF2E7D32))),
      errorBorder: const OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: Colors.red)),
      focusedErrorBorder: const OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: Colors.red)),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
