
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

class ConsultationScreen extends StatefulWidget {
  final String appointmentId;
  final Map<String, dynamic> credentials;

  const ConsultationScreen({
    super.key,
    required this.appointmentId,
    required this.credentials,
  });

  @override
  State<ConsultationScreen> createState() =>
      _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VideoTrack? _remoteVideoTrack;
  VideoTrack? _localVideoTrack;
  bool _isConnecting = true;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraEnabled = true;
  bool _isEnding = false;
  String? _error;


  @override
  void initState() {
    super.initState();
    _connectToRoom();
  }

  Future<void> _connectToRoom() async {
    try {
      final serverUrl = widget.credentials['serverUrl'] as String;
      final token = widget.credentials['token'] as String;

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
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


  @override
  void dispose() {
    _listener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Online Consultation'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: _isConnecting
    ? const Center(
        child: CircularProgressIndicator(),
      )
    : _error != null
        ? Center(
            child: Text(
              _error!,
              textAlign: TextAlign.center,
            ),
          )
        : _remoteVideoTrack != null
            ? VideoTrackRenderer(_remoteVideoTrack!)
            : const Center(
                child: Text(
                  'Waiting for the other participant...',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 16,
                  ),
                ),
              ),
    );
  }
}
