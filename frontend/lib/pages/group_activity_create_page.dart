import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_activity_service.dart';
import '../widgets/location_picker.dart';

class GroupActivityCreatePage extends StatefulWidget {
  final VoidCallback? onCreated;
  const GroupActivityCreatePage({super.key, this.onCreated});

  @override
  State<GroupActivityCreatePage> createState() =>
      _GroupActivityCreatePageState();
}

class _GroupActivityCreatePageState extends State<GroupActivityCreatePage> {
  // -- Theme --------------------------------------------------------------------
  static const Color _green    = Color(0xFF2E7D32);
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _surface  = Color(0xFFF5FBF4);

  // -- Form ---------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _maxPaxCtrl = TextEditingController(text: '10');
  final _xpCtrl     = TextEditingController();

  List<Map<String, dynamic>> _types   = [];
  List<Map<String, dynamic>> _niveaux = [];
  int? _selectedType;
  int? _selectedNiveau;
  int? _xpMin;
  int? _xpMax;

  LocationResult? _selectedLocation;
  DateTime? _eventDate;
  bool _submitting  = false;
  bool _loadingData = true;

  // -- Image ---------------------------------------------------------------------
  XFile? _pickedImage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _maxPaxCtrl.dispose();
    _xpCtrl.dispose();
    super.dispose();
  }

  // -- Data loaders --------------------------------------------------------------
  Future<void> _loadDropdowns() async {
    try {
      final db = Supabase.instance.client;
      final results = await Future.wait([
        db.from('type_activite').select(),
        db.from('niveau_activite').select().order('xpmin'),
      ]);
      if (mounted) {
        setState(() {
          _types   = List<Map<String, dynamic>>.from(results[0] as List);
          _niveaux = List<Map<String, dynamic>>.from(results[1] as List);
          _loadingData = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  // -- Image picker ---------------------------------------------------------------
  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (picked != null && mounted) setState(() => _pickedImage = picked);
  }

  Future<String?> _uploadImage() async {
    final img = _pickedImage;
    if (img == null) return null;
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    final ext = img.path.split('.').last.toLowerCase();
    final path = 'group/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await Supabase.instance.client.storage
        .from('activity_image')
        .upload(path, File(img.path),
            fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage
        .from('activity_image')
        .getPublicUrl(path);
  }

  // -- Date/time picker -----------------------------------------------------------
  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final min = now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: min,
      firstDate: min,
      lastDate: now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32))),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(min),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D32))),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() => _eventDate =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  // -- Location picker ------------------------------------------------------------
  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationResult>(
        MaterialPageRoute(
            builder: (_) => LocationPickerPage(initial: _selectedLocation)));
    if (result != null && mounted) setState(() => _selectedLocation = result);
  }

  // -- Submit ---------------------------------------------------------------------
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventDate == null) {
      _snack('Please select the event date & time.', isError: true);
      return;
    }
    if (_eventDate!.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
      _snack('Event must be at least 1 hour in the future.', isError: true);
      return;
    }
    final maxPax = int.tryParse(_maxPaxCtrl.text.trim()) ?? 0;
    if (maxPax < 2) {
      _snack('Maximum participants must be at least 2.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final imageUrl = await _uploadImage();
      final xpVal = _xpCtrl.text.trim().isEmpty
          ? null
          : int.tryParse(_xpCtrl.text.trim());
      await GroupActivityService.instance.createGroupActivity(
        title: _titleCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        location: _selectedLocation?.address,
        latitude: _selectedLocation?.latitude,
        longitude: _selectedLocation?.longitude,
        eventDate: _eventDate!,
        maxParticipants: maxPax,
        categoryId: _selectedType,
        levelId: _selectedNiveau,
        xpFinal: xpVal,
        imageUrl: imageUrl,
      );
      if (mounted) {
        _snack('Group event submitted for community approval!');
        widget.onCreated?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _snack('Failed to create: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // -- Build ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create Group Event',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Community eco-activity',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
      ),
      body: _loadingData
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImagePicker(),
                    const SizedBox(height: 24),
                    _buildApprovalNotice(),
                    const SizedBox(height: 24),

                    // Title
                    _label('Event Title *'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _titleCtrl,
                      hint: 'e.g. Weekend Park Clean-Up',
                      icon: Icons.title_rounded,
                      caps: TextCapitalization.sentences,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 18),

                    // Description
                    _label('Description'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _descCtrl,
                      hint: 'What will participants do? What to bring?',
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                      caps: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 18),

                    // Category
                    _label('Category *'),
                    const SizedBox(height: 6),
                    _dropdown<int>(
                      value: _selectedType,
                      hint: 'Select category',
                      icon: Icons.category_outlined,
                      items: _types
                          .map((t) => DropdownMenuItem<int>(
                                value: t['id_type_act'] as int,
                                child:
                                    Text(t['nom'] as String? ?? '',
                                        style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedType = v),
                      validator: (v) =>
                          v == null ? 'Please select a category' : null,
                    ),
                    const SizedBox(height: 18),

                    // Level
                    _label('Level *'),
                    const SizedBox(height: 6),
                    _dropdown<int>(
                      value: _selectedNiveau,
                      hint: 'Select difficulty level',
                      icon: Icons.bar_chart_rounded,
                      items: _niveaux
                          .map((n) => DropdownMenuItem<int>(
                                value: n['id_niv_act'] as int,
                                child: Text(
                                    n['description'] as String? ??
                                        'Level ${n['id_niv_act']}',
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedNiveau = v;
                          if (v != null) {
                            final row = _niveaux.firstWhere(
                                (n) => n['id_niv_act'] == v,
                                orElse: () => {});
                            _xpMin = row['xpmin'] as int?;
                            _xpMax = row['xpmax'] as int?;
                            _xpCtrl.clear();
                          } else {
                            _xpMin = null;
                            _xpMax = null;
                          }
                        });
                      },
                      validator: (v) =>
                          v == null ? 'Please select a level' : null,
                    ),
                    const SizedBox(height: 18),

                    // XP Reward
                    _label('XP Reward'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _xpCtrl,
                      hint: _xpMin != null && _xpMax != null
                          ? '$_xpMin – $_xpMax XP'
                          : 'Select a level first',
                      icon: Icons.emoji_events_rounded,
                      keyboard: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      helperText: _xpMin != null && _xpMax != null
                          ? 'Allowed range: $_xpMin – $_xpMax XP'
                          : null,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        if (n == null) return 'Enter a valid number';
                        if (_xpMin != null && n < _xpMin!) {
                          return 'Minimum XP is $_xpMin';
                        }
                        if (_xpMax != null && n > _xpMax!) {
                          return 'Maximum XP is $_xpMax';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    // Location
                    _label('Location'),
                    const SizedBox(height: 6),
                    _locationButton(),
                    const SizedBox(height: 18),

                    // Date & time
                    _label('Event Date & Time *'),
                    const SizedBox(height: 6),
                    _dateTimePicker(),
                    const SizedBox(height: 18),

                    // Max participants
                    _label('Max Participants *'),
                    const SizedBox(height: 6),
                    _textField(
                      controller: _maxPaxCtrl,
                      hint: 'e.g. 20',
                      icon: Icons.groups_rounded,
                      keyboard: TextInputType.number,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 2) return 'Minimum 2 participants';
                        if (n > 500) return 'Maximum 500 participants';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _infoRow(Icons.info_outline_rounded,
                        'Participants can join once the event is approved.'),
                    const SizedBox(height: 32),
                    _submitButton(),
                  ],
                ),
              ),
            ),
    );
  }

  // -- Widgets --------------------------------------------------------------------
  Widget _buildApprovalNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: const Row(
        children: [
          Icon(Icons.how_to_vote_rounded, color: Color(0xFF2E7D32), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Group events need community approval (2 votes) before they go public.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF1B5E20),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    if (_pickedImage == null) {
      return GestureDetector(
        onTap: _pickImage,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF388E3C), Color(0xFF1B5E20)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.add_a_photo_rounded,
                  color: Colors.white70, size: 44),
              const SizedBox(height: 10),
              const Text('Tap to add a cover photo',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('Optional — attracts more participants',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(File(_pickedImage!.path),
            width: double.infinity, height: 180, fit: BoxFit.cover),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: Row(children: [
          _imgBtn(Icons.refresh_rounded, 'Change', _pickImage),
          const SizedBox(width: 6),
          _imgBtn(Icons.close_rounded, 'Remove',
              () => setState(() => _pickedImage = null)),
        ]),
      ),
    ]);
  }

  Widget _imgBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ]),
        ),
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF333333),
          letterSpacing: 0.2));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextCapitalization caps = TextCapitalization.none,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? helperText,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: caps,
        keyboardType: keyboard,
        inputFormatters: formatters,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.black.withValues(alpha: 0.35), fontSize: 13),
          helperText: helperText,
          prefixIcon: Icon(icon, color: _green, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: _green.withValues(alpha: 0.25))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: _green.withValues(alpha: 0.2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _green, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade400)),
        ),
      );

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        onChanged: onChanged,
        validator: validator,
        items: items,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.black.withValues(alpha: 0.35), fontSize: 13),
          prefixIcon: Icon(icon, color: _green, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: _green.withValues(alpha: 0.25))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: _green.withValues(alpha: 0.2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _green, width: 1.5)),
        ),
      );

  Widget _locationButton() => GestureDetector(
        onTap: _pickLocation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedLocation != null
                  ? _green
                  : _green.withValues(alpha: 0.2),
              width: _selectedLocation != null ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(Icons.location_on_rounded,
                color: _selectedLocation != null ? _green : Colors.black38,
                size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedLocation?.address ?? 'Tap to select location',
                style: TextStyle(
                    fontSize: 13,
                    color: _selectedLocation != null
                        ? Colors.black87
                        : Colors.black38),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.black38, size: 20),
          ]),
        ),
      );

  Widget _dateTimePicker() => GestureDetector(
        onTap: _pickDateTime,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _eventDate != null
                  ? _green
                  : _green.withValues(alpha: 0.2),
              width: _eventDate != null ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            Icon(Icons.event_rounded,
                color: _eventDate != null ? _green : Colors.black38, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _eventDate != null
                    ? _fmtDate(_eventDate!)
                    : 'Select date & time',
                style: TextStyle(
                    fontSize: 13,
                    color:
                        _eventDate != null ? Colors.black87 : Colors.black38),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.black38, size: 20),
          ]),
        ),
      );

  Widget _infoRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style:
                  const TextStyle(fontSize: 11.5, color: Colors.black38)),
        ),
      ]);

  Widget _submitButton() => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _green.withValues(alpha: 0.4),
            elevation: 4,
            shadowColor: _green.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.groups_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Submit for Approval',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      );

  static String _fmtDate(DateTime dt) {
    const m = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}  ·  $h:$min';
  }
}
