import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sports_app1/login_screen.dart';

// ----------------------------------------------------
// 대회 데이터 모델
// ----------------------------------------------------

//우리 1등임


class Competition {
  final String id;
  final String name;
  final LatLng latLng;
  final String category;
  final String location;
  final String startDate;
  final String registerUrl;

  Competition({
    required this.id,
    required this.name,
    required this.latLng,
    required this.category,
    required this.location,
    required this.startDate,
    required this.registerUrl,
  });

  factory Competition.fromJson(Map<String, dynamic> json) {
    // 💡 Null 안전성 강화: 'as' 캐스팅 대신 안전한 접근 및 기본값 제공
    // Null이 String으로 캐스팅되는 오류를 방지합니다.

    // id는 null이 아니라고 가정하고 toString() 사용
    final String competitionId = json['id']?.toString() ?? 'unknown_id';

    // 필수 필드에 Null이 들어왔을 경우 대체 값 지정
    final String competitionName = (json['name'] as String?) ?? '제목 없음';
    final String competitionCategory = (json['sport_category'] as String?) ?? '기타';
    final String competitionLocation = (json['location_city_county'] as String?) ?? '지역 정보 없음';
    final String competitionStartDate = (json['start_date'] as String?) ?? '미정';
    final String competitionRegisterUrl = (json['register_url'] as String?) ?? '';

    // 좌표는 필수이며, Null일 경우 기본값 (0.0) 할당
    final double lat = (json['latitude'] as double?) ?? 0.0;
    final double lng = (json['longitude'] as double?) ?? 0.0;

    final LatLng competitionLatLng = LatLng(lat, lng);

    return Competition(
      id: competitionId,
      name: competitionName,
      latLng: competitionLatLng,
      category: competitionCategory,
      location: competitionLocation,
      startDate: competitionStartDate,
      registerUrl: competitionRegisterUrl,
    );
  }
}

// ----------------------------------------------------
// 상수 및 초기 설정
// ----------------------------------------------------

// 백엔드 API 기본 URL (FastAPI의 기본 포트를 8000에서 8080으로 변경했습니다.)
const String kBaseUrl = "http://10.0.2.2:8080";

// 드롭다운 선택지 (백엔드와 일치하도록 설정)
const List<String> kSportCategories = ['전체 종목', '배드민턴', '마라톤', '보디빌딩', '테니스'];

// 1단계: 시/도 단위 선택지
const List<String> kProvinces = [
  '전체 지역',
  '서울특별시',
  '부산광역시',
  '대구광역시',
  '인천광역시',
  '광주광역시',
  '대전광역시',
  '울산광역시',
  '세종특별자치시',
  '경기도',
  '강원특별자치도',
  '충청북도',
  '충청남도',
  '전북특별자치도',
  '전라남도',
  '경상북도',
  '경상남도',
  '제주특별자치도'
];

// 2단계: 시/도에 따른 시/군/구 매핑 데이터
const Map<String, List<String>> kCityCountyMap = {
  '전체 지역': ['전체 시/군/구'],
  // 1. 특별시
  '서울특별시': ['전체 시/군/구', '종로구', '중구', '용산구', '성동구', '광진구', '동대문구', '중랑구', '성북구', '강북구', '도봉구', '노원구', '은평구', '서대문구', '마포구', '양천구', '강서구', '구로구', '금천구', '영등포구', '동작구', '관악구', '서초구', '강남구', '송파구', '강동구'],
  // 2. 광역시
  '부산광역시': ['전체 시/군/구', '중구', '서구', '동구', '영도구', '부산진구', '동래구', '남구', '북구', '해운대구', '사하구', '금정구', '강서구', '연제구', '수영구', '사상구', '기장군'],
  '대구광역시': ['전체 시/군/구', '중구', '동구', '서구', '남구', '북구', '수성구', '달서구', '달성군', '군위군'],
  '인천광역시': ['전체 시/군/구', '중구', '동구', '미추홀구', '연수구', '남동구', '부평구', '계양구', '서구', '강화군', '옹진군'],
  '광주광역시': ['전체 시/군/구', '동구', '서구', '남구', '북구', '광산구'],
  '대전광역시': ['전체 시/군/구', '동구', '중구', '서구', '유성구', '대덕구'],
  '울산광역시': ['전체 시/군/구', '중구', '남구', '동구', '북구', '울주군'],
  // 3. 특별자치시
  '세종특별자치시': ['전체 시/군/구', '세종특별자치시'],
  // 4. 경기도
  '경기도': ['전체 시/군/구', '수원시', '성남시', '의정부시', '안양시', '부천시', '광명시', '평택시', '동두천시', '안산시', '고양시', '과천시', '구리시', '남양주시', '오산시', '시흥시', '군포시', '의왕시', '하남시', '용인시', '파주시', '이천시', '안성시', '김포시', '화성시', '광주시', '양주시', '포천시', '여주시', '연천군', '가평군', '양평군'],
  // 5. 강원특별자치도
  '강원특별자치도': ['전체 시/군/구', '춘천시', '원주시', '강릉시', '동해시', '태백시', '속초시', '삼척시', '홍천군', '횡성군', '영월군', '평창군', '정선군', '철원군', '화천군', '양구군', '인제군', '고성군', '양양군'],
  // 6. 충청북도
  '충청북도': ['전체 시/군/구', '청주시', '충주시', '제천시', '보은군', '옥천군', '영동군', '진천군', '괴산군', '음성군', '단양군', '증평군'],
  // 7. 충청남도
  '충청남도': ['전체 시/군/구', '천안시', '공주시', '보령시', '아산시', '서산시', '논산시', '계룡시', '당진시', '금산군', '부여군', '서천군', '청양군', '홍성군', '예산군', '태안군'],
  // 8. 전북특별자치도
  '전북특별자치도': ['전체 시/군/구', '전주시', '군산시', '익산시', '정읍시', '남원시', '김제시', '완주군', '진안군', '무주군', '장수군', '임실군', '순창군', '고창군', '부안군'],
  // 9. 전라남도
  '전라남도': ['전체 시/군/구', '목포시', '여수시', '순천시', '나주시', '광양시', '담양군', '곡성군', '구례군', '고흥군', '보성군', '화순군', '장흥군', '강진군', '해남군', '영암군', '무안군', '함평군', '영광군', '장성군', '완도군', '진도군', '신안군'],
  // 10. 경상북도
  '경상북도': ['전체 시/군/구', '포항시', '경주시', '김천시', '안동시', '구미시', '영주시', '영천시', '상주시', '문경시', '경산시', '의성군', '청송군', '영양군', '영덕군', '청도군', '고령군', '성주군', '칠곡군', '예천군', '봉화군', '울진군', '울릉군'],
  // 11. 경상남도
  '경상남도': ['전체 시/군/구', '창원시', '진주시', '통영시', '사천시', '김해시', '밀양시', '거제시', '양산시', '의령군', '함안군', '창녕군', '고성군', '남해군', '하동군', '산청군', '함양군', '거창군', '합천군'],
  // 12. 특별자치도
  '제주특별자치도': ['전체 시/군/구', '제주시', '서귀포시']
};

// 초기 지도 중심점 (Google Maps의 LatLng으로 교체)
const LatLng kInitialCameraPosition = LatLng(37.5665, 126.9780); // 서울 시청


// ----------------------------------------------------
// 메인 함수 및 앱 시작
// ----------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 💡 .env 파일 로드
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("⚠️ .env 파일 로드 실패: $e");
  }

  // 💡 .env에서 클라이언트 ID 가져오기
  final String? clientId = dotenv.env['GOOGLE_MAPS_API_KEY'];

  // 지도 SDK 초기화 - Google Maps는 네이티브 파일에서 초기화하므로 Dart 코드는 간소화합니다.
  if (clientId != null && clientId.isNotEmpty) {
    print("Google Maps API 키 로드 완료. (네이티브 파일에서 키 확인 필요)");
  } else {
    print("⚠️ GOOGLE_MAPS_API_KEY가 .env 파일에 설정되지 않았습니다. 지도는 작동하지 않을 수 있습니다.");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sports Competition App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ----------------------------------------------------
// 메인 화면 위젯 (지도 및 검색 기능)
// ----------------------------------------------------

class CompetitionMapScreen extends StatefulWidget {
  const CompetitionMapScreen({super.key});

  @override
  State<CompetitionMapScreen> createState() => _CompetitionMapScreenState();
}

class _CompetitionMapScreenState extends State<CompetitionMapScreen> {
  // GoogleMapController 사용
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  List<Competition> _competitions = [];
  bool _isLoading = false;

  // 검색 조건
  String _selectedCategory = kSportCategories.first;
  // 1단계 시/도
  String _selectedProvince = kProvinces.first;
  // 2단계 시/군/구
  String _selectedCityCounty = '전체 시/군/구';
  DateTime? _selectedDate;

  // 백엔드에서 제공하는 사용자 위치 (예시)
  LatLng _userCurrentLocation = kInitialCameraPosition;

  @override
  void initState() {
    super.initState();
    // _selectedCityCounty 초기값을 _selectedProvince의 리스트에서 가져와 불일치 방지
    _selectedCityCounty = kCityCountyMap[_selectedProvince]!.first;
    _determinePosition();
    _fetchCompetitions(isInitial: true);
  }

  // ✅ 현재 위치를 가져오는 함수
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('위치 서비스가 비활성화되어 있습니다.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('위치 권한이 거부되었습니다.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 권한을 허용해주세요.');
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _userCurrentLocation = LatLng(position.latitude, position.longitude);
      });
      _moveCameraToCurrentUserLocation();
    } catch (e) {
      _showSnackBar('현재 위치를 가져오는 데 실패했습니다: $e');
    }
  }

  // ✅ 현재 위치로 카메라를 이동하는 함수
  void _moveCameraToCurrentUserLocation() {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_userCurrentLocation, 14),
      );
    }
  }


  // 대회 데이터 로드 및 지도에 표시
  Future<void> _fetchCompetitions({bool isInitial = false}) async {
    setState(() {
      _isLoading = true;
    });

    final Map<String, dynamic> queryParams = {};

    if (!isInitial) {
      if (_selectedCategory != '전체 종목') {
        queryParams['sport_category'] = _selectedCategory;
      }

      // 지역 필터링 로직: 백엔드에 시/도와 시/군/구를 분리하여 전송
      if (_selectedProvince != '전체 지역') {
        queryParams['province'] = _selectedProvince;

        if (_selectedCityCounty != '전체 시/군/구') {
          queryParams['city_county'] = _selectedCityCounty;
        }
      }

      if (_selectedDate != null) {
        queryParams['available_from'] = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      }
    }

    String queryString = Uri(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString()))).query;
    final Uri uri = Uri.parse('$kBaseUrl/competitions?$queryString');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        if (data['success'] == true && data['data'] != null) {
          final List<Competition> newCompetitions = (data['data'] as List)
              .map((json) => Competition.fromJson(json))
              .where((comp) => comp.latLng.latitude != 0.0 || comp.latLng.longitude != 0.0) // 좌표가 0.0, 0.0 인 데이터 제외
              .toList();

          final int resultCount = newCompetitions.length; // 💡 검색된 실제 개수

          setState(() {
            _competitions = newCompetitions;
            _updateMapMarkers();
            _adjustMapBounds();
          });

          // 💡 [수정] 검색 결과 개수를 표시하는 스낵바 추가
          if (resultCount > 0) {
            _showSnackBar("✅ 검색 결과: ${resultCount}개의 대회가 발견되었습니다.");
          } else {
            _showSnackBar("검색 조건에 맞는 대회가 없습니다.");
          }

        } else {
          setState(() {
            _competitions = [];
            _markers = {};
            _adjustMapBounds();
          });
          // 성공은 했지만 데이터가 없거나 메시지 반환 시 (Null 안전성 강화 필요)
          _showSnackBar(data['message']?.toString() ?? "검색 조건에 맞는 대회가 없습니다.");
        }
      } else {
        // HTTP 상태 코드 오류 시
        _showSnackBar("API 호출 실패: HTTP ${response.statusCode}");
      }
    } catch (e) {
      // 💡 네트워크 오류 시 발생한 예외 객체를 안전하게 문자열로 변환하여 출력
      _showSnackBar("네트워크 오류: API에 연결할 수 없습니다. ${e.toString()}");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 마커 업데이트 로직 (Google Maps용)
  void _updateMapMarkers() {
    final Set<Marker> newMarkers = {};
    for (var comp in _competitions) {
      final marker = Marker(
        markerId: MarkerId(comp.id),
        position: comp.latLng,
        infoWindow: InfoWindow(
          title: comp.name,
          snippet: comp.location,
          onTap: () => _showCompetitionDetails(comp),
        ),
      );
      newMarkers.add(marker);
    }
    setState(() {
      _markers = newMarkers;
    });
  }

  // 검색 결과에 따라 지도 비율 변경 로직 (Google Maps용)
  void _adjustMapBounds() {
    if (_mapController == null || _competitions.isEmpty) {
      return;
    }

    if (_competitions.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
        _competitions.first.latLng,
        14,
      ));
      return;
    }

    // 결과가 여러 개일 경우, 모든 마커를 포함하는 경계 계산
    double minLat = _competitions.map((c) => c.latLng.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = _competitions.map((c) => c.latLng.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = _competitions.map((c) => c.latLng.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = _competitions.map((c) => c.latLng.longitude).reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // 경계에 맞게 지도 뷰 이동 (패딩 100)
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      bounds,
      100,
    ));
  }

  // 상세 정보 표시 모달
  void _showCompetitionDetails(Competition competition) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(competition.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('종목: ${competition.category}'),
                Text('지역: ${competition.location}'),
                Text('시작일: ${competition.startDate}'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () => _launchURL(competition.registerUrl),
                      icon: const Icon(Icons.app_registration),
                      label: const Text('등록하기'),
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

  // URL 연결 및 스낵바 로직은 유지
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnackBar('등록 URL을 열 수 없습니다: $url');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // 기간 선택 DatePicker 로직은 유지
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      helpText: '참가 가능 시작 날짜 선택',
      cancelText: '취소',
      confirmText: '확인',
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // 드롭다운 위젯 빌더
  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
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
        title: const Text('🏆 체육 대회 검색'),
      ),
      body: Stack(
        children: [

          // 1. GoogleMap 위젯
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: _userCurrentLocation,
              zoom: 10,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              _moveCameraToCurrentUserLocation();
            },
            markers: _markers,
            myLocationEnabled: true,
            padding: const EdgeInsets.only(top: 280),
          ),


          // 로딩 인디케이터
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),

          // 2. 검색 조건 UI (상단)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
              ),
              child: Column(
                children: [
                  // 1. 종목 & 기간 선택 Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // 종목 드롭다운
                      Expanded(
                        child: _buildDropdown(
                          '종목',
                          _selectedCategory,
                          kSportCategories,
                              (newValue) {
                            setState(() {
                              _selectedCategory = newValue!;
                            });
                          },
                        ),
                      ),
                      // 기간 선택 버튼
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 8.0),
                              child: Text('기간', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                            TextButton.icon(
                              onPressed: () => _selectDate(context),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                _selectedDate == null
                                    ? '날짜 선택'
                                    : DateFormat('yy/MM/dd').format(_selectedDate!),
                                style: const TextStyle(fontSize: 14),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 2. 지역 드롭다운 Row
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // 1단계: 시/도 선택 (Expanded 적용)
                      Expanded(
                        child: _buildDropdown(
                          '시/도',
                          _selectedProvince,
                          kProvinces,
                              (newValue) {
                            setState(() {
                              _selectedProvince = newValue!;
                              // 시/도가 바뀌면 시/군/구 목록을 해당 시/도로 초기화
                              _selectedCityCounty = kCityCountyMap[newValue]!.first;
                            });
                          },
                        ),
                      ),
                      // 2단계: 시/군/구 선택 (Expanded 적용)
                      Expanded(
                        child: _buildDropdown(
                          '시/군/구',
                          _selectedCityCounty,
                          // 현재 선택된 시/도에 해당하는 시/군/구 목록을 사용
                          kCityCountyMap[_selectedProvince]!,
                              (newValue) {
                            setState(() {
                              _selectedCityCounty = newValue!;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  // 3. 검색 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _fetchCompetitions(isInitial: false),
                      icon: const Icon(Icons.search),
                      label: const Text('대회 검색', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. 하단 AI 추천 / 지도자 매칭 버튼 영역
          Positioned(
            bottom: 20,
            left: 10,
            right: 10,
            child: Row(
              children: [
                // AI 추천 버튼
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        _showSnackBar('AI 추천 기능 준비 중입니다.');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      child: const Text('AI 추천', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),

                // 지도자 매칭 버튼
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        _showSnackBar('지도자 매칭 페이지로 이동합니다.');
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.grey),
                        ),
                      ),
                      child: const Text('지도자 매칭', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}