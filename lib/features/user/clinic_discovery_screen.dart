import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';

class ClinicDiscoveryScreen extends StatefulWidget {
  const ClinicDiscoveryScreen({super.key});

  @override
  State<ClinicDiscoveryScreen> createState() => _ClinicDiscoveryScreenState();
}

class _ClinicDiscoveryScreenState extends State<ClinicDiscoveryScreen> {
  final ClinicService _service = ClinicService();
  final TextEditingController _query = TextEditingController();
  final TextEditingController _serviceFilter = TextEditingController();
  final MapController _mapController = MapController();
  List<ClinicInfo> _clinics = [];
  GeoPoint? _location;
  ClinicInfo? _selectedClinic;
  String? _mode;
  bool _showMap = false;
  bool _mapReady = false;
  bool _showFilters = false;
  bool _loading = false;
  bool _reloadRequested = false;
  String? _error;
  double _radiusKm = 50;
  Timer? _searchDebounce;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _query.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query
      ..removeListener(_scheduleSearch)
      ..dispose();
    _serviceFilter.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    final requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.checkHealth();
      final clinics = await _service.search(
        query: _query.text,
        location: _location,
        radiusKm: _radiusKm,
        service: _serviceFilter.text,
        mode: _mode,
      );
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _clinics = clinics;
        if (_selectedClinic != null &&
            !clinics.any((clinic) => clinic.id == _selectedClinic!.id)) {
          _selectedClinic = null;
        }
      });
      if (_mapReady) {
        final mapped = clinics.where((clinic) => clinic.hasMapLocation);
        if (mapped.isNotEmpty) _focusMap(mapped.first);
      }
    } on ApiException catch (error) {
      if (kDebugMode) {
        debugPrint('Clinic discovery failed (${error.statusCode}).');
      }
      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _clinics = [];
          _selectedClinic = null;
          _error = error.message;
        });
      }
    } finally {
      if (mounted && requestId == _loadRequestId) {
        setState(() => _loading = false);
        if (_reloadRequested) {
          _reloadRequested = false;
          scheduleMicrotask(_load);
        }
      }
    }
  }

  Future<void> _requestLocation() async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.my_location_outlined),
        title: const Text('Use your location?'),
        content: const Text(
          'Your location helps find nearby clinics and calculate distance. '
          'It is only used for this search. You can also search for a place manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage(
          'Location services are turned off. Enable them or search for a place.',
          action: SnackBarAction(
            label: 'Open settings',
            onPressed: Geolocator.openLocationSettings,
          ),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Location permission is disabled. Enable it in app settings or search for a place.',
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openAppSettings,
          ),
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Location permission is disabled. Enable it in app settings or search for a place.',
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openAppSettings,
          ),
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _showMessage(
          'Location permission was denied. Manual search is available.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      setState(() {
        _location = GeoPoint(
          label: 'Current location',
          latitude: position.latitude,
          longitude: position.longitude,
        );
      });
      await _load();
    } on TimeoutException {
      _showMessage(
        'Could not determine your location. Search for a place instead.',
      );
    } on UnsupportedError {
      _showMessage(
        'Device location is unavailable. Search for a place instead.',
      );
      await _searchLocation();
    } catch (_) {
      _showMessage(
        'Could not determine your location. Search for a place instead.',
      );
    }
  }

  Future<void> _searchLocation() async {
    final controller = TextEditingController();
    var searching = false;
    String? error;
    List<GeoPoint> matches = [];
    late StateSetter updateDialog;
    BuildContext? activeDialog;

    void setDialogError(String message) {
      final dialog = activeDialog;
      if (dialog != null && dialog.mounted) {
        updateDialog(() => error = message);
      }
    }

    Future<void> search() async {
      final text = controller.text.trim();
      if (text.length < 3) {
        setDialogError('Enter at least 3 characters.');
        return;
      }
      updateDialog(() {
        searching = true;
        error = null;
        matches = [];
      });
      try {
        final result = await _service.geocode(text);
        final dialog = activeDialog;
        if (dialog != null && dialog.mounted) {
          updateDialog(() {
            matches = result;
            if (result.isEmpty) error = 'No matching locations found.';
          });
        }
      } on ApiException catch (exception) {
        setDialogError(exception.message);
      } finally {
        final dialog = activeDialog;
        if (dialog != null && dialog.mounted) {
          updateDialog(() => searching = false);
        }
      }
    }

    final selected = await showDialog<GeoPoint>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          activeDialog = dialogContext;
          updateDialog = setDialogState;
          return AlertDialog(
            title: const Text('Search for a location'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      labelText: 'City, address or postal code',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => search(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Location search uses OpenStreetMap. Your search text is sent to OpenStreetMap Nominatim.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ),
                  if (matches.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final match = matches[index];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(match.label),
                            onTap: () => Navigator.pop(dialogContext, match),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: searching ? null : search,
                child: const Text('Search'),
              ),
            ],
          );
        },
      ),
    );
    Future.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (selected != null && mounted) {
      setState(() => _location = selected);
      await _load();
    }
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  void _focusMap(ClinicInfo clinic) {
    if (!clinic.hasMapLocation || !_mapReady) return;
    _mapController.move(LatLng(clinic.latitude!, clinic.longitude!), 12);
  }

  void _openClinic(ClinicInfo clinic) =>
      context.push('/clinics/${clinic.id}', extra: clinic);
  bool get _hasFilters =>
      _location != null ||
      _serviceFilter.text.trim().isNotEmpty ||
      _mode != null;

  Widget _filtersPanel() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _requestLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use my location'),
                ),
                OutlinedButton.icon(
                  onPressed: _searchLocation,
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Search location'),
                ),
                if (_location != null)
                  InputChip(
                    avatar: const Icon(Icons.place, size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        _location!.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    onDeleted: () {
                      setState(() => _location = null);
                      _load();
                    },
                  ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _serviceFilter,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      labelText: 'Medical service',
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: 'Apply service filter',
                        onPressed: _load,
                        icon: const Icon(Icons.filter_alt),
                      ),
                    ),
                  ),
                ),
                DropdownButton<String?>(
                  value: _mode,
                  hint: const Text('Any visit type'),
                  items: const [
                    DropdownMenuItem(
                      value: null,
                      child: Text('Any visit type'),
                    ),
                    DropdownMenuItem(
                      value: 'physical',
                      child: Text('In person'),
                    ),
                    DropdownMenuItem(value: 'online', child: Text('Online')),
                  ],
                  onChanged: (mode) {
                    setState(() => _mode = mode);
                    _load();
                  },
                ),
              ],
            ),
            if (_location != null)
              Row(
                children: [
                  const Text('Search radius'),
                  Expanded(
                    child: Slider(
                      value: _radiusKm,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      label: '${_radiusKm.round()} km',
                      onChanged: (value) => setState(() => _radiusKm = value),
                      onChangeEnd: (_) => _load(),
                    ),
                  ),
                  Text('${_radiusKm.round()} km'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a clinic'),
        actions: [
          IconButton(
            tooltip: 'My appointments',
            onPressed: () => context.push('/appointments'),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    children: [
                      TextField(
                        controller: _query,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        decoration: InputDecoration(
                          labelText: 'Clinic name',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Search',
                            onPressed: _load,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.view_list),
                                  label: Text('List'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.map_outlined),
                                  label: Text('Map'),
                                ),
                              ],
                              selected: {_showMap},
                              onSelectionChanged: (value) {
                                setState(() {
                                  _showMap = value.first;
                                  _mapReady = false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Badge(
                            smallSize: 10,
                            isLabelVisible: _hasFilters,
                            child: IconButton.filledTonal(
                              tooltip: 'Filters',
                              onPressed: () =>
                                  setState(() => _showFilters = !_showFilters),
                              icon: Icon(
                                _showFilters ? Icons.expand_less : Icons.tune,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_showFilters) _filtersPanel(),
                    ],
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  key: const ValueKey('body'),
                  child: _error != null
                      ? _buildErrorState()
                      : _showMap
                      ? _buildMap()
                      : _buildList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _clinics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_clinics.isEmpty) {
      return _emptyState(
        'No clinics found',
        'Try another name or service, choose a different location, or search again.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _clinics.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _clinicCard(_clinics[index]),
      ),
    );
  }

  Widget _buildMap() {
    if (_loading && _clinics.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_clinics.isEmpty) {
      return _emptyState(
        'No clinics found',
        'There are no clinics matching these search filters. Try another name, service, or location.',
      );
    }
    final mapped = _clinics.where((clinic) => clinic.hasMapLocation).toList();
    if (mapped.isEmpty) {
      final missingCoordinates = _clinics.length;
      return _emptyState(
        'Clinics found, but none can be mapped',
        '$missingCoordinates ${missingCoordinates == 1 ? 'clinic has' : 'clinics have'} missing or invalid coordinates. Switch to List to view clinic details.',
        action: OutlinedButton.icon(
          onPressed: () => setState(() => _showMap = false),
          icon: const Icon(Icons.view_list),
          label: const Text('View clinic list'),
        ),
      );
    }
    final initial = _location != null
        ? LatLng(_location!.latitude, _location!.longitude)
        : LatLng(mapped.first.latitude!, mapped.first.longitude!);
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initial,
              initialZoom: _location == null ? 11 : 10,
              minZoom: 4,
              maxZoom: 18,
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  const LatLng(-85, -180),
                  const LatLng(85, 180),
                ),
              ),
              onMapReady: () {
                _mapReady = true;
                _focusMap(_selectedClinic ?? mapped.first);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_bcksnap',
              ),
              MarkerLayer(
                markers: [
                  for (final clinic in mapped)
                    Marker(
                      point: LatLng(clinic.latitude!, clinic.longitude!),
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: clinic.name,
                        onPressed: () {
                          setState(() => _selectedClinic = clinic);
                          _focusMap(clinic);
                        },
                        icon: Icon(
                          Icons.location_on,
                          color: _selectedClinic?.id == clinic.id
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.primary,
                          size: 38,
                        ),
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
        if (_selectedClinic != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _clinicCard(_selectedClinic!),
          ),
        if (mapped.length < _clinics.length)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '${_clinics.length - mapped.length} clinic(s) omitted from the map because coordinates are missing or invalid.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Map data © OpenStreetMap contributors',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _clinicCard(ClinicInfo clinic) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.local_hospital_outlined)),
        title: Text(
          clinic.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(clinic.address),
              if (clinic.distanceKm != null)
                Text('${clinic.distanceKm!.toStringAsFixed(1)} km away'),
              if (clinic.phone != null && clinic.phone!.trim().isNotEmpty)
                Text('Phone: ${clinic.phone}'),
              if (clinic.services.isNotEmpty) Text(clinic.services.join(' · ')),
              if (clinic.demoAppointmentTypes.isNotEmpty)
                const Text(
                  'DEMO booking options available — fictional development data only',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              if (clinic.supportsPhysical || clinic.supportsOnline)
                Text(
                  [
                    if (clinic.supportsPhysical) 'In person',
                    if (clinic.supportsOnline) 'Online',
                  ].join(' · '),
                )
              else if (clinic.demoAppointmentTypes.isEmpty)
                const Text('Appointment types not listed'),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openClinic(clinic),
      ),
    );
  }

  Widget _buildErrorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            'Clinic search is unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  Widget _emptyState(String title, String description, {Widget? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_searching, size: 44),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action ??
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
            ],
          ),
        ),
      );
}
