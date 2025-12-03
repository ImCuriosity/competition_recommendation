import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 컨트롤러
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _addressController = TextEditingController();

  String? _selectedGender;
  // 💡 [수정] 성별 옵션을 '남', '여'로 변경
  final List<String> _genderOptions = ['남', '여'];

  final List<String> _allSports = ['배드민턴', '마라톤', '보디빌딩', '테니스'];
  Map<String, String> _selectedSports = {};
  final List<String> _skillLevels = ['상', '중', '하'];

  bool _isLoading = true;
  String _initialAddress = '';
  // 기존 좌표 보관용 (주소 미변경 시 재사용)
  double? _currentLat;
  double? _currentLng;

  @override
  void initState() {
    super.initState();
    _getProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ✅ 프로필 가져오기 (안전하게 수정됨)
  Future<void> _getProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // 💡 [수정] .maybeSingle() 사용: 데이터가 없으면 에러 대신 null 반환
      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      // 관심 종목 조회
      final sportsData = await Supabase.instance.client
          .from('interesting_sports')
          .select('sport_name, skill')
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          if (profileData != null) {
            _nameController.text = (profileData['name'] ?? '') as String;
            _nicknameController.text = (profileData['nickname'] ?? '') as String;
            _phoneController.text = (profileData['phone_number'] ?? '') as String;
            _ageController.text = (profileData['age']?.toString() ?? '');

            _addressController.text = (profileData['address'] ?? '') as String;
            _initialAddress = _addressController.text;

            // 기존 좌표 저장 (DB에서 location을 가져오려면 select에 location 추가 필요하지만,
            // 여기서는 업데이트 시 주소 변경 여부로 판단하므로 생략하거나 필요 시 추가 구현)

            // 💡 [수정] 기존 데이터('남성', '여성')를 '남', '여'로 매핑하여 UI에 표시
            if (profileData['gender'] != null) {
              String gender = profileData['gender'] as String;
              if (gender == '남성') gender = '남';
              if (gender == '여성') gender = '여';

              if (_genderOptions.contains(gender)) {
                _selectedGender = gender;
              }
            }
          }

          _selectedSports = {
            for (var item in (sportsData as List))
              (item['sport_name'] as String): (item['skill'] as String)
          };

          _isLoading = false;
        });
      }
    } catch (error) {
      // PGRST116 에러는 이제 발생하지 않지만, 다른 에러는 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로드 실패: $error')));
        setState(() => _isLoading = false);
      }
    }
  }

  // 주소 변환 함수
  Future<Map<String, double>?> _getCoordinatesFromAddress(String address) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) throw 'API Key가 없습니다.';

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
        String errorMsg = '주소 변환 실패 ($status)';
        if (status == 'ZERO_RESULTS') errorMsg = '주소를 찾을 수 없습니다. 도로명 주소로 입력해주세요.';
        if (status == 'REQUEST_DENIED') errorMsg = 'API 권한 오류: Google Cloud에서 Geocoding API를 켜주세요.';
        throw errorMsg;
      }
    } catch (e) {
      if (e is String) rethrow;
      throw '네트워크 오류: $e';
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

  // ✅ 프로필 저장 로직 (복구 기능 포함)
  Future<void> _updateProfile() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이름을 입력해주세요.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final currentAddress = _addressController.text.trim();

      // 기본값 0.0 (기존 데이터가 없어서 좌표를 모를 경우를 대비)
      double newLat = 0.0;
      double newLng = 0.0;

      // 1. 주소 변환 시도
      if (currentAddress.isNotEmpty) {
        // 주소가 바뀌었거나, 처음 입력하는 경우 API 호출
        if (currentAddress != _initialAddress || _initialAddress.isEmpty) {
          final coords = await _getCoordinatesFromAddress(currentAddress);
          if (coords != null) {
            newLat = coords['lat']!;
            newLng = coords['lng']!;
          }
        }
      }

      // 💡 [핵심 수정] update_user_profile 대신 create_user_profile 사용
      // create_user_profile 함수는 내부적으로 "없으면 생성, 있으면 수정(Upsert)" 로직을 가지고 있으므로 더 안전합니다.
      // 주의: 이전에 만든 SQL 함수가 _lat, _lng를 필수로 받을 수 있으므로 0.0이라도 보내줍니다.
      await Supabase.instance.client.rpc('create_user_profile', params: {
        '_id': userId,
        '_name': _nameController.text.trim(),
        '_nickname': _nicknameController.text.trim(),
        '_phone': _phoneController.text.trim(),
        '_age': int.tryParse(_ageController.text.trim()) ?? 0,
        '_gender': _selectedGender,
        '_address': currentAddress,
        '_lat': newLat,
        '_lng': newLng,
      });

      // 관심 종목 업데이트
      await Supabase.instance.client.from('interesting_sports').delete().eq('user_id', userId);

      if (_selectedSports.isNotEmpty) {
        final List<Map<String, dynamic>> sportsData = _selectedSports.entries.map((entry) {
          return {
            'user_id': userId,
            'sport_name': entry.key,
            'skill': entry.value,
          };
        }).toList();
        await Supabase.instance.client.from('interesting_sports').insert(sportsData);
      }

      setState(() {
        _initialAddress = currentAddress;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 성공적으로 저장되었습니다.'), backgroundColor: Colors.green),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보 수정')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Icon(Icons.account_circle, size: 80, color: Colors.grey),
                  const SizedBox(height: 10),
                  Text(Supabase.instance.client.auth.currentUser?.email ?? '',
                      style: const TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 30),

            _buildTextField(_nameController, '이름', type: TextInputType.text),
            const SizedBox(height: 20),
            _buildTextField(_nicknameController, '닉네임', type: TextInputType.text),
            const SizedBox(height: 20),
            _buildTextField(_phoneController, '전화번호', isPhone: true),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildTextField(_ageController, '나이', isNumber: true)),
                const SizedBox(width: 10),
                // 💡 [수정] 성별 드롭다운 위에도 라벨('성별')을 추가하여 '나이' 필드와 높이/라인을 맞춤
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('성별'),
                      DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: _inputDeco('선택'), // 힌트 텍스트 변경
                        items: _genderOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildLabel('활동 지역 (주소)'),
            TextFormField(
              controller: _addressController,
              keyboardType: TextInputType.text,
              decoration: _inputDeco('예: 서울시 강남구').copyWith(
                helperText: '주소를 변경하면 저장 시 좌표가 자동 갱신됩니다.',
              ),
            ),

            const SizedBox(height: 30),
            _buildLabel('관심 종목 (선택 시 실력 변경)'),
            Wrap(
              spacing: 8.0,
              children: _allSports.map((sport) {
                final isSelected = _selectedSports.containsKey(sport);
                final level = _selectedSports[sport];

                return FilterChip(
                  label: Text(isSelected ? '$sport ($level)' : sport),
                  selected: isSelected,
                  onSelected: (sel) {
                    if (sel) {
                      _showSkillDialog(sport);
                    } else {
                      setState(() => _selectedSports.remove(sport));
                    }
                  },
                  selectedColor: Colors.blue.withOpacity(0.2),
                  checkmarkColor: Colors.blue,
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {bool isNumber = false, bool isPhone = false, TextInputType? type}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        TextFormField(
          controller: ctrl,
          keyboardType: isNumber || isPhone ? TextInputType.number : (type ?? TextInputType.text),
          inputFormatters: [
            if (isNumber) FilteringTextInputFormatter.digitsOnly,
            if (isPhone) _PhoneNumberFormatter(),
          ],
          decoration: _inputDeco('$label을(를) 입력하세요'),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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