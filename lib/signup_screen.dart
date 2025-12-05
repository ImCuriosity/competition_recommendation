import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sports_app1/main.dart'; // 💡 kProvinces, kCityCountyMap 사용을 위해 import

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // 컨트롤러
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  // _addressController는 드롭다운 사용으로 제거됨

  // 성별
  String? _selectedGender;
  final List<String> _genderOptions = ['남', '여'];

  // 💡 지역 선택 상태 변수 (기본값 설정)
  // '전체 지역'은 제외하고 실제 지역인 두 번째 항목부터 사용
  String _selectedProvince = kProvinces.length > 1 ? kProvinces[1] : '서울특별시';
  String _selectedCityCounty = '';

  // 관심 종목 데이터
  final List<String> _allSports = ['배드민턴', '마라톤', '보디빌딩', '테니스'];
  final Map<String, String> _selectedSports = {};
  final List<String> _skillLevels = ['상', '중', '하'];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 초기 시/군/구 설정 ('전체' 제외하고 첫 번째 실제 지역 선택)
    _updateCityCountyList();
  }

  void _updateCityCountyList() {
    final cities = kCityCountyMap[_selectedProvince]!;
    // '전체 시/군/구'가 있다면 그 다음 항목을, 없으면 첫 번째 항목을 기본값으로
    if (cities.length > 1 && cities.first.contains('전체')) {
      _selectedCityCounty = cities[1];
    } else {
      _selectedCityCounty = cities.first;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // 주소 -> 좌표 변환
  Future<Map<String, double>?> _getCoordinatesFromAddress(String address) async {
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null) throw 'API Key not found';

      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=$address&key=$apiKey&language=ko');

      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final location = data['results'][0]['geometry']['location'];
        return {
          'lat': location['lat'],
          'lng': location['lng'],
        };
      }
    } catch (e) {
      debugPrint('Geocoding Error: $e');
    }
    return null;
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
    // 유효성 검사
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nicknameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _ageController.text.isEmpty ||
        _selectedGender == null) {
      _showSnackBar('모든 정보를 입력해주세요.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 💡 드롭다운으로 선택된 주소 조합
      final fullAddress = '$_selectedProvince $_selectedCityCounty';

      final coords = await _getCoordinatesFromAddress(fullAddress);
      if (coords == null) {
        throw '선택하신 지역의 좌표를 가져올 수 없습니다.';
      }

      final AuthResponse res = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final User? user = res.user;
      if (user == null) throw '회원가입 실패 (User is null)';

      // DB 저장
      await Supabase.instance.client.rpc('create_user_profile', params: {
        '_id': user.id,
        '_name': '', // 이름 필드 없음
        '_nickname': _nicknameController.text.trim(),
        '_phone': _phoneController.text.trim(),
        '_age': int.parse(_ageController.text.trim()),
        '_gender': _selectedGender,
        '_address': fullAddress, // 💡 조합된 주소 저장
        '_lat': coords['lat'],
        '_lng': coords['lng'],
      });

      if (_selectedSports.isNotEmpty) {
        final List<Map<String, dynamic>> sportsData = _selectedSports.entries.map((entry) {
          return {
            'user_id': user.id,
            'sport_name': entry.key,
            'skill': entry.value,
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
      ),
    );
  }

  // 💡 드롭다운 빌더 위젯
  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              onChanged: onChanged,
              items: items.map<DropdownMenuItem<String>>((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // '전체 지역', '전체 시/군/구'를 제외한 리스트 생성
    final provinceList = kProvinces.where((p) => !p.contains('전체')).toList();
    final cityList = kCityCountyMap[_selectedProvince]!.where((c) => !c.contains('전체')).toList();

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

              // 이름 입력 없음

              _buildTextField(_nicknameController, '닉네임', Icons.face, type: TextInputType.text),
              const SizedBox(height: 10),

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                          child: Text('성별', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedGender,
                              isExpanded: true,
                              hint: const Text('선택'),
                              items: _genderOptions.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setState(() => _selectedGender = val),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 💡 주소 입력: 드롭다운 방식
              const Text('활동 지역', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown('시/도', _selectedProvince, provinceList, (val) {
                      setState(() {
                        _selectedProvince = val!;
                        // 시/도가 바뀌면 하위 지역 목록 갱신 및 첫 번째 값 선택
                        final newCities = kCityCountyMap[val]!.where((c) => !c.contains('전체')).toList();
                        _selectedCityCounty = newCities.first;
                      });
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDropdown('시/군/구', _selectedCityCounty, cityList, (val) {
                      setState(() {
                        _selectedCityCounty = val!;
                      });
                    }),
                  ),
                ],
              ),

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
          child: Text(hint, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        TextField(
          controller: controller,
          obscureText: isObscure,
          keyboardType: type ?? TextInputType.text,
          inputFormatters: formatter,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
            hintText: '$hint 입력',
          ),
        ),
      ],
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {

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