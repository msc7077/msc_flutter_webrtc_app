import 'package:flutter/material.dart';
import 'call_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: RoleSelectionPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  void _navigate(BuildContext context, bool isCaller) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(isCaller: isCaller)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("역할 선택")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => _navigate(context, true),
              icon: const Icon(Icons.call),
              label: const Text("발신자 (Caller)"),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _navigate(context, false),
              icon: const Icon(Icons.call_received),
              label: const Text("수신자 (Callee)"),
            ),
          ],
        ),
      ),
    );
  }
}
