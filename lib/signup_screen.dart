import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // 입력 컨트롤러
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();

  // 성별
  String? _selectedGender;
  final List<String> _genderOptions = ['남', '여ㅁㄴㄷ'];

  // 관심 종목 데이터
  final List<String> _allSports = ['배드민턴', '마라톤', '보디빌딩', '테니스'];
  final Map<String, String> _selectedSports = {};
  final List<String> _skillLevels = ['상', '중', '하'];

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // 💡 [수정] 상세한 에러 원인을 파악하는 주소 변환 함수
  Future<Map<String, double>?> _getCoordinatesFromAddress(String address) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) throw 'API Key가 .env 파일에 없습니다.';

    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=$address&key=$apiKey&language=ko');

      final response = await http.get(url);
      final data = json.decode(response.body);
      final status = data['status'];

      if (status == 'OK') {
        final location = data['results'][0]['geometry']['location'];
        return {'lat': location['lat'], 'lng': location['lng']};
      } else {
        // 🚨 실패 원인별 에러 메시지 생성
        String errorMessage = '주소 변환 실패 ($status)';
        if (status == 'ZERO_RESULTS') errorMessage = '해당 주소를 지도에서 찾을 수 없습니다. (도로명 주소 권장)';
        if (status == 'REQUEST_DENIED') errorMessage = 'API 권한 오류: Google Cloud에서 Geocoding API를 켜주세요.';
        if (status == 'OVER_QUERY_LIMIT') errorMessage = 'API 사용량 초과 (결제 계정 확인 필요)';

        debugPrint('Geocoding Error Details: ${data['error_message']}');
        throw errorMessage;
      }
    } catch (e) {
      if (e is String) rethrow; // 위에서 던진 메시지 그대로 전달
      debugPrint('Geocoding Exception: $e');
      throw '네트워크 오류 또는 주소 변환 실패';
    }
  }

  // 실력 선택 다이얼로그
  Future<void> _showSkillDialog(String sport) async {
    final String? selectedLevel = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text('$sport 실력 선택'),
          children: _skillLevels.map((level) {
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, level);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(level, style: const TextStyle(fontSize: 16)),
              ),
            );
          }).toList(),
        );
      },
    );

    if (selectedLevel != null) {
      setState(() {
        _selectedSports[sport] = selectedLevel;
      });
    }
  }

  // 회원가입 로직
  Future<void> _signUp() async {
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty ||
        _nicknameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _ageController.text.isEmpty ||
        _addressController.text.isEmpty ||
        _selectedGender == null) {
      _showSnackBar('모든 정보를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. 주소로 좌표 구하기 (에러 발생 시 catch 블록으로 이동하여 상세 사유 표시)
      final coords = await _getCoordinatesFromAddress(_addressController.text.trim());

      // 혹시 null이 반환되더라도 안전하게 처리 (위 함수에서 throw 하므로 도달할 일은 거의 없음)
      if (coords == null) {
        throw '좌표를 가져올 수 없습니다.';
      }

      // 2. Supabase Auth 가입
      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final User? user = res.user;
      if (user == null) throw '회원가입 실패 (User is null)';

      // 3. 프로필 저장 (profiles 테이블)
      await Supabase.instance.client.rpc('create_user_profile', params: {
        '_id': user.id,
        '_name': _nameController.text.trim(),
        '_nickname': _nicknameController.text.trim(),
        '_phone': _phoneController.text.trim(),
        '_age': int.parse(_ageController.text.trim()),
        '_gender': _selectedGender,
        '_address': _addressController.text.trim(),
        '_lat': coords['lat'],
        '_lng': coords['lng'],
      });

      // 4. 관심 종목 저장 (interesting_sports 테이블)
      if (_selectedSports.isNotEmpty) {
        final List<Map<String, dynamic>> sportsData = _selectedSports.entries.map((entry) {
          return {
            'user_id': user.id,
            'sport_name': entry.key, // DB 컬럼명 확인 (sport_name)
            'skill': entry.value,    // DB 컬럼명 확인 (skill)
          };
        }).toList();

        await Supabase.instance.client.from('interesting_sports').insert(sportsData);
      }

      if (mounted) {
        _showSnackBar('회원가입 성공! 로그인해주세요.');
        Navigator.pop(context);
      }

    } on AuthException catch (e) {
      _showSnackBar(e.message, isError: true);
    } catch (e) {
      // 💡 상세 에러 메시지를 화면에 표시
      _showSnackBar('오류 발생: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4), // 에러 메시지를 읽을 수 있도록 시간 연장
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(_emailController, '이메일', Icons.email, type: TextInputType.emailAddress),
              const SizedBox(height: 10),
              _buildTextField(_passwordController, '비밀번호 (6자리 이상)', Icons.lock, isObscure: true),
              const SizedBox(height: 20),

              // 한글 입력 최적화 (text 타입)
              _buildTextField(_nameController, '이름 (실명)', Icons.person, type: TextInputType.text),
              const SizedBox(height: 10),
              _buildTextField(_nicknameController, '닉네임', Icons.face, type: TextInputType.text),
              const SizedBox(height: 10),

              // 전화번호 숫자 키패드 및 포맷터 적용
              _buildTextField(
                  _phoneController,
                  '전화번호',
                  Icons.phone,
                  type: TextInputType.number,
                  formatter: [_PhoneNumberFormatter()]
              ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(_ageController, '나이', Icons.calendar_today,
                        type: TextInputType.number, formatter: [FilteringTextInputFormatter.digitsOnly]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedGender,
                      hint: const Text('성별'),
                      decoration: _inputDeco(Icons.wc),
                      items: _genderOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                      onChanged: (val) => setState(() => _selectedGender = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTextField(_addressController, '활동 지역 (예: 서울시 강남구 역삼동)', Icons.location_on, type: TextInputType.text),

              const SizedBox(height: 30),
              const Text('관심 종목', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8.0,
                children: _allSports.map((sport) {
                  final isSelected = _selectedSports.containsKey(sport);
                  final level = _selectedSports[sport];

                  return FilterChip(
                    label: Text(isSelected ? '$sport ($level)' : sport),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        _showSkillDialog(sport);
                      } else {
                        setState(() {
                          _selectedSports.remove(sport);
                        });
                      }
                    },
                    checkmarkColor: Colors.blueAccent,
                    selectedColor: Colors.blueAccent.withOpacity(0.2),
                  );
                }).toList(),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _signUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('가입하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon,
      {bool isObscure = false, TextInputType? type, List<TextInputFormatter>? formatter}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: type ?? TextInputType.text,
      inputFormatters: formatter,
      autocorrect: false, // 한글 입력 오류 방지
      enableSuggestions: false, // 한글 입력 오류 방지
      decoration: _inputDeco(icon).copyWith(labelText: hint),
    );
  }

  InputDecoration _inputDeco(IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {

    // 숫자만 추출
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 11) {
      return oldValue;
    }

    final buffer = StringBuffer();
    if (digits.length <= 3) {
      buffer.write(digits);
    } else if (digits.length <= 7) {
      buffer.write('${digits.substring(0, 3)}-${digits.substring(3)}');
    } else {
      buffer.write('${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}');
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}