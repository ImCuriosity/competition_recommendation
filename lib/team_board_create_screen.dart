import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamBoardCreateScreen extends StatefulWidget {
  const TeamBoardCreateScreen({super.key});

  @override
  State<TeamBoardCreateScreen> createState() => _TeamBoardCreateScreenState();
}

class _TeamBoardCreateScreenState extends State<TeamBoardCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxMembersController = TextEditingController();

  String? _selectedCategory;
  String _selectedStatus = '모집 중';
  String? _selectedSkillLevel;
  bool _isLoading = false;

  final List<String> _recruitmentStatuses = ['모집 중', '모집 완료'];
  final List<String> _skillLevels = ['누구나', '초급', '중급', '고급'];

  Future<void> _submitPost() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _showSnackBar('인증 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    setState(() => _isLoading = true);

    final body = json.encode({
      'title': _titleController.text,
      'content': _contentController.text,
      'sport_category': _selectedCategory,
      'location_name': _locationController.text,
      'recruitment_status': _selectedStatus,
      'required_skill_level': _selectedSkillLevel,
      'max_member_count': int.tryParse(_maxMembersController.text),
    });

    try {
      final response = await http.post(
        Uri.parse('$kBaseUrl/team-board'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}', 
        },
        body: body,
      );

      if (response.statusCode == 200) {
        _showSnackBar('게시글이 성공적으로 등록되었습니다.');
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar(errorData['detail'] ?? '게시글 등록에 실패했습니다.');
      }
    } catch (e) {
      _showSnackBar('네트워크 오류: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _locationController.dispose();
    _maxMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('팀원 모집 글쓰기'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextFormField(_titleController, '제목', '제목을 입력하세요.'),
              const SizedBox(height: 16),
              _buildDropdownButtonFormField(
                value: _selectedCategory,
                onChanged: (value) => setState(() => _selectedCategory = value),
                items: kSportCategories.where((c) => c != '전체 종목').toList(),
                labelText: '종목',
                hintText: '종목을 선택하세요',
              ),
              const SizedBox(height: 16),
              _buildTextFormField(_contentController, '내용', '내용을 입력하세요.', maxLines: 5),
              const SizedBox(height: 16),
              _buildTextFormField(_locationController, '활동 지역', '예: 서울시 강남구'),
              const SizedBox(height: 16),
              _buildDropdownButtonFormField(
                value: _selectedSkillLevel,
                onChanged: (value) => setState(() => _selectedSkillLevel = value),
                items: _skillLevels,
                labelText: '요구 실력',
                hintText: '실력 수준을 선택하세요',
              ),
              const SizedBox(height: 16),
              _buildTextFormField(_maxMembersController, '최대 인원', '숫자만 입력', keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitPost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('등록하기', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextFormField(TextEditingController controller, String label, String hint, {int? maxLines = 1, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: (value) {
        if (label != '최대 인원' && (value == null || value.isEmpty)) {
          return '$label 항목은 필수입니다.';
        }
        return null;
      },
    );
  }

  Widget _buildDropdownButtonFormField<T>({
    required T? value,
    required ValueChanged<T?> onChanged,
    required List<T> items,
    required String labelText,
    String? hintText,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
      ),
      hint: Text(hintText ?? ''),
      items: items.map<DropdownMenuItem<T>>((T item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(item.toString()),
        );
      }).toList(),
       validator: (value) {
        if (value == null) {
          return '$labelText 항목은 필수입니다.';
        }
        return null;
      },
    );
  }
}