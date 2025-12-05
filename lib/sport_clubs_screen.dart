import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories, etc.

class SportClub {
  final String id;
  final String clubName;
  final String location;
  final String sportCategory;
  final String? afflitionGroupName;
  final String? sportCategoryDetail;
  final String? gender;
  final int? memberCount;
  final String? foundationDate;

  SportClub({
    required this.id,
    required this.clubName,
    required this.location,
    required this.sportCategory,
    this.afflitionGroupName,
    this.sportCategoryDetail,
    this.gender,
    this.memberCount,
    this.foundationDate,
  });

  factory SportClub.fromJson(Map<String, dynamic> json) {
    final String provinceCity = json['location_province_city'] as String? ?? '';
    final String countyDistrict = json['location_county_district'] as String? ?? '';
    final String location = '$provinceCity $countyDistrict'.trim();

    return SportClub(
      id: json['id']?.toString() ?? 'unknown_id',
      clubName: json['club'] as String? ?? '정보 없음',
      location: location,
      sportCategory: json['sport_category'] as String? ?? '기타',
      afflitionGroupName: json['afltion_group_name'] as String?,
      sportCategoryDetail: json['sport_categoty_detail'] as String?,
      gender: json['gender'] as String?,
      memberCount: json['mber_co'] as int?,
      foundationDate: json['fond_de'] as String?,
    );
  }
}

class SportClubsScreen extends StatefulWidget {
  const SportClubsScreen({super.key});

  @override
  State<SportClubsScreen> createState() => _SportClubsScreenState();
}

class _SportClubsScreenState extends State<SportClubsScreen> {
  bool _isLoading = false;
  List<SportClub> _clubs = [];
  String _selectedCategory = kSportCategories.first;
  String _selectedProvince = kProvinces.first;
  String _selectedCityCounty = '전체 시/군/구';

  @override
  void initState() {
    super.initState();
    _selectedCityCounty = kCityCountyMap[_selectedProvince]!.first;
    _fetchClubs();
  }

  Future<void> _fetchClubs() async {
    setState(() {
      _isLoading = true;
    });

    final Map<String, String> queryParams = {};
    if (_selectedCategory != '전체 종목') {
      queryParams['sport_category'] = _selectedCategory;
    }
    if (_selectedProvince != '전체 지역') {
      queryParams['province'] = _selectedProvince;
      if (_selectedCityCounty != '전체 시/군/구') {
        queryParams['city_county'] = _selectedCityCounty;
      }
    }

    final uri = Uri.parse('$kBaseUrl/clubs').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          final List<SportClub> newClubs = (data['data'] as List)
              .map((json) => SportClub.fromJson(json))
              .toList();
          setState(() {
            _clubs = newClubs;
          });
          _showSnackBar("✅ ${newClubs.length}개의 동호회를 찾았습니다.");
        } else {
           _showSnackBar(data['message']?.toString() ?? "동호회를 불러오는데 실패했습니다.");
        }
      } else {
        _showSnackBar("API 호출 실패: HTTP ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("네트워크 오류: API에 연결할 수 없습니다.");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        DropdownButton<String>(
          value: value,
          isExpanded: true,
          onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(item, style: const TextStyle(fontSize: 14)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('전국 체육 동호회'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0)))
            ),
            child: Column(
              children: [
                 Row(
                  children: [
                    Expanded(
                      child: _buildDropdown('종목', _selectedCategory, kSportCategories, (newValue) {
                        setState(() {
                          _selectedCategory = newValue!;
                        });
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown('시/도', _selectedProvince, kProvinces, (newValue) {
                        setState(() {
                          _selectedProvince = newValue!;
                          _selectedCityCounty = kCityCountyMap[newValue]!.first;
                        });
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown('시/군/구', _selectedCityCounty, kCityCountyMap[_selectedProvince]!, (newValue) {
                        setState(() {
                          _selectedCityCounty = newValue!;
                        });
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _fetchClubs,
                    icon: const Icon(Icons.search),
                    label: const Text('동호회 검색', style: TextStyle(fontSize: 16)),
                     style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)
                        )
                      ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _clubs.isEmpty
                ? const Center(child: Text("검색 조건에 맞는 동호회가 없습니다."))
                : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _clubs.length,
              itemBuilder: (context, index) {
                final club = _clubs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(club.clubName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildInfoRow(Icons.place, '위치: ${club.location}'),
                        const SizedBox(height: 4),
                        _buildInfoRow(Icons.sports_soccer, '종목: ${club.sportCategory} ${club.sportCategoryDetail != null ? '(${club.sportCategoryDetail})' : ''}'),
                        if (club.afflitionGroupName != null) ...[
                          const SizedBox(height: 4),
                          _buildInfoRow(Icons.group_work, '소속: ${club.afflitionGroupName}'),
                        ],
                        if (club.gender != null) ...[
                          const SizedBox(height: 4),
                          _buildInfoRow(Icons.person, '성별: ${club.gender}'),
                        ],
                        if (club.memberCount != null) ...[
                           const SizedBox(height: 4),
                          _buildInfoRow(Icons.people_outline, '인원: ${club.memberCount}명'),
                        ],
                        if (club.foundationDate != null) ...[
                           const SizedBox(height: 4),
                          _buildInfoRow(Icons.cake, '창단일: ${club.foundationDate}'),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
