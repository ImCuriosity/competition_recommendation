import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sports_app1/main.dart'; // For kBaseUrl, kSportCategories, etc.
import 'package:url_launcher/url_launcher.dart';

class PublicSportProgram {
  final String id;
  final String facilityName;
  final String facilityTypeName;
  final String location;
  final String sportCategory;
  final String programName;
  final String programTarget;
  final String programBeginDate;
  final String programEndDate;
  final String programDay;
  final int? programLimit;
  final double? programPrice;
  final String? homepageUrl;

  PublicSportProgram({
    required this.id,
    required this.facilityName,
    required this.facilityTypeName,
    required this.location,
    required this.sportCategory,
    required this.programName,
    required this.programTarget,
    required this.programBeginDate,
    required this.programEndDate,
    required this.programDay,
    this.programLimit,
    this.programPrice,
    this.homepageUrl,
  });

  factory PublicSportProgram.fromJson(Map<String, dynamic> json) {
    final String provinceCity = json['location_province_city'] as String? ?? '';
    final String countyDistrict = json['location_county_district'] as String? ?? '';
    final String location = '$provinceCity $countyDistrict'.trim();

    return PublicSportProgram(
      id: json['id']?.toString() ?? 'unknown_id',
      facilityName: json['fclty_name'] as String? ?? '정보 없음',
      facilityTypeName: json['fclty_type_name'] as String? ?? '정보 없음',
      location: location,
      sportCategory: json['sport_category'] as String? ?? '기타',
      programName: json['program_name'] as String? ?? '정보 없음',
      programTarget: json['program_target'] as String? ?? '정보 없음',
      programBeginDate: json['program_begin_date'] as String? ?? '미정',
      programEndDate: json['program_end_date'] as String? ?? '미정',
      programDay: json['program_day'] as String? ?? '미정',
      programLimit: json['program_limit'] as int?,
      programPrice: (json['program_price'] as num?)?.toDouble(),
      homepageUrl: json['homepage_url'] as String?,
    );
  }
}

class PublicSportProgramsScreen extends StatefulWidget {
  const PublicSportProgramsScreen({super.key});

  @override
  State<PublicSportProgramsScreen> createState() => _PublicSportProgramsScreenState();
}

class _PublicSportProgramsScreenState extends State<PublicSportProgramsScreen> {
  bool _isLoading = false;
  List<PublicSportProgram> _programs = [];
  String _selectedCategory = kSportCategories.first;
  String _selectedProvince = kProvinces.first;
  String _selectedCityCounty = '전체 시/군/구';

  @override
  void initState() {
    super.initState();
    _selectedCityCounty = kCityCountyMap[_selectedProvince]!.first;
    _fetchPrograms();
  }

  Future<void> _fetchPrograms() async {
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

    final uri = Uri.parse('$kBaseUrl/public-sport-programs').replace(queryParameters: queryParams);

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          final List<PublicSportProgram> newPrograms = (data['data'] as List)
              .map((json) => PublicSportProgram.fromJson(json))
              .toList();
          setState(() {
            _programs = newPrograms;
          });
          _showSnackBar("✅ ${newPrograms.length}개의 프로그램을 찾았습니다.");
        } else {
           _showSnackBar(data['message']?.toString() ?? "프로그램을 불러오는데 실패했습니다.");
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
  
  Future<void> _launchURL(String? url) async {
    if (url != null && url.isNotEmpty) {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showSnackBar('URL을 열 수 없습니다: $url');
      }
    } else {
      _showSnackBar('홈페이지 정보가 없습니다.');
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
        title: const Text('공공 체육 프로그램'),
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
                    onPressed: _isLoading ? null : _fetchPrograms,
                    icon: const Icon(Icons.search),
                    label: const Text('프로그램 검색', style: TextStyle(fontSize: 16)),
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
                : _programs.isEmpty
                ? const Center(child: Text("검색 조건에 맞는 프로그램이 없습니다."))
                : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _programs.length,
              itemBuilder: (context, index) {
                final program = _programs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: InkWell(
                    onTap: () => _launchURL(program.homepageUrl),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(program.programName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _buildInfoRow(Icons.business, '시설: ${program.facilityName} (${program.facilityTypeName})'),
                          const SizedBox(height: 4),
                          _buildInfoRow(Icons.place, '위치: ${program.location}'),
                          const SizedBox(height: 4),
                           _buildInfoRow(Icons.sports_soccer, '종목: ${program.sportCategory}'),
                          const SizedBox(height: 4),
                           _buildInfoRow(Icons.event, '기간: ${program.programBeginDate} ~ ${program.programEndDate}'),
                           const SizedBox(height: 4),
                           _buildInfoRow(Icons.schedule, '요일: ${program.programDay}'),
                           const SizedBox(height: 4),
                           _buildInfoRow(Icons.group, '대상: ${program.programTarget}'),
                        ],
                      ),
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

