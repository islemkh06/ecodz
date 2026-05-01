import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/event_service.dart';

class EventCreatePage extends StatefulWidget {
  final int actId;
  final String activityTitle;

  const EventCreatePage({
    super.key,
    required this.actId,
    required this.activityTitle,
  });

  @override
  State<EventCreatePage> createState() => _EventCreatePageState();
}

class _EventCreatePageState extends State<EventCreatePage> {
  static const Color _deepGreen  = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _surface    = Color(0xFFF5FBF4);

  final _formKey          = GlobalKey<FormState>();
  final _titleCtrl        = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _maxPaxCtrl       = TextEditingController(text: '10');

  DateTime? _eventDate;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _maxPaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final minDate = now.add(const Duration(hours: 13)); // at least 13h out

    final date = await showDatePicker(
      context: context,
      initialDate: minDate,
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _deepGreen),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(minDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _deepGreen),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _eventDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventDate == null) {
      _showSnack('Please select the event date & time.', isError: true);
      return;
    }

    final expirationDate = _eventDate!.subtract(const Duration(hours: 12));
    if (expirationDate.isBefore(DateTime.now())) {
      _showSnack(
        'Event must be at least 12 hours from now (registrations close 12h before).',
        isError: true,
      );
      return;
    }

    final maxPax = int.tryParse(_maxPaxCtrl.text.trim()) ?? 0;
    if (maxPax < 2) {
      _showSnack('Maximum participants must be at least 2.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await EventService.instance.createEvent(
        actId:           widget.actId,
        title:           _titleCtrl.text.trim(),
        description:     _descriptionCtrl.text.trim().isEmpty
                             ? null
                             : _descriptionCtrl.text.trim(),
        eventDate:       _eventDate!,
        maxParticipants: maxPax,
      );

      if (mounted) {
        _showSnack('Event created successfully!');
        Navigator.of(context).pop(true); // signal success to caller
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to create event: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _deepGreen,
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
        title: const Text('Create Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Activity context chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _lightGreen,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: _deepGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Activity: ${widget.activityTitle}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _deepGreen,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Title
              _buildLabel('Event Title'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputDecoration('e.g. Saturday Clean-Up', Icons.title),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Description
              _buildLabel('Description (optional)'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionCtrl,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputDecoration('Describe what participants should expect…', Icons.notes),
              ),
              const SizedBox(height: 16),

              // Event date/time
              _buildLabel('Event Date & Time'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _deepGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event, color: _deepGreen),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _eventDate != null
                              ? _formatDateTime(_eventDate!)
                              : 'Select date & time',
                          style: TextStyle(
                            fontSize: 14,
                            color: _eventDate != null
                                ? Colors.black87
                                : Colors.black45,
                          ),
                        ),
                      ),
                      if (_eventDate != null)
                        _ExpirationBadge(eventDate: _eventDate!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Registrations close automatically 12 hours before the event.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 16),

              // Max participants
              _buildLabel('Max Participants'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _maxPaxCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDecoration('e.g. 20', Icons.group),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 2) return 'Minimum 2 participants';
                  if (n > 500) return 'Maximum 500 participants';
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // Submit
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
                          'Create Event',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      );

  InputDecoration _inputDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: _deepGreen, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _deepGreen.withValues(alpha: 0.3), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _deepGreen.withValues(alpha: 0.3), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _deepGreen, width: 2),
        ),
      );

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  •  $h:$m';
  }
}

class _ExpirationBadge extends StatelessWidget {
  final DateTime eventDate;
  const _ExpirationBadge({required this.eventDate});

  @override
  Widget build(BuildContext context) {
    final exp = eventDate.subtract(const Duration(hours: 12));
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = exp.hour.toString().padLeft(2, '0');
    final m = exp.minute.toString().padLeft(2, '0');
    final label = '${exp.day} ${months[exp.month - 1]}  $h:$m';

    return Tooltip(
      message: 'Registration closes at $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(
          'Closes $label',
          style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
        ),
      ),
    );
  }
}
