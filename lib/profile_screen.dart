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
  final List<String> _genderOptions = ['남', '여'];

  final List<String> _allSports = ['배드민턴', '마라톤', '보디빌딩', '테니스'];
  Map<String, String> _selectedSports = {};
  final List<String> _skillLevels = ['상', '중', '하'];

  bool _isLoading = true;
  String _initialAddress = '';

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
            _nameController.text = (profileData['name'] ?? '') as String;
            _nicknameController.text = (profileData['nickname'] ?? '') as String;
            _phoneController.text = (profileData['phone_number'] ?? '') as String;
            _ageController.text = (profileData['age']?.toString() ?? '');
            _addressController.text = (profileData['address'] ?? '') as String;
            _initialAddress = _addressController.text;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('프로필 로딩 실패: $error')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Map<String, double>?> _getCoordinatesFromAddress(String address) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null) throw 'API Key가 없습니다.';
    try {
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=$address&key=$apiKey&language=ko');
      final response = await http.get(url);
      final data = json.decode(response.body);
      final status = data['status'];
      if (status == 'OK') {
        final location = data['results'][0]['geometry']['location'];
        return {'lat': location['lat'], 'lng': location['lng']};
      } else {
        throw '주소 변환 실패: $status';
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _showSkillDialog(String sport) async {
    final String? selectedLevel = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text('$sport 실력 선택'),
          children: _skillLevels.map((level) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(context, level),
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
      setState(() => _selectedSports[sport] = selectedLevel);
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.isEmpty) {
      _showSnackBar('이름을 입력해주세요.', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final currentAddress = _addressController.text.trim();
      Map<String, dynamic> profileUpdate = {
        'name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()),
        'gender': _selectedGender,
        'address': currentAddress,
      };

      if (currentAddress.isNotEmpty && currentAddress != _initialAddress) {
        final coords = await _getCoordinatesFromAddress(currentAddress);
        if (coords != null) {
          profileUpdate['location'] = 'POINT(${coords['lng']} ${coords['lat']})';
        }
      }

      await Supabase.instance.client.from('profiles').update(profileUpdate).eq('id', userId);

      await Supabase.instance.client.from('interesting_sports').delete().eq('user_id', userId);
      if (_selectedSports.isNotEmpty) {
        final sportsData = _selectedSports.entries.map((e) => {
          'user_id': userId,
          'sport_name': e.key,
          'skill': e.value,
        }).toList();
        await Supabase.instance.client.from('interesting_sports').insert(sportsData);
      }

      setState(() => _initialAddress = currentAddress);
      _showSnackBar('프로필이 성공적으로 저장되었습니다.');
    } catch (error) {
      _showSnackBar('저장 실패: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ));
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
                        Text(
                          Supabase.instance.client.auth.currentUser?.email ?? '',
                          style: const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildTextField(_nameController, '이름'),
                  const SizedBox(height: 20),
                  _buildTextField(_nicknameController, '닉네임'),
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
                  _buildLabel('활동 지역 (주소)'),
                  TextFormField(
                    controller: _addressController,
                    decoration: _inputDeco('예: 서울시 강남구').copyWith(
                      helperText: '주소를 변경하면 좌표가 자동 갱신됩니다.',
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildLabel('관심 종목 (선택 시 실력 변경)'),
                  Wrap(
                    spacing: 8.0,
                    children: _allSports.map((sport) {
                      final isSelected = _selectedSports.containsKey(sport);
                      return FilterChip(
                        label: Text(isSelected ? '$sport (${_selectedSports[sport]})' : sport),
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
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _updateProfile,
                      icon: const Icon(Icons.save), 
                      label: const Text('수정하기', style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  )
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

  Widget _buildTextField(TextEditingController ctrl, String label, {bool isNumber = false, bool isPhone = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        TextFormField(
          controller: ctrl,
          keyboardType: isNumber || isPhone ? TextInputType.number : TextInputType.text,
          inputFormatters: [if (isNumber) FilteringTextInputFormatter.digitsOnly, if (isPhone) _PhoneNumberFormatter()],
          decoration: _inputDeco('$label 입력'),
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
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) return oldValue;
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