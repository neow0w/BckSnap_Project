import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../services/auth_service.dart';
import '../../services/clinic_service.dart';
import 'consultation_chat_screen.dart';
import '../../services/screening_service.dart';
import '../../models/screening.dart';

class ConsultationScreen extends StatefulWidget {
  final String appointmentId;
  final Map<String, dynamic> credentials;

  const ConsultationScreen({
    super.key,
    required this.appointmentId,
    required this.credentials,
  });

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final ClinicService _clinicService = ClinicService();
  final ScreeningService _screeningService = ScreeningService();

  List<Screening> _patientScreenings = [];
  bool _isLoadingScreenings = false;
  String? _screeningError;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideoTrack;
  VideoTrack? _localVideoTrack;
  bool _isConnecting = true;
  bool _isChatOpen = false;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraEnabled = true;
  bool _isFrontCamera = true;
  bool _isEnding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connectToRoom();
    _loadPatientScreenings();
  }

  Future<void> _loadPatientScreenings() async {
    if (!mounted) return;

    setState(() {
      _isLoadingScreenings = true;
      _screeningError = null;
    });

    try {
      final appointment = await _clinicService.appointment(
        widget.appointmentId,
      );

      final screenings = await _screeningService.screeningsOf(
        appointment.userId,
      );

      if (!mounted) return;

      setState(() {
        _patientScreenings = screenings;
        _isLoadingScreenings = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _screeningError = 'Unable to load patient screening results.';
        _isLoadingScreenings = false;
      });
    }
  }

  Future<void> _connectToRoom() async {
    try {
      final serverUrl = widget.credentials['serverUrl'] as String;
      final token = widget.credentials['token'] as String;

      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );

      _room = room;

      final listener = room.createListener();

      _listener = listener;

      listener.on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          if (!mounted) return;

          setState(() {
            _remoteVideoTrack = event.track as VideoTrack;
          });
        }
      });

      listener.on<TrackUnsubscribedEvent>((event) {
        if (!mounted) return;

        setState(() {
          _remoteVideoTrack = null;
        });
      });

      await room.connect(serverUrl, token);

      final localParticipant = room.localParticipant;

      if (localParticipant == null) {
        throw Exception('Unable to access the local participant.');
      }
      await localParticipant.setCameraEnabled(true);
      await localParticipant.setMicrophoneEnabled(true);

      final localVideoPublication =
          localParticipant.videoTrackPublications.firstOrNull;

      if (localVideoPublication?.track is VideoTrack) {
        _localVideoTrack = localVideoPublication!.track as VideoTrack;
      }

      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _isConnected = true;
        _isCameraEnabled = true;
        _isMuted = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _error = 'Unable to connect to the consultation. Please try again.';
      });
    }
  }

  Future<void> _toggleMicrophone() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) return;

    try {
      final newMutedState = !_isMuted;

      await localParticipant.setMicrophoneEnabled(!newMutedState);

      if (!mounted) return;

      setState(() {
        _isMuted = newMutedState;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to change microphone settings.';
      });
    }
  }

  Future<void> _toggleCamera() async {
    final localParticipant = _room?.localParticipant;

    if (localParticipant == null) return;

    try {
      final newCameraState = !_isCameraEnabled;

      await localParticipant.setCameraEnabled(newCameraState);

      final publication = localParticipant.videoTrackPublications.firstOrNull;

      if (!mounted) return;

      setState(() {
        _isCameraEnabled = newCameraState;
        _localVideoTrack = newCameraState && publication?.track is VideoTrack
            ? publication!.track as VideoTrack
            : null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to change camera settings.';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (!_isCameraEnabled) return;

    final localParticipant = _room?.localParticipant;
    if (localParticipant == null) return;

    try {
      final publication = localParticipant.videoTrackPublications.firstOrNull;

      final track = publication?.track;

      if (track is! LocalVideoTrack) return;

      final newPosition = _isFrontCamera
          ? CameraPosition.back
          : CameraPosition.front;

      await track.setCameraPosition(newPosition);

      if (!mounted) return;

      setState(() {
        _isFrontCamera = !_isFrontCamera;
        _localVideoTrack = track;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to switch camera. Please try again.'),
        ),
      );
    }
  }

  void _showScreeningResults() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Patient Screening Results',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _isLoadingScreenings
                      ? const Center(child: CircularProgressIndicator())
                      : _screeningError != null
                      ? Center(child: Text(_screeningError!))
                      : _patientScreenings.isEmpty
                      ? const Center(child: Text('No screening results found.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _patientScreenings.length,
                          itemBuilder: (context, index) {
                            final screening = _patientScreenings[index];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      screening.forSelf
                                          ? 'Account Holder'
                                          : screening.subjectName ??
                                                'Other Screened Person',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Screening Date: '
                                              '${screening.createdAt.toLocal()}'
                                          .split('.')[0],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Measured Angle: '
                                      '${screening.angle.toStringAsFixed(1)}°',
                                    ),
                                    Text(
                                      'Screening Indicator: '
                                      '${screening.hasScoliosis ? 'Flagged' : 'Not flagged'}',
                                    ),
                                    if (screening.details != null) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Screening Details',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(screening.details.toString()),
                                    ],
                                    Text(
                                      'Photo: ${screening.hasPhoto ? 'Available' : 'Not available'}',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveCall() async {
    if (_isEnding) return;

    setState(() {
      _isEnding = true;
    });

    try {
      await _room?.disconnect();

      if (!mounted) return;

      context.pop();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isEnding = false;
        _error = 'Unable to leave the consultation. Please try again.';
      });
    }
  }

  Future<void> _endMeeting() async {
    if (_isEnding) return;

    // Ask the doctor to confirm.
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End Consultation?'),
        content: const Text(
          'This will permanently end the consultation '
          'for both you and the patient. The patient '
          'will no longer be able to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End Meeting'),
          ),
        ],
      ),
    );

    if (shouldEnd != true || !mounted) return;

    setState(() {
      _isEnding = true;
    });

    try {
      // Permanently close the consultation through the backend.
      await _clinicService.endConsultation(widget.appointmentId);

      // Disconnect the LiveKit room.
      await _room?.disconnect();

      if (!mounted) return;

      // Return to the previous screen.
      context.pop();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isEnding = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to end consultation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDoctor = AuthService().currentUser?.role == 'doctor';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Online Consultation'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _isConnecting
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!, textAlign: TextAlign.center))
          : Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 9,
                          color: _isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? 'Connected' : 'Disconnected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _remoteVideoTrack != null
                      ? VideoTrackRenderer(
                          _remoteVideoTrack!,
                          fit: VideoViewFit.contain,
                        )
                      : const ColoredBox(
                          color: Color(0xFF1E293B),
                          child: Center(
                            child: Text(
                              'Waiting for the other participant...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  width: MediaQuery.sizeOf(context).width >= 600
                      ? 220
                      : MediaQuery.orientationOf(context) ==
                            Orientation.landscape
                      ? 170
                      : 120,
                  height: MediaQuery.sizeOf(context).width >= 600
                      ? 140
                      : MediaQuery.orientationOf(context) ==
                            Orientation.landscape
                      ? 110
                      : 170,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _localVideoTrack != null
                        ? VideoTrackRenderer(
                            _localVideoTrack!,
                            fit: VideoViewFit.cover,
                          )
                        : const ColoredBox(
                            color: Color(0xFF334155),
                            child: Center(
                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                  ),
                ),
                if (isDoctor)
                  Positioned(
                    top: 70,
                    left: 16,
                    child: ElevatedButton.icon(
                      onPressed: _showScreeningResults,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2563EB),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Screening Results'),
                    ),
                  ),
                if (isDoctor)
                  Positioned(
                    bottom: 105,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: _isEnding ? null : _endMeeting,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('End Meeting'),
                      ),
                    ),
                  ),
                // Bottom call controls
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isChatOpen = !_isChatOpen;
                          });
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: _isChatOpen
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          fixedSize: const Size(56, 56),
                        ),
                        icon: const Icon(Icons.chat),
                        tooltip: 'Open chat',
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _toggleMicrophone,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          fixedSize: const Size(56, 56),
                        ),
                        icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: _toggleCamera,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          fixedSize: const Size(56, 56),
                        ),
                        icon: Icon(
                          _isCameraEnabled
                              ? Icons.videocam
                              : Icons.videocam_off,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _isEnding || !_isCameraEnabled
                            ? null
                            : _switchCamera,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF334155),
                          foregroundColor: Colors.white,
                          fixedSize: const Size(56, 56),
                        ),
                        icon: const Icon(Icons.cameraswitch),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: _isEnding ? null : _leaveCall,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          fixedSize: const Size(56, 56),
                        ),
                        icon: const Icon(Icons.call_end),
                      ),
                    ],
                  ),
                ),
                if (_isChatOpen)
                  Positioned(
                    top: 12,
                    right: 12,
                    bottom: 105,
                    width: MediaQuery.sizeOf(context).width >= 700
                        ? 380
                        : MediaQuery.sizeOf(context).width * 0.9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ConsultationChatScreen(
                        appointmentId: widget.appointmentId,
                        onClose: () {
                          setState(() {
                            _isChatOpen = false;
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ), // Stack
    );
  }
}
