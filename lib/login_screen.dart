import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_app1/main.dart'; // CompetitionMapScreen을 위해 main.dart를 가져옵니다.


// 💡 클래스 이름을 기존 main.dart에서 사용하는 'LoginScreen'으로 유지합니다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 입력값을 가져오기 위한 컨트롤러
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Supabase 로그인 함수
  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일과 비밀번호를 모두 입력해주세요.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // ✅ 로그인 성공 시: 이전 스택을 모두 지우고 메인 화면으로 이동합니다.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const CompetitionMapScreen()),
        );
      }

    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('예상치 못한 오류가 발생했습니다.')),
        );
      }
    } finally {
      // 페이지가 이미 바뀌었을 수 있으므로 mounted 체크 후 로딩 해제
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Supabase 회원가입 함수 (테스트용)
  Future<void> _signUp() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이메일과 비밀번호를 모두 입력해주세요.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입 성공! 등록된 이메일로 확인 후 로그인을 시도해주세요.')),
      );
    } on AuthException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('로그인')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 앱 로고 또는 아이콘
              const Icon(
                Icons.sports_basketball,
                size: 72,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 30),
              // 이메일 입력
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              // 비밀번호 입력
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.lock),
                ),
                obscureText: true, // 비밀번호 가리기
              ),
              const SizedBox(height: 30),
              if (_isLoading)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 로그인 버튼
                    ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('로그인', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(height: 10),
                    // 회원가입 버튼
                    TextButton(
                      onPressed: _signUp,
                      child: const Text('계정이 없다면, 여기를 눌러 회원가입', style: TextStyle(color: Colors.blueGrey)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}