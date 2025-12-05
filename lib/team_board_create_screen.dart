import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories, kProvinces, kCityCountyMap
import 'package:sports_app1/team_board_screen.dart'; // For TeamBoardPost
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamBoardCreateScreen extends StatefulWidget {
  final TeamBoardPost? postToEdit;

  const TeamBoardCreateScreen({super.key, this.postToEdit});

  @override
  State<TeamBoardCreateScreen> createState() => _TeamBoardCreateScreenState();
}

class _TeamBoardCreateScreenState extends State<TeamBoardCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _maxMembersController;

  String? _selectedCategory;
  String? _selectedProvince;
  String? _selectedCityCounty;
  String? _selectedSkillLevel;
  String _selectedStatus = '모집 중';
  bool _isLoading = false;

  final List<String> _skillLevels = ['누구나', '초급', '중급', '고급'];
  final List<String> _recruitmentStatuses = ['모집 중', '모집 완료'];

  bool get _isEditMode => widget.postToEdit != null;

  @override
  void initState() {
    super.initState();

    final post = widget.postToEdit;
    _titleController = TextEditingController(text: post?.title);
    _contentController = TextEditingController(text: post?.content);
    _maxMembersController = TextEditingController(text: post?.maxMemberCount?.toString() ?? '');
    _selectedCategory = post?.sportCategory;
    _selectedSkillLevel = post?.requiredSkillLevel;
    _selectedStatus = post?.recruitmentStatus ?? '모집 중';

    if (post?.locationName != null && post!.locationName!.split(' ').length > 1) {
      _selectedProvince = post.locationName!.split(' ')[0];
      _selectedCityCounty = post.locationName!.split(' ').sublist(1).join(' ');
    } else {
      _selectedProvince = kProvinces.first;
      _selectedCityCounty = kCityCountyMap[_selectedProvince]?.first;
    }
  }

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

    final location = '$_selectedProvince $_selectedCityCounty';

    final body = json.encode({
      'title': _titleController.text,
      'content': _contentController.text,
      'sport_category': _selectedCategory,
      'location_name': location,
      'recruitment_status': _selectedStatus,
      'required_skill_level': _selectedSkillLevel,
      'max_member_count': int.tryParse(_maxMembersController.text),
    });

    try {
      http.Response response;
      if (_isEditMode) {
        response = await http.put(
          Uri.parse('$kBaseUrl/team-board/${widget.postToEdit!.id}'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: body,
        );
      } else {
        response = await http.post(
          Uri.parse('$kBaseUrl/team-board'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: body,
        );
      }

      if (response.statusCode == 200) {
        _showSnackBar(_isEditMode ? '게시글이 성공적으로 수정되었습니다.' : '게시글이 성공적으로 등록되었습니다.');
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar(errorData['detail'] ?? (_isEditMode ? '게시글 수정에 실패했습니다.' : '게시글 등록에 실패했습니다.'));
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
    _maxMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '게시글 수정' : '팀원 모집 글쓰기'),
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
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownButtonFormField(
                      value: _selectedProvince,
                      onChanged: (value) {
                        setState(() {
                          _selectedProvince = value;
                          _selectedCityCounty = kCityCountyMap[value]?.first;
                        });
                      },
                      items: kProvinces,
                      labelText: '시/도',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdownButtonFormField(
                      value: _selectedCityCounty,
                      onChanged: (value) => setState(() => _selectedCityCounty = value),
                      items: _selectedProvince != null ? kCityCountyMap[_selectedProvince]! : [],
                      labelText: '시/군/구',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDropdownButtonFormField(
                value: _selectedSkillLevel,
                onChanged: (value) => setState(() => _selectedSkillLevel = value),
                items: _skillLevels,
                labelText: '요구 실력',
                hintText: '실력 수준을 선택하세요',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextFormField(_maxMembersController, '최대 인원', '숫자만 입력', keyboardType: TextInputType.number),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDropdownButtonFormField(
                      value: _selectedStatus,
                      onChanged: (value) => setState(() => _selectedStatus = value!),
                      items: _recruitmentStatuses,
                      labelText: '모집 상태',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitPost,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isEditMode ? '수정하기' : '등록하기', style: const TextStyle(fontSize: 16)),
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