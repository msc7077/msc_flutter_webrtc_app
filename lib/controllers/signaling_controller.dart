import 'package:get/get.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SignalingController extends GetxController {
  var myName = ''.obs;

  // 메시지 리스트: Map 형식 { 'name': String, 'message': String }
  var messages = <Map<String, String>>[].obs;

  late IO.Socket socket;

  void setMyName(String name) {
    myName.value = name;
  }

  // 소켓 서버 연결 및 이벤트 등록
  void connectSocket() {
    // 서버 URL은 실제 서버 주소로 변경하세요
    socket = IO.io('https://your-signaling-server.com', <String, dynamic>{
      'transports': ['websocket'],
    });

    socket.onConnect((_) {
      print('소켓 연결 완료');
      socket.emit('join', myName.value); // 서버에 내 이름 알리기
    });

    socket.on('message', (data) {
      // 서버로부터 메시지 받음
      // data 예: { 'name': '상대방', 'message': '안녕하세요' }
      messages.add({'name': data['name'], 'message': data['message']});
    });

    socket.onDisconnect((_) {
      print('소켓 연결 종료');
    });
  }

  // 메시지 보내기
  void sendMessage(String text) {
    if (text.isEmpty) return;

    final msg = {'name': myName.value, 'message': text};
    messages.add(msg); // 내 화면에 바로 표시

    socket.emit('message', msg); // 서버로 전송
  }

  @override
  void onClose() {
    socket.dispose();
    super.onClose();
  }
}
