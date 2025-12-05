# ⚽ Competition & Sports Community App

> 대회 검색 · 공공 체육 정보 · 팀원 모집 · 맞춤 추천을 한번에!  
> 지도 기반 스포츠/대회 정보 플랫폼

---

## 🔗 서비스 URL

- 전체 서비스 (Google Drive 배포 링크):  
  [https://drive.google.com/drive/u/0/folders/1QceFWy2bRJohzvu3x_Da9BAnj1nDf36f](https://drive.google.com/drive/u/0/folders/1QceFWy2bRJohzvu3x_Da9BAnj1nDf36f)  
- 코드 저장소 (GitHub):  
  [https://github.com/ImCuriosity/competition_recommendation.git](https://github.com/ImCuriosity/competition_recommendation.git)

---

## 📖 서비스 개요

이 앱은 사용자가 **주변 스포츠 대회 및 공공 체육 프로그램, 동호회 정보**를 찾고,  
자신에게 맞는 대회를 추천받고,  
또한 **팀원 모집 게시판**을 통해 직접 팀원을 모집하거나 참여를 신청할 수 있는  
모든 스포츠 커뮤니티 활동을 통합 제공하는 플랫포옴입니다.

주요 기능:
- 지도 기반 대회 / 체육 정보 탐색  
- 필터링(종목, 지역, 날짜 등)  
- 대회 / 공공 프로그램 / 동호회 상세 정보 조회  
- 팀원 모집 게시판 (CRUD + 댓글 + 모집 상태 관리)  
- 사용자 프로필 & 관심 종목 / 실력 관리  
- AI 기반 맞춤 대회 추천 API  

---

## ✅ 주요 기능

### 🎯 대회 정보 통합 검색 (지도 기반)

- :contentReference[oaicite:0]{index=0} 지도 UI를 사용하여 현재 위치 또는 선택한 지역 주변의 스포츠 대회 탐색  
- ‘종목’, ‘지역(시/도, 시/군/구)’, ‘개최일’ 등 다양한 조건으로 필터링  
- 대회 이름, 장소, 날짜, 접수 기간, 홈페이지 URL 등의 상세 정보 제공  

### 🏃‍♂️ 공공 체육 정보 제공

- **공공 프로그램**: 각 지역에서 운영하는 공공 체육 강습 및 프로그램 정보 제공  
- **체육 동호회**: 지역별 / 종목별 동호회 활동 정보 탐색  

### 📢 팀원 모집 게시판

- CRUD 기능: 사용자가 직접 모집 글 작성, 수정, 삭제  
- 댓글 기능: 신청 및 문의를 위해 게시글에 댓글 달기  
- 모집 상태 관리: ‘모집 중’, ‘모집 완료’ 등 상태 표시로 실시간 모집 현황 공유  

### 👤 사용자 맞춤형 기능

- 이메일 기반 인증 / 회원 시스템 (로그인, 회원가입, 로그아웃) — :contentReference[oaicite:1]{index=1} 사용  
- 사용자 프로필 관리 — 관심 종목, 실력 수준 등  
- 서버 사이드 AI 추천 시스템: 사용자의 프로필 (관심 종목, 실력, 위치 등)에 기반한 대회 추천 API  

---

## 🛠 기술 스택

| 영역        | 기술 / 라이브러리 |
|-------------|------------------|
| 프런트엔드 | :contentReference[oaicite:2]{index=2} (Dart) — UI/UX, 전체 앱 로직 담당 |
| 주요 라이브러리 | `google_maps_flutter`, `geolocator`, `http`, `supabase_flutter` 등 |
| 백엔드      | :contentReference[oaicite:3]{index=3} (Python) — REST API 서버 역할 |
| 데이터베이스 & 인증 | Supabase / PostgreSQL + JWT 기반 인증 시스템 |

---

## 🚀 설치 및 실행 — 로컬 개발 환경

### 🧑‍💻 준비 사항

- Flutter 3.x, Dart SDK (권장)  
- Python 3.9+  
- Supabase 프로젝트 (PostgreSQL + 인증)  
- `.env` 또는 환경 변수 파일에 다음 항목 설정:  
 ~~~
 root/server/.env
 SUPABASE_URL=<your supabase url>
 SUPABASE_ANON_KEY=<your supabase anon or service key>
 SUPABSE_JWT_SECRET=<your jwt secret or supabase jwt secret>

 root/.env
 SUPABASE_URL=<your supabase url>
 SUPABASE_ANON_KEY=<your supabase anon or service key>
 GOOGLE_MAPS_API_KEY=<your google map api key>
  
 root/android/gradle/local.properties
 google.mapsApiKey=<your google map api key>
  ~~~


### 📦 프로젝트 클론
  ~~~
  git clone https://github.com/ImCuriosity/competition_recommendation.git
  cd competition_recommendation
  ~~~

### 🔧 백엔드 서버 실행
~~~
  cd backend               # backend 디렉토리 경로 예시
  python -m venv venv
  source venv/bin/activate  # Windows: venv\Scripts\activate
  pip install -r requirements.txt
  
  uvicorn main:app --reload --host 0.0.0.0 --port 8000
~~~

### 📱 프런트엔드 앱 실행 (Flutter)
~~~
  cd mobile_app  # Flutter 프로젝트 경로 예시
  flutter pub get
  flutter run     # 혹은 flutter run -d <device id>
~~~

### 📄 API 문서 & 스펙
  기본 REST API 엔드포인트 (대회 조회, 공공 프로그램 조회, 동호회 조회, 게시판 CRUD, 댓글, 인증, 추천 API 등)
  (추후 추가 예정) OpenAPI / Swagger 문서 제공 — http://localhost:8000/docs (기본 설정 사용 시)

### 🤝 기여 가이드
  1. 저장소를 Fork 하세요.
  2. 새로운 브랜치(feature/issue-번호, fix/…)를 만드세요.
  3. 변경 사항 커밋 및 Push
  4. Pull Request 생성

### 📝 라이선스
  - 본 프로젝트의 라이선스는 별도 명시가 없는 경우 MIT 라이선스를 따릅니다.
  - 자세한 내용은 LICENSE 파일을 참고하세요.
  - 새로운 브랜치(feature/issue-번호, fix/…)를 만드세요.

### 🙏 기타 참고 사항
  - 지도 기반 UI를 사용할 때 Google Maps API Key 설정이 필요합니다.
  - Supabase 설정 후, 초기 데이터 삽입 스크립트 또는 마이그레이션 스크립트를 제공할 예정입니다.
  (백엔드) AI 추천 로직은 별도의 모듈로 구성되어 있으며, 추후 학습 데이터, 추천 튜닝 방법 등에 대한 문서를 추가할 계획입니다.

### 📬 문의 / 연락
  - 궁금한 점이나 제안하고 싶은 기능이 있다면 언제든지 Issue 또는 Pull Request 남겨주세요.
  즐거운 개발 되세요! 🚀
