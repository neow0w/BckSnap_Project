import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';

/// The receptionist taps the map to pin the clinic's location.
class ClinicLocationScreen extends StatefulWidget {
  final bool embedded;
  const ClinicLocationScreen({super.key, this.embedded = false});

  @override
  State<ClinicLocationScreen> createState() => _ClinicLocationScreenState();
}

class _ClinicLocationScreenState extends State<ClinicLocationScreen> {
  // Calamba, used when the clinic has no pin yet.
  static const _defaultCenter = LatLng(14.2117, 121.1653);

  final _service = ClinicService();
  final _map = MapController();
  final _search = TextEditingController();

  LatLng? _pin;
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _map.dispose();
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
        if (clinic.hasMapLocation) {
          _pin = LatLng(clinic.latitude!, clinic.longitude!);
        }
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

  Future<void> _find() async {
    final text = _search.text.trim();
    if (text.length < 3) return;
    setState(() => _searching = true);
    try {
      final results = await _service.geocode(text);
      if (!mounted) return;
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching place found.')),
        );
      } else {
        final p = LatLng(results.first.latitude, results.first.longitude);
        setState(() => _pin = p);
        _map.move(p, 16);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _save() async {
    final pin = _pin;
    if (pin == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.updateClinicLocation(pin.latitude, pin.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clinic location saved.')));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/admin');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _find(),
                      decoration: InputDecoration(
                        labelText: 'Search an address or place',
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
                                onPressed: _find,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Tap the map to place the pin on your clinic.'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _pin ?? _defaultCenter,
                        initialZoom: _pin == null ? 12 : 16,
                        minZoom: 4,
                        maxZoom: 18,
                        // Stop at the edges of the world instead of repeating it.
                        cameraConstraint: CameraConstraint.contain(
                          bounds: LatLngBounds(
                            const LatLng(-85, -180),
                            const LatLng(85, 180),
                          ),
                        ),
                        onMapReady: () => _map.move(
                          _pin ?? _defaultCenter,
                          _pin == null ? 12 : 16,
                        ),
                        onTap: (_, point) => setState(() => _pin = point),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.flutter_bcksnap',
                        ),
                        if (_pin != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _pin!,
                                width: 44,
                                height: 44,
                                alignment: Alignment.topCenter,
                                child: Icon(
                                  Icons.location_on,
                                  size: 44,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution(
                              '© OpenStreetMap contributors',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_pin == null || _saving) ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save location'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
