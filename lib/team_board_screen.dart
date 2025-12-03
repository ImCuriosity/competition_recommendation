
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories, etc.
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Data Models ---

class TeamBoardPost {
  final int id;
  final String title;
  final String content;
  final String? sportCategory;
  final String? locationName;
  final String recruitmentStatus;
  final String? requiredSkillLevel;
  final int currentMemberCount;
  final int? maxMemberCount;
  final int viewsCount;
  final DateTime createdAt;
  final String authorUsername;

  TeamBoardPost({
    required this.id,
    required this.title,
    required this.content,
    this.sportCategory,
    this.locationName,
    required this.recruitmentStatus,
    this.requiredSkillLevel,
    required this.currentMemberCount,
    this.maxMemberCount,
    required this.viewsCount,
    required this.createdAt,
    required this.authorUsername,
  });

  factory TeamBoardPost.fromJson(Map<String, dynamic> json) {
    return TeamBoardPost(
      id: json['id'],
      title: json['title'] ?? '제목 없음',
      content: json['content'] ?? '',
      sportCategory: json['sport_category'],
      locationName: json['location_name'],
      recruitmentStatus: json['recruitment_status'] ?? '모집 중',
      requiredSkillLevel: json['required_skill_level'],
      currentMemberCount: json['current_member_count'] ?? 0,
      maxMemberCount: json['max_member_count'],
      viewsCount: json['views_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      authorUsername: json['profiles']?['username'] ?? '익명', // Assuming profiles table join
    );
  }
}

// --- Main Screen ---

class TeamBoardScreen extends StatefulWidget {
  const TeamBoardScreen({super.key});

  @override
  State<TeamBoardScreen> createState() => _TeamBoardScreenState();
}

class _TeamBoardScreenState extends State<TeamBoardScreen> {
  bool _isLoading = true;
  List<TeamBoardPost> _posts = [];
  String _selectedCategory = kSportCategories.first;
  String _selectedStatus = '전체';
  final List<String> _recruitmentStatuses = ['전체', '모집 중', '모집 완료'];

  @override
  void initState() {
    super.initState();
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    setState(() {
      _isLoading = true;
    });

    final Map<String, String> queryParams = {};
    if (_selectedCategory != '전체 종목') {
      queryParams['sport_category'] = _selectedCategory;
    }
    if (_selectedStatus != '전체') {
      queryParams['recruitment_status'] = _selectedStatus;
    }

    final uri = Uri.parse('$kBaseUrl/team-board').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          final List<TeamBoardPost> newPosts = (data['data'] as List)
              .map((postJson) => TeamBoardPost.fromJson(postJson))
              .toList();
          setState(() {
            _posts = newPosts;
          });
        } else {
          _showSnackBar(data['message'] ?? '게시글을 불러오는데 실패했습니다.');
        }
      } else {
        _showSnackBar('API 오류: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('네트워크 오류: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _navigateToPostDetail(TeamBoardPost post) {
    // Note: Detail screen to be implemented
    _showSnackBar('상세보기 화면으로 이동합니다.');
  }

  void _navigateToCreatePost() {
    // Note: Create post screen to be implemented
    _showSnackBar('글쓰기 화면으로 이동합니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('팀원 모집 게시판'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
           _buildFilterSection(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                    ? const Center(child: Text("게시글이 없습니다."))
                    : RefreshIndicator(
                        onRefresh: _fetchPosts,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _posts.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            return ListTile(
                              title: Text(post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${post.authorUsername} · ${post.sportCategory ?? '종목무관'} · ${post.locationName ?? '지역무관'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Chip(
                                    label: Text(post.recruitmentStatus),
                                    backgroundColor: post.recruitmentStatus == '모집 중' ? Colors.blue.shade100 : Colors.grey.shade300,
                                    padding: EdgeInsets.zero,
                                    labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${post.viewsCount} 조회', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                              onTap: () => _navigateToPostDetail(post),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        child: const Icon(Icons.add),
        tooltip: '글쓰기',
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
       padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
       decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))
       ),
      child: Row(
        children: [
          Expanded(child: _buildDropdown('종목', _selectedCategory, kSportCategories, (val) => setState(() => _selectedCategory = val!))),
          const SizedBox(width: 12),
          Expanded(child: _buildDropdown('상태', _selectedStatus, _recruitmentStatuses, (val) => setState(() => _selectedStatus = val!))),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _fetchPosts, 
            child: const Icon(Icons.search),
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
          )
        ],
      ),
    );
  }
  
  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButton<String>(
      value: value,
      isExpanded: true,
      onChanged: onChanged,
      hint: Text(label),
      underline: const SizedBox.shrink(),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis,))).toList(),
    );
  }
}
