import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // ✅ 한글 입력을 위한 import
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sports_app1/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_app1/profile_screen.dart';

import 'package:sports_app1/public_sport_programs_screen.dart';
import 'package:sports_app1/sport_clubs_screen.dart';
import 'package:sports_app1/team_board_screen.dart';

// ----------------------------------------------------
// Data Models & Constants
// ----------------------------------------------------

class Competition {
  final String id;
  final String name;
  final LatLng latLng;
  final String category;
  final String location;
  final String locationName;
  final String startDate;
  final String registerUrl;
  final String registrationStartDate;
  final String registerDeadline;

  Competition({
    required this.id,
    required this.name,
    required this.latLng,
    required this.category,
    required this.location,
    required this.locationName,
    required this.startDate,
    required this.registerUrl,
    required this.registrationStartDate,
    required this.registerDeadline,
  });

  factory Competition.fromJson(Map<String, dynamic> json) {
    final String competitionId = json['id']?.toString() ?? 'unknown_id';
    final String competitionName = (json['title'] as String?) ?? '제목 없음';
    final String competitionCategory = (json['sport_category'] as String?) ?? '기타';
    final String competitionStartDate = (json['start_date'] as String?) ?? '미정';
    final String competitionRegisterUrl = (json['homepage_url'] as String?) ?? '';
    final String competitionLocationName = (json['location_name'] as String?) ?? '장소 정보 없음';
    final String provinceCity = (json['location_province_city'] as String?) ?? '';
    final String countyDistrict = (json['location_county_district'] as String?) ?? '';
    final String competitionLocation = '$provinceCity $countyDistrict'.trim();

    String registrationPeriodString = (json['registration_period'] as String?) ?? '미정';
    String registrationStartDate = '미정';
    String registerDeadline = '미정';

    if (registrationPeriodString != '미정' && registrationPeriodString.contains(',')) {
      try {
        final parts = registrationPeriodString.replaceAll('[', '').replaceAll(')', '').split(',');
        if (parts.length == 2) {
          final startStr = parts[0].trim();
          final endStr = parts[1].trim();
          registrationStartDate = startStr;
          final DateTime endDate = DateTime.parse(endStr);
          final DateTime deadlineDate = endDate.subtract(const Duration(days: 1));
          registerDeadline = DateFormat('yyyy-MM-dd').format(deadlineDate);
        }
      } catch (e) {
        // Parsing error
      }
    }

    final double lat = (json['latitude'] as double?) ?? 0.0;
    final double lng = (json['longitude'] as double?) ?? 0.0;
    final LatLng competitionLatLng = LatLng(lat, lng);

    return Competition(
      id: competitionId,
      name: competitionName,
      latLng: competitionLatLng,
      category: competitionCategory,
      location: competitionLocation,
      locationName: competitionLocationName,
      startDate: competitionStartDate,
      registerUrl: competitionRegisterUrl,
      registrationStartDate: registrationStartDate,
      registerDeadline: registerDeadline,
    );
  }
}

const String kBaseUrl = "http://10.0.2.2:8080";
const List<String> kSportCategories = ['전체 종목', '배드민턴', '마라톤', '보디빌딩', '테니스'];
const List<String> kProvinces = ['전체 지역', '서울특별시', '부산광역시', '대구광역시', '인천광역시', '광주광역시', '대전광역시', '울산광역시', '세종특별자치시', '경기도', '강원특별자치도', '충청북도', '충청남도', '전북특별자치도', '전라남도', '경상북도', '경상남도', '제주특별자치도'];
const Map<String, List<String>> kCityCountyMap = {
  '전체 지역': ['전체 시/군/구'],
  '서울특별시': ['전체 시/군/구', '종로구', '중구', '용산구', '성동구', '광진구', '동대문구', '중랑구', '성북구', '강북구', '도봉구', '노원구', '은평구', '서대문구', '마포구', '양천구', '강서구', '구로구', '금천구', '영등포구', '동작구', '관악구', '서초구', '강남구', '송파구', '강동구'],
  '부산광역시': ['전체 시/군/구', '중구', '서구', '동구', '영도구', '부산진구', '동래구', '남구', '북구', '해운대구', '사하구', '금정구', '강서구', '연제구', '수영구', '사상구', '기장군'],
  '대구광역시': ['전체 시/군/구', '중구', '동구', '서구', '남구', '북구', '수성구', '달서구', '달성군', '군위군'],
  '인천광역시': ['전체 시/군/구', '중구', '동구', '미추홀구', '연수구', '남동구', '부평구', '계양구', '서구', '강화군', '옹진군'],
  '광주광역시': ['전체 시/군/구', '동구', '서구', '남구', '북구', '광산구'],
  '대전광역시': ['전체 시/군/구', '동구', '중구', '서구', '유성구', '대덕구'],
  '울산광역시': ['전체 시/군/구', '중구', '남구', '동구', '북구', '울주군'],
  '세종특별자치시': ['전체 시/군/구', '세종특별자치시'],
  '경기도': ['전체 시/군/구', '수원시', '성남시', '의정부시', '안양시', '부천시', '광명시', '평택시', '동두천시', '안산시', '고양시', '과천시', '구리시', '남양주시', '오산시', '시흥시', '군포시', '의왕시', '하남시', '용인시', '파주시', '이천시', '안성시', '김포시', '화성시', '광주시', '양주시', '포천시', '여주시', '연천군', '가평군', '양평군'],
  '강원특별자치도': ['전체 시/군/구', '춘천시', '원주시', '강릉시', '동해시', '태백시', '속초시', '삼척시', '홍천군', '횡성군', '영월군', '평창군', '정선군', '철원군', '화천군', '양구군', '인제군', '고성군', '양양군'],
  '충청북도': ['전체 시/군/구', '청주시', '충주시', '제천시', '보은군', '옥천군', '영동군', '진천군', '괴산군', '음성군', '단양군', '증평군'],
  '충청남도': ['전체 시/군/구', '천안시', '공주시', '보령시', '아산시', '서산시', '논산시', '계룡시', '당진시', '금산군', '부여군', '서천군', '청양군', '홍성군', '예산군', '태안군'],
  '전북특별자치도': ['전체 시/군/구', '전주시', '군산시', '익산시', '정읍시', '남원시', '김제시', '완주군', '진안군', '무주군', '장수군', '임실군', '순창군', '고창군', '부안군'],
  '전라남도': ['전체 시/군/구', '목포시', '여수시', '순천시', '나주시', '광양시', '담양군', '곡성군', '구례군', '고흥군', '보성군', '화순군', '장흥군', '강진군', '해남군', '영암군', '무안군', '함평군', '영광군', '장성군', '완도군', '진도군', '신안군'],
  '경상북도': ['전체 시/군/구', '포항시', '경주시', '김천시', '안동시', '구미시', '영주시', '영천시', '상주시', '문경시', '경산시', '의성군', '청송군', '영양군', '영덕군', '청도군', '고령군', '성주군', '칠곡군', '예천군', '봉화군', '울진군', '울릉군'],
  '경상남도': ['전체 시/군/구', '창원시', '진주시', '통영시', '사천시', '김해시', '밀양시', '거제시', '양산시', '의령군', '함안군', '창녕군', '고성군', '남해군', '하동군', '산청군', '함양군', '거창군', '합천군'],
  '제주특별자치도': ['전체 시/군/구', '제주시', '서귀포시']
};
const LatLng kInitialCameraPosition = LatLng(37.5665, 126.9780);

// ----------------------------------------------------
// App Entry Point
// ----------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // .env file not found
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl != null && supabaseAnonKey != null) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } catch (e) {
      // Supabase init failed
    }
  } else {
    // Env vars missing
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Competition App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      // ✅ --- 한글 입력을 위한 로케일 설정 ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ko', 'KR'),
      // ✅ --- 설정 끝 ---
      home: const LoginScreen(),
    );
  }
}

// ----------------------------------------------------
// Home Screen (Bottom Navigation)
// ----------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    CompetitionMapScreen(),
    PublicSportProgramsScreen(),
    SportClubsScreen(),
    TeamBoardScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.run_circle_outlined), label: '프로그램'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), label: '동호회'),
          BottomNavigationBarItem(icon: Icon(Icons.group_add_outlined), label: '팀원 모집'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}

// ----------------------------------------------------
// Competition Map Screen
// ----------------------------------------------------

class CompetitionMapScreen extends StatefulWidget {
  const CompetitionMapScreen({super.key});

  @override
  State<CompetitionMapScreen> createState() => _CompetitionMapScreenState();
}

class _CompetitionMapScreenState extends State<CompetitionMapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  List<Competition> _competitions = [];
  bool _isLoading = false;
  String _selectedCategory = kSportCategories.first;
  String _selectedProvince = kProvinces.first;
  String _selectedCityCounty = '전체 시/군/구';
  DateTime? _selectedDate;
  LatLng _userCurrentLocation = kInitialCameraPosition;

  @override
  void initState() {
    super.initState();
    _selectedCityCounty = kCityCountyMap[_selectedProvince]!.first;
    _determinePosition();
    _fetchCompetitions(isInitial: true);
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (Route<dynamic> route) => false,
        );
        _showSnackBar('로그아웃되었습니다.');
      }
    } catch (e) {
      _showSnackBar('로그아웃 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('위치 서비스가 비활성화되어 있습니다.');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('위치 권한이 거부되었습니다.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('위치 권한이 영구적으로 거부되었습니다.');
      return;
    }
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() => _userCurrentLocation = LatLng(position.latitude, position.longitude));
      _moveCameraToCurrentUserLocation();
    } catch (e) {
      _showSnackBar('현재 위치를 가져오는데 실패했습니다.');
    }
  }

  void _moveCameraToCurrentUserLocation() {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_userCurrentLocation, 14));
  }

  Future<void> _fetchCompetitions({bool isInitial = false}) async {
    setState(() => _isLoading = true);

    final Map<String, dynamic> queryParams = {};
    if (!isInitial) {
      if (_selectedCategory != '전체 종목') queryParams['sport_category'] = _selectedCategory;
      if (_selectedProvince != '전체 지역') {
        queryParams['province'] = _selectedProvince;
        if (_selectedCityCounty != '전체 시/군/구') queryParams['city_county'] = _selectedCityCounty;
      }
      if (_selectedDate != null) queryParams['available_from'] = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    }

    final uri = Uri.parse('$kBaseUrl/competitions').replace(queryParameters: queryParams);
    await _fetchDataAndUpdateMap(uri);
  }

  Future<void> _fetchAiRecommendations() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _showSnackBar('AI 추천을 받으려면 로그인이 필요합니다.');
      return;
    }

    setState(() => _isLoading = true);

    final uri = Uri.parse('$kBaseUrl/recommend/competitions');
    try {
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      });

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['recommended_by_sport'] != null) {
          
          final Map<String, dynamic> recommendationsBySport = data['recommended_by_sport'];
          final List<Competition> recommendedComps = [];

          recommendationsBySport.forEach((sport, competitions) {
            final List<Competition> comps = (competitions as List)
                .map((json) => Competition.fromJson(json))
                .toList();
            recommendedComps.addAll(comps);
          });

          _updateMarkersAndCamera(recommendedComps, isAiRecommendation: true);

        } else {
          _showSnackBar(data['message'] ?? '추천을 받아오지 못했습니다.');
        }
      } else {
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        _showSnackBar(errorData['detail'] ?? 'API 오류: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('네트워크 오류: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _fetchDataAndUpdateMap(Uri uri) async {
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data['success'] == true && data['data'] != null) {
          final List<Competition> newCompetitions = (data['data'] as List)
              .map((json) => Competition.fromJson(json))
              .where((c) => c.latLng.latitude != 0.0)
              .toList();
          _updateMarkersAndCamera(newCompetitions);
        } else {
          _updateMarkersAndCamera([]);
          _showSnackBar(data['message'] ?? "검색 결과가 없습니다.");
        }
      } else {
        _showSnackBar("API 호출 실패: HTTP ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("네트워크 오류: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateMarkersAndCamera(List<Competition> competitions, {bool isAiRecommendation = false}) {
    _competitions = competitions;
    _updateMapMarkers();
    _adjustMapBounds();

    final message = isAiRecommendation
        ? "✅ AI가 ${_competitions.length}개의 맞춤 대회를 추천했습니다."
        : "✅ ${_competitions.length}개의 대회를 찾았습니다.";

    if (_competitions.isNotEmpty) {
      _showSnackBar(message);
    }
  }

  void _updateMapMarkers() {
    final Set<Marker> newMarkers = {};
    for (var comp in _competitions) {
      newMarkers.add(Marker(
        markerId: MarkerId(comp.id),
        position: comp.latLng,
        onTap: () => _showCompetitionDetails(comp),
      ));
    }
    setState(() => _markers = newMarkers);
  }

  void _adjustMapBounds() {
    if (_mapController == null) return;

    if (_competitions.isEmpty) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(kInitialCameraPosition, 12));
      return;
    }

    if (_competitions.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_competitions.first.latLng, 15));
      return;
    }

    double minLat = _competitions.map((c) => c.latLng.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = _competitions.map((c) => c.latLng.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = _competitions.map((c) => c.latLng.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = _competitions.map((c) => c.latLng.longitude).reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _showCompetitionDetails(Competition competition) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.fromLTRB(25, 30, 25, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(competition.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87)),
                const Divider(height: 30),
                const Text('📌 장소 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 10),
                _buildModalIconTextRow(Icons.place, '주소', competition.location),
                _buildModalIconTextRow(Icons.pin_drop, '장소명', competition.locationName),
                const SizedBox(height: 25),
                const Text('⏱️ 대회 상세', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 10),
                _buildModalIconTextRow(Icons.category, '종목', competition.category),
                _buildModalIconTextRow(Icons.event_available, '대회 시작일', competition.startDate),
                const SizedBox(height: 25),
                const Text('📝 접수 기간', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 10),
                _buildModalIconTextRow(Icons.schedule_send, '접수 시작일', competition.registrationStartDate),
                _buildModalIconTextRow(Icons.date_range, '접수 마감일', competition.registerDeadline),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () => _launchURL(competition.registerUrl),
                      icon: const Icon(Icons.link),
                      label: const Text('등록 사이트 이동', style: TextStyle(fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModalIconTextRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.indigo),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      _showSnackBar('URL을 열 수 없습니다: $url');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023), lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) setState(() => _selectedDate = picked);
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 8.0), child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))),
        DropdownButton<String>(
          value: value, isExpanded: true, onChanged: onChanged,
          items: items.map<DropdownMenuItem<String>>((String item) => DropdownMenuItem<String>(value: item, child: Padding(padding: const EdgeInsets.only(left: 8.0), child: Text(item, style: const TextStyle(fontSize: 14))))).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏆 체육 대회 검색', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (Supabase.instance.client.auth.currentUser != null)
              Text('ID: ${Supabase.instance.client.auth.currentUser!.id}', style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.person), tooltip: '프로필 수정', onPressed: _isLoading ? null : _editProfile),
          IconButton(icon: const Icon(Icons.logout), tooltip: '로그아웃', onPressed: _isLoading ? null : _logout),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(target: _userCurrentLocation, zoom: 10),
            onMapCreated: (controller) {
              _mapController = controller;
              _moveCameraToCurrentUserLocation();
            },
            markers: _markers,
            myLocationEnabled: true,
            padding: const EdgeInsets.only(top: 260),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          Positioned(
            top: 10, left: 10, right: 10,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('종목', _selectedCategory, kSportCategories, (v) => setState(() => _selectedCategory = v!))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(padding: EdgeInsets.only(left: 8.0), child: Text('기간', style: TextStyle(fontSize: 12, color: Colors.grey))),
                            TextButton.icon(
                              onPressed: () => _selectDate(context),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_selectedDate == null ? '날짜 선택' : DateFormat('yy/MM/dd').format(_selectedDate!), style: const TextStyle(fontSize: 14)),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('시/도', _selectedProvince, kProvinces, (v) => setState(() { _selectedProvince = v!; _selectedCityCounty = kCityCountyMap[v]!.first; }))),
                      Expanded(child: _buildDropdown('시/군/구', _selectedCityCounty, kCityCountyMap[_selectedProvince]!, (v) => setState(() => _selectedCityCounty = v!))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _fetchCompetitions(isInitial: false),
                      icon: const Icon(Icons.search), label: const Text('대회 검색', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _fetchAiRecommendations, 
                      icon: const Icon(Icons.smart_toy_outlined, size: 20),
                      label: const Text('AI 맞춤 대회 추천 받기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE135), foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
