import 'package:flutter/material.dart';
import 'package:sports_app1/main.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // 로그인 성공 시 홈 화면으로 이동
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const CompetitionMapScreen()),
            );
          },
          child: const Text('로그인'),
        ),
      ),
    );
  }
}
