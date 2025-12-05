import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:sports_app1/main.dart'; // For kBaseUrl
import 'package:sports_app1/team_board_create_screen.dart';
import 'package:sports_app1/team_board_screen.dart'; // For TeamBoardPost
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Data Models ---

class Reply {
  final int id;
  final String content;
  final DateTime createdAt;
  final String authorUsername;
  final String authorId;

  Reply({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.authorUsername,
    required this.authorId,
  });

  factory Reply.fromJson(Map<String, dynamic> json) {
    return Reply(
      id: json['id'],
      content: json['content'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      authorUsername: json['profiles']?['nickname'] ?? '익명',
      authorId: json['user_id'] ?? '',
    );
  }
}


// --- Detail Screen ---

class TeamBoardDetailScreen extends StatefulWidget {
  final int postId;

  const TeamBoardDetailScreen({super.key, required this.postId});

  @override
  State<TeamBoardDetailScreen> createState() => _TeamBoardDetailScreenState();
}

class _TeamBoardDetailScreenState extends State<TeamBoardDetailScreen> {
  bool _isLoading = true;
  TeamBoardPost? _post;
  List<Reply> _replies = [];
  String? _error;
  final _replyController = TextEditingController();

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _fetchPostDetails();
  }

  Future<void> _fetchPostDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final postFuture = http.get(Uri.parse('$kBaseUrl/team-board/${widget.postId}'));
      final repliesFuture = http.get(Uri.parse('$kBaseUrl/team-board/${widget.postId}/replies'));
      
      final responses = await Future.wait([postFuture, repliesFuture]);

      if (responses[0].statusCode == 200) {
        final postData = json.decode(utf8.decode(responses[0].bodyBytes));
        if (postData['success'] == true && postData['data'] != null) {
          _post = TeamBoardPost.fromJson(postData['data']);
        } else {
          throw Exception(postData['detail'] ?? '게시글 로딩 실패');
        }
      } else {
        throw Exception('API 오류 (게시글): ${responses[0].statusCode}');
      }

      if (responses[1].statusCode == 200) {
        final repliesData = json.decode(utf8.decode(responses[1].bodyBytes));
        if (repliesData['success'] == true && repliesData['data'] != null) {
          _replies = (repliesData['data'] as List).map((r) => Reply.fromJson(r)).toList();
        }
      } else {
         _showSnackBar('댓글 로딩 실패');
      }

    } catch (e) {
      _error = e.toString();
       _showSnackBar(_error!);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addReply() async {
    if (_replyController.text.trim().isEmpty) {
      _showSnackBar('댓글 내용을 입력해주세요.');
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _showSnackBar('인증 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    final body = json.encode({
      'content': _replyController.text.trim(),
    });

    try {
       final response = await http.post(
        Uri.parse('$kBaseUrl/team-board/${widget.postId}/replies'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}', // ✅ JWT 토큰 추가
        },
        body: body,
      );

      if (response.statusCode == 200) {
        _replyController.clear();
        _fetchPostDetails(); // Refresh replies
        _showSnackBar('댓글이 등록되었습니다.');
      } else {
         final errorData = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar(errorData['detail'] ?? '댓글 등록에 실패했습니다.');
      }
    } catch (e) {
      _showSnackBar('네트워크 오류: $e');
    }
  }
  
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _navigateToEditScreen() async {
    if (_post == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TeamBoardCreateScreen(postToEdit: _post!),
      ),
    );

    if (result == true) {
      _fetchPostDetails();
    }
  }

  Future<void> _deletePost() async {
    if (_post == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('정말로 이 게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _showSnackBar('인증 정보가 없습니다.');
      return;
    }

    try {
      final response = await http.delete(
        Uri.parse('$kBaseUrl/team-board/${_post!.id}'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      if (response.statusCode == 200) {
        _showSnackBar('게시글이 삭제되었습니다.');
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar(errorData['detail'] ?? '게시글 삭제에 실패했습니다.');
      }
    } catch (e) {
      _showSnackBar('네트워크 오류: $e');
    }
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAuthor = _post?.authorId != null && _post!.authorId == _currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글 상세'),
        actions: isAuthor
            ? [
                IconButton(icon: const Icon(Icons.edit), onPressed: _navigateToEditScreen, tooltip: '수정'),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deletePost, tooltip: '삭제'),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _post == null
                  ? const Center(child: Text('게시글이 존재하지 않습니다.'))
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _fetchPostDetails,
                            child: CustomScrollView(
                              slivers: [
                                SliverToBoxAdapter(child: _buildPostContent()),
                                SliverToBoxAdapter(child: _buildReplyHeader()),
                                _buildReplyList(),
                              ],
                            ),
                          ),
                        ),
                        _buildReplyInputField(),
                      ],
                    ),
    );
  }

  Widget _buildPostContent() {
    if (_post == null) return const SizedBox.shrink();
    final post = _post!;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(post.authorUsername, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 12),
              const Icon(Icons.access_time, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text(DateFormat('yyyy-MM-dd HH:mm').format(post.createdAt), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          Row(
             children: [
                Chip(label: Text(post.sportCategory ?? '종목 무관')),
                const SizedBox(width: 8),
                Chip(
                  label: Text(post.recruitmentStatus),
                  backgroundColor: post.recruitmentStatus == '모집 중' ? Colors.blue.shade100 : Colors.grey.shade300,
                ),
             ],
          ),
          const Divider(height: 24),
          Text(post.content, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
   Widget _buildReplyHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Text('댓글 ${_replies.length}개', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildReplyList() {
    if (_replies.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Center(child: Text('등록된 댓글이 없습니다.')),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final reply = _replies[index];
          return ListTile(
            title: Text(reply.authorUsername),
            subtitle: Text(reply.content),
            trailing: Text(DateFormat('MM-dd HH:mm').format(reply.createdAt), style: Theme.of(context).textTheme.bodySmall),
          );
        },
        childCount: _replies.length,
      ),
    );
  }

  Widget _buildReplyInputField() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              decoration: const InputDecoration(
                hintText: '댓글을 입력하세요...',
                border: OutlineInputBorder(),
                 contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _addReply,
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
