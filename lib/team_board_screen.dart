
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories, etc.
import 'package:sports_app1/team_board_create_screen.dart';
import 'package:sports_app1/team_board_detail_screen.dart';
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
      authorUsername: json['profiles']?['nickname'] ?? '익명', // BUG FIX: username -> nickname
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamBoardDetailScreen(postId: post.id),
      ),
    ).then((_) => _fetchPosts()); // 상세 페이지에서 돌아왔을 때 목록 새로고침
  }

  void _navigateToCreatePost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TeamBoardCreateScreen(),
      ),
    );

    if (result == true) {
      _fetchPosts();
    }
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
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6.0),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: InkWell(
                                onTap: () => _navigateToPostDetail(post),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              post.title,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Chip(
                                            label: Text(post.recruitmentStatus, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                            backgroundColor: post.recruitmentStatus == '모집 중' ? Colors.blue.shade100 : Colors.grey.shade300,
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${post.sportCategory ?? '종목무관'} | ${post.locationName ?? '지역무관'}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            post.authorUsername,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                          Text(
                                            '${post.viewsCount} 조회',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
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
            onPressed: _isLoading ? null : _fetchPosts, 
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
