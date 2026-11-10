import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';

/// Admin: sets where the clinic is, without a map. The admin types the
/// address and picks the matching result. Patients' "Use my location" and
/// "Search location" use the saved position to sort clinics by distance.
class ClinicLocationScreen extends StatefulWidget {
  final bool embedded;
  const ClinicLocationScreen({super.key, this.embedded = false});

  @override
  State<ClinicLocationScreen> createState() => _ClinicLocationScreenState();
}

class _ClinicLocationScreenState extends State<ClinicLocationScreen> {
  final _service = ClinicService();
  final _search = TextEditingController();

  ClinicInfo? _clinic;
  List<GeoPoint> _matches = [];
  GeoPoint? _selected;
  bool _loading = true;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = AuthService().currentUser?.clinicId;
    if (id == null) {
      setState(() {
        _error = 'No clinic is assigned to this account.';
        _loading = false;
      });
      return;
    }
    try {
      final clinic = await _service.clinic(id);
      if (!mounted) return;
      setState(() {
        _clinic = clinic;
        _search.text = clinic.address;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the clinic.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadStatus() async {
    final id = AuthService().currentUser?.clinicId;
    if (id == null) return;
    try {
      final c = await _service.clinic(id);
      if (mounted) setState(() => _clinic = c);
    } catch (_) {}
  }

  Future<void> _find() async {
    final text = _search.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Enter at least 3 characters.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _matches = [];
      _selected = null;
    });
    try {
      final results = await _service.geocode(text);
      if (!mounted) return;
      setState(() {
        _matches = results;
        _selected = results.isEmpty ? null : results.first;
        if (results.isEmpty) {
          _error = 'No matching place found. Try adding the barangay and city.';
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not search for the address.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final pick = _selected;
    if (pick == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.updateClinicLocation(pick.latitude, pick.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clinic location saved.')));
      if (widget.embedded) {
        setState(() {
          _matches = [];
          _selected = null;
        });
        await _reloadStatus();
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/admin');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the location.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _clinic;
    final saved = c != null && c.hasMapLocation;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Clinic location'),
              leading: BackButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/admin'),
              ),
            ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Clinic location',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Patients find your clinic by distance using the '
                        'address you save here. Type the full address, '
                        'choose the matching result, then save.',
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: ListTile(
                          leading: Icon(
                            saved ? Icons.check_circle : Icons.info_outline,
                            color: saved ? Colors.green : Colors.orange,
                          ),
                          title: Text(
                            saved ? 'Location saved' : 'No location saved yet',
                          ),
                          subtitle: Text(
                            saved
                                ? '${c.latitude!.toStringAsFixed(5)}, '
                                      '${c.longitude!.toStringAsFixed(5)}'
                                : 'Patients cannot find this clinic by '
                                      'distance until you save one.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _find(),
                        decoration: InputDecoration(
                          labelText: 'Clinic address',
                          hintText: 'Street, barangay, city',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Find',
                                  onPressed: _find,
                                  icon: const Icon(Icons.arrow_forward),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Address search uses OpenStreetMap.',
                        style: TextStyle(fontSize: 11),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_matches.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Choose the matching result',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final m in _matches)
                          Card(
                            child: ListTile(
                              selected: identical(m, _selected),
                              leading: Icon(
                                identical(m, _selected)
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: primary,
                              ),
                              title: Text(m.label),
                              onTap: () => setState(() => _selected = m),
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: (_selected == null || _saving)
                            ? null
                            : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save location'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
