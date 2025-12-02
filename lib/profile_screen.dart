import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 숫자 입력을 위한 패키지
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // 1. 컨트롤러 정의 (이름, 닉네임, 나이, 전화번호)
  final _nameController = TextEditingController(); // name 컬럼
  final _nicknameController = TextEditingController(); // nickname 컬럼
  final _ageController = TextEditingController(); // age 컬럼
  final _phoneController = TextEditingController(); // phone_number 컬럼

  // 성별은 선택 값으로 관리
  String? _selectedGender;
  final List<String> _genderOptions = ['남성', '여성'];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ✅ 프로필 정보 불러오기
  Future<void> _getProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      // DB 데이터 -> 컨트롤러에 할당
      _nameController.text = (data['name'] ?? '') as String;
      _nicknameController.text = (data['nickname'] ?? '') as String;
      _phoneController.text = (data['phone_number'] ?? '') as String;

      // 나이는 정수형이므로 문자열로 변환
      if (data['age'] != null) {
        _ageController.text = data['age'].toString();
      }

      // 성별 설정
      if (data['gender'] != null && _genderOptions.contains(data['gender'])) {
        _selectedGender = data['gender'] as String;
      }

    } on PostgrestException catch (error) {
      print("프로필 로드 오류 (신규 유저): ${error.message}");
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필 로드 실패: $error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ✅ 프로필 정보 업데이트 (저장)
  Future<void> _updateProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // 입력값 가져오기
      final name = _nameController.text.trim();
      final nickname = _nicknameController.text.trim();
      final phone = _phoneController.text.trim();
      final ageString = _ageController.text.trim();
      final int? age = ageString.isNotEmpty ? int.tryParse(ageString) : null;
      final gender = _selectedGender;

      final updates = {
        'id': userId,
        'name': name,            // name 컬럼으로 저장
        'nickname': nickname,    // nickname 컬럼으로 저장
        'age': age,
        'gender': gender,
        'phone_number': phone,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client.from('profiles').upsert(updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 성공적으로 저장되었습니다!'), backgroundColor: Colors.green),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필 저장 실패: $error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 정보 수정'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 이메일 정보 (수정 불가)
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

            // 1. 이름 (Name)
            _buildLabel('이름'),
            TextFormField(
              controller: _nameController,
              keyboardType: TextInputType.name,
              decoration: _buildInputDecoration('이름을 입력하세요 (예: 홍길동)'),
            ),
            const SizedBox(height: 20),

            // 2. 닉네임 (Nickname)
            _buildLabel('닉네임'),
            TextFormField(
              controller: _nicknameController,
              decoration: _buildInputDecoration('닉네임을 입력하세요'),
            ),
            const SizedBox(height: 20),

            // 3. 나이 (Age)
            _buildLabel('나이'),
            TextFormField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], // 숫자만 입력 가능
              decoration: _buildInputDecoration('나이를 입력하세요 (숫자)'),
            ),
            const SizedBox(height: 20),

            // 4. 성별 (Gender) - 드롭다운
            _buildLabel('성별'),
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: _buildInputDecoration('성별을 선택하세요'),
              items: _genderOptions.map((String gender) {
                return DropdownMenuItem<String>(
                  value: gender,
                  child: Text(gender),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedGender = newValue;
                });
              },
            ),
            const SizedBox(height: 20),

            // 5. 전화번호 (Phone Number)
            _buildLabel('전화번호'),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              // 💡 수정됨: 커스텀 포맷터 적용 (숫자만 입력해도 하이픈 자동 생성)
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly, // 숫자 이외 입력 방지
                _PhoneNumberFormatter(), // 하이픈 자동 삽입
              ],
              decoration: _buildInputDecoration('전화번호를 입력하세요 (숫자만 입력)'),
            ),
            const SizedBox(height: 40),

            // 저장 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 라벨 위젯 헬퍼
  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  // 입력창 스타일 헬퍼
  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.grey),
      ),
    );
  }
}

// 💡 추가됨: 휴대폰 번호 자동 포맷터 클래스
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    // 1. 현재 텍스트 값
    final text = newValue.text;

    // 2. 포맷팅된 문자열을 담을 버퍼
    final buffer = StringBuffer();

    // 3. 길이에 따라 하이픈(-) 위치 결정 (일반적인 010-XXXX-XXXX 형식)
    if (text.length <= 3) {
      buffer.write(text);
    } else if (text.length <= 7) {
      buffer.write('${text.substring(0, 3)}-${text.substring(3)}');
    } else {
      buffer.write('${text.substring(0, 3)}-${text.substring(3, 7)}-${text.substring(7)}');
    }

    // 4. 최대 길이 제한 (하이픈 포함 13자리)
    var string = buffer.toString();
    if (string.length > 13) {
      string = string.substring(0, 13);
    }

    // 5. 커서 위치를 항상 끝으로 유지
    return TextEditingValue(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}