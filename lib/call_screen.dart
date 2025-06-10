import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_turn_test.dart';

class CallScreen extends StatefulWidget {
  final bool isCaller; // true: 발신자, false: 수신자

  const CallScreen({super.key, required this.isCaller});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  late Signaling _signaling;

  final String TAG = 'WebRTC Signaling';

  final _config = {
    'iceServers': [
      // {'urls': 'stun:stageturn.kidkids.net:3478'},
      {
        'urls': [
          // 'turn:stageturn.kidkids.net:3478?transport=udp',
          // 'turn:stageturn.kidkids.net:3478?transport=tcp',
          'turn:stageturn.kidkids.net:5349?transport=udp',
          'turn:stageturn.kidkids.net:5349?transport=tcp',
          // 'turns:stageturn.kidkids.net:5349?transport=udp',
          // 'turns:stageturn.kidkids.net:5349?transport=tcp',
          // 'turns:stageturn.kidkids.net:5349',
        ],
        'username': 'ekuser',
        'credential': 'kidkids!@#890',
      },
    ],
  };

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _start();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _start() async {
    _signaling = Signaling(
      serverUrl: 'wss://stagesignal.kidkids.net',
      roomId: 'room1234',
      onOffer: _onOffer,
      onAnswer: _onAnswer,
      onCandidate: _onCandidate,
    );
    _signaling.connect();

    _peerConnection = await createPeerConnection(_config);
    final mediaStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });

    _localRenderer.srcObject = mediaStream;
    for (var track in mediaStream.getTracks()) {
      _peerConnection?.addTrack(track, mediaStream);
    }

    final stats = await _peerConnection?.getStats();
    for (var report in stats!) {
      if (report.type == 'candidate-pair' &&
          report.values['state'] == 'succeeded') {
        print('✅ 연결 성공: ${report.values}');
      }
    }

    _peerConnection?.onTrack = (event) {
      print('$TAG 🧊 onTrack: ${event}');
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    _peerConnection?.onIceCandidate = (candidate) {
      print('$TAG 🧊 ICE 후보 수집: ${candidate.candidate}');
      if (candidate != null) _signaling.sendCandidate(candidate);
    };

    _peerConnection?.onIceConnectionState = (state) {
      print('$TAG 📶 ICE 연결 상태: $state');
    };

    if (widget.isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _signaling.sendOffer(offer);
    }
  }

  Future<void> _onOffer(RTCSessionDescription offer) async {
    await _peerConnection?.setRemoteDescription(offer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _signaling.sendAnswer(answer);
  }

  Future<void> _onAnswer(RTCSessionDescription answer) async {
    await _peerConnection?.setRemoteDescription(answer);
  }

  void _onCandidate(RTCIceCandidate candidate) {
    _peerConnection?.addCandidate(candidate);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _peerConnection?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isCaller ? 'Caller' : 'Callee')),
      body: Column(
        children: [
          Expanded(child: RTCVideoView(_localRenderer, mirror: true)),
          Expanded(child: RTCVideoView(_remoteRenderer)),
        ],
      ),
    );
  }
}
