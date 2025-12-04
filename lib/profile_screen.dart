import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sports_app1/main.dart'; // 💡 kProvinces, kCityCountyMap 사용을 위해 import

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 컨트롤러
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  // _addressController 제거됨 (드롭다운으로 대체)

  String? _selectedGender;
  final List<String> _genderOptions = ['남', '여'];

  // 💡 지역 선택 상태 변수
  String _selectedProvince = kProvinces.length > 1 ? kProvinces[1] : '서울특별시';
  String _selectedCityCounty = '';

  final List<String> _allSports = ['배드민턴', '마라톤', '보디빌딩', '테니스'];
  Map<String, String> _selectedSports = {};
  final List<String> _skillLevels = ['상', '중', '하'];

  bool _isLoading = true;
  String _initialAddress = '';

  @override
  void initState() {
    super.initState();
    // 초기 지역 설정
    _updateCityCountyList();
    _getProfile();
  }

  void _updateCityCountyList() {
    // 현재 선택된 시/도에 맞는 시/군/구 목록 가져오기
    if (kCityCountyMap.containsKey(_selectedProvince)) {
      final cities = kCityCountyMap[_selectedProvince]!;
      // 목록이 있고 선택된 값이 목록에 없으면 첫 번째 값(혹은 '전체' 제외한 첫 번째)으로 설정
      if (cities.isNotEmpty) {
        // 기존 선택값이 목록에 있으면 유지, 없으면 리셋
        if (!_selectedCityCounty.isNotEmpty || !cities.contains(_selectedCityCounty)) {
          if (cities.length > 1 && cities.first.contains('전체')) {
            _selectedCityCounty = cities[1];
          } else {
            _selectedCityCounty = cities.first;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // ✅ 프로필 가져오기
  Future<void> _getProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      final sportsData = await Supabase.instance.client
          .from('interesting_sports')
          .select('sport_name, skill')
          .eq('user_id', userId);

      if (mounted) {
        setState(() {
          if (profileData != null) {
            _nicknameController.text = (profileData['nickname'] ?? '') as String;
            _phoneController.text = (profileData['phone_number'] ?? '') as String;
            _ageController.text = (profileData['age']?.toString() ?? '');

            // 💡 저장된 주소 파싱하여 드롭다운 초기값 설정
            String savedAddress = (profileData['address'] ?? '') as String;
            _initialAddress = savedAddress;

            if (savedAddress.isNotEmpty) {
              final parts = savedAddress.split(' ');
              // "시/도 시/군/구" 형식이라고 가정하고 파싱
              if (parts.isNotEmpty && kProvinces.contains(parts[0])) {
                _selectedProvince = parts[0];
                if (parts.length > 1) {
                  // 해당 시/도의 시/군/구 목록에 있는지 확인
                  final cities = kCityCountyMap[_selectedProvince] ?? [];
                  if (cities.contains(parts[1])) {
                    _selectedCityCounty = parts[1];
                  }
                } else {
                  // 시/도만 있고 시/군/구가 없는 경우 초기화
                  _updateCityCountyList();
                }
              }
            }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로드 실패: $error')));
        setState(() => _isLoading = false);
      }
    }
  }

  // 주소 변환 함수 (에러 상세 표시)
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
        if (status == 'ZERO_RESULTS') errorMsg = '주소를 찾을 수 없습니다.';
        if (status == 'REQUEST_DENIED') errorMsg = 'API 권한 오류: Geocoding API를 확인해주세요.';
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

  // ✅ 프로필 저장 로직
  Future<void> _updateProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // 💡 드롭다운 값을 합쳐서 주소 생성
      final currentAddress = '$_selectedProvince $_selectedCityCounty';

      double newLat = 0.0;
      double newLng = 0.0;

      // 주소가 변경되었거나 초기값이 비어있던 경우 좌표 갱신 시도
      if (currentAddress.isNotEmpty) {
        if (currentAddress != _initialAddress || _initialAddress.isEmpty) {
          try {
            final coords = await _getCoordinatesFromAddress(currentAddress);
            if (coords != null) {
              newLat = coords['lat']!;
              newLng = coords['lng']!;
            }
          } catch (e) {
            throw e.toString();
          }
        }
      }

      await Supabase.instance.client.rpc('create_user_profile', params: {
        '_id': userId,
        '_name': '',
        '_nickname': _nicknameController.text.trim(),
        '_phone': _phoneController.text.trim(),
        '_age': int.tryParse(_ageController.text.trim()) ?? 0,
        '_gender': _selectedGender,
        '_address': currentAddress,
        '_lat': newLat,
        '_lng': newLng,
      });

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
    // '전체'가 포함된 항목 필터링 (프로필 수정 시 실제 지역만 선택 가능하도록)
    final provinceList = kProvinces.where((p) => !p.contains('전체')).toList();
    final cityList = kCityCountyMap[_selectedProvince]!.where((c) => !c.contains('전체')).toList();

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

            _buildTextField(_nicknameController, '닉네임', type: TextInputType.text),
            const SizedBox(height: 20),

            _buildTextField(_phoneController, '전화번호', isPhone: true),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildTextField(_ageController, '나이', isNumber: true)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('성별'),
                      DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: _inputDeco('선택'),
                        items: _genderOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 💡 주소 입력: 드롭다운 적용
            const Text('활동 지역 (주소)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown('시/도', _selectedProvince, provinceList, (val) {
                    setState(() {
                      _selectedProvince = val!;
                      // 시/도가 바뀌면 하위 지역 목록 갱신 (전체 제외)
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
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text('주소를 변경하면 변경된 주소로 서비스가 제공됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),

            const SizedBox(height: 30),
            _buildLabel('관심 종목'),
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