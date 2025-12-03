from fastapi import FastAPI, Query, HTTPException
from dotenv import load_dotenv
import os
from typing import Optional, Dict, Any, List, Tuple
from enum import Enum
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions
from shapely import wkb
from binascii import unhexlify
import datetime
import math
import uuid

# ====================================================
# 상수 및 초기 설정
# ====================================================

SUPABASE_PAGE_SIZE = 1000 
EARTH_RADIUS_KM = 6371.0 # 지구 반지름 (킬로미터)

# 유사도 계산을 위한 상수
MAX_DIST_KM = 500.0 # 위치 유사도 정규화를 위한 최대 거리
SKILL_WEIGHT = 0.6 # 실력 유사도 가중치
LOCATION_WEIGHT = 0.4 # 위치 유사도 가중치

# 실력 랭크 매핑 (유사도 계산용)
SKILL_RANK = {"상": 3, "중": 2, "하": 1, "무관": 0}

# 허용되는 스포츠 종목을 Enum으로 정의
class SportCategory(str, Enum):
    배드민턴 = "배드민턴"
    마라톤 = "마라톤"
    보디빌딩 = "보디빌딩"
    테니스 = "테니스"

# ★★★ 최종 업데이트된 GRADE_SKILL_MAP (모든 4개 종목 반영) ★★★
GRADE_SKILL_MAP: Dict[SportCategory, Dict[str, List[str]]] = {
    SportCategory.테니스: {
        "상": [
            "챌린저부", "마스터스부", "지도자부", "개나리부", "국화부", 
            "통합부", "마스터스", "챌린저"
        ],
        "중": [
            "전국신인부", "남자오픈부", "여자퓨처스부", "남자퓨처스부", "세미오픈부", 
            "베테랑부", "오픈부", "신인부", "썸머부", "무궁화부", "랭킹부", "퓨처스부"
        ],
        "하": [
            "남자테린이부", "여자테린이부", "지역 신인부", "입문부", "테린이", 
            "초심부", "루키부", "신인"
        ],
        "무관": ["무관", "", "전부"],
    },
    SportCategory.보디빌딩: {
        "상": ["마스터즈", "시니어", "오픈", "프로", "엘리트", "오버롤", "마스터"],
        "중": ["주니어", "미들", "일반부", "학생부"],
        "하": ["루키", "노비스", "비기너", "초심"],
        "무관": ["무관", ""],
    },
    SportCategory.배드민턴: {
        "상": ["S급", "A급", "B급", "S조", "A조", "B조", "자강"],
        "중": ["C급", "D급", "C조", "D조"],
        "하": ["E급", "초심", "왕초", "신인", "F급", "E조"],
        "무관": ["무관", ""],
    },
    SportCategory.마라톤: {
        "상": [
            "풀", "하프", "42.195km", "21.0975km", "100km", "50km", "48km", "40km", 
            "35km", "32km", "32.195km", "25km", "16km", "15km", "Full", "Half", "마니아"
        ],
        "중": [
            "13km", "12km", "11.19km", "10km", "7.5km", "7km", "10k"
        ],
        "하": [
            "5km", "3km", "5km 걷기", "7인1조 단체전", "5k", "3k", "걷기"
        ],
        "무관": ["무관", "", "전부"],
    },
}
# ★★★ 최종 등급 업데이트 반영 끝 ★★★

# 환경변수 로드
load_dotenv()

# FastAPI 앱 생성
app = FastAPI(
    title="Sports Competition API (Similarity Recommendation)",
    description="운동 대회 검색 및 임베딩/유사도 기반 AI 추천 API",
    version="2.0.4"
)

# Supabase 클라이언트 초기화 (조건부)
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")
supabase: Optional[Client] = None

if supabase_url and supabase_key and supabase_url != "your-supabase-url":
    try:
        supabase = create_client(supabase_url, supabase_key)
        print("✅ Supabase 연결 성공!")
    except Exception as e:
        print(f"⚠️ Supabase 연결 실패: {e}")
else:
    print("⚠️ Supabase 설정이 없습니다. 나중에 .env 파일을 설정하세요.")

# ====================================================
# 핵심 유틸리티 함수: 페이지네이션 및 데이터 처리
# ====================================================

async def fetch_all_competitions_paginated(base_query: Any) -> List[Dict[str, Any]]:
    """페이지네이션을 사용하여 모든 데이터를 가져옵니다."""
    all_data = []
    offset = 0
    
    while True:
        try:
            response = base_query.range(offset, offset + SUPABASE_PAGE_SIZE - 1).execute()
            current_data = response.data
            all_data.extend(current_data)
            
            if len(current_data) < SUPABASE_PAGE_SIZE:
                break
            
            offset += SUPABASE_PAGE_SIZE
            
        except Exception as e:
            print(f"❌ 페이지네이션 중 오류 발생 (Offset: {offset}): {e}")
            break 

    return all_data


def process_competition_data(item: Dict[str, Any], available_from: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """WKB 파싱 및 날짜 필터링/처리 로직"""
    
    # 1. 날짜 필터링 (선행 필터)
    if available_from and item.get('event_period'):
        try:
            period_str = item['event_period']
            start_date_str = period_str.split(',')[0].replace('[', '').strip()
            
            if start_date_str < available_from:
                return None 
        except Exception:
            pass

    # 2. WKB 파싱 및 위도/경도 추출
    if item.get('location'):
        try:
            # WKB 16진수 문자열 파싱
            geom = wkb.loads(unhexlify(item['location']))
            item['longitude'] = geom.x
            item['latitude'] = geom.y
        except Exception:
            item['longitude'] = None
            item['latitude'] = None
            
    else:
        item['longitude'] = None
        item['latitude'] = None

    # 3. 데이터 정리
    if item.get('event_period'):
        item['start_date'] = item.pop('event_period', '').split(',')[0].replace('[', '').strip()
    else:
        item['start_date'] = None
        
    item.pop('location', None)
    
    return item

# ====================================================
# AI 추천: 선행 필터링 유틸리티 함수
# ====================================================

def get_skill_level_from_grade(sport: str, grade: Optional[str]) -> str:
    """대회 등급(grade)을 사용자 실력 레벨(상/중/하/무관)로 변환"""
    grade = grade.strip().replace(' ', '') if grade else ""
    if not grade:
        return "무관"

    try:
        sport_enum = SportCategory(sport)
    except ValueError:
        return "무관"

    mapping = GRADE_SKILL_MAP.get(sport_enum, {})
    # 등급 매핑 시, 대소문자 구분 없이, 그리고 공백 없이 비교하도록 처리
    normalized_grade = grade.upper().replace(' ', '')
    
    for skill_level, grades in mapping.items():
        if normalized_grade in [g.upper().replace(' ', '') for g in grades]:
            return skill_level
    
    return "무관"


def age_matches(user_age: int, competition_age_str: Optional[str]) -> bool:
    """사용자 나이가 대회 참가 연령 기준에 맞는지 확인 (선행 필터)"""
    if not competition_age_str or competition_age_str == "무관":
        return True

    try:
        age_str = competition_age_str.replace(' ', '').replace('세', '')
        
        if '~' not in age_str:
            return user_age == int(age_str)
        
        elif age_str.startswith('~'):
            max_age = int(age_str[1:])
            return user_age < max_age
        
        elif age_str.endswith('~'):
            min_age = int(age_str[:-1])
            return user_age >= min_age
        
        else:
            min_str, max_str = age_str.split('~')
            min_age = int(min_str)
            max_age = int(max_str)
            return min_age <= user_age < max_age
            
    except Exception:
        return False


def gender_matches(user_gender: Optional[str], competition_gender: Optional[str]) -> bool:
    """사용자 성별이 대회 성별 제한에 맞는지 확인 (선행 필터)"""
    if not competition_gender or competition_gender == "무관":
        return True

    user_gender = user_gender.strip() if user_gender else None
    comp_gender = competition_gender.strip()
    
    if not user_gender:
        return False
    
    # 성별이 일치하는 경우만 허용
    if comp_gender == user_gender:
        return True
        
    return False

# ====================================================
# AI 추천: 유사도 계산 유틸리티 함수
# ====================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """두 위도/경도 좌표 간의 거리를 킬로미터(km)로 계산합니다 (Haversine 공식)."""
    
    # 각도를 라디안으로 변환
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    # Haversine 공식 적용
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    distance_km = EARTH_RADIUS_KM * c
    return distance_km

def calculate_location_similarity(user_lat: float, user_lon: float, comp_lat: float, comp_lon: float) -> float:
    """위치 유사도 점수를 계산합니다 (0 ~ 1.0). 거리가 가까울수록 1에 가깝습니다."""
    
    distance = haversine_distance(user_lat, user_lon, comp_lat, comp_lon)
    
    # 500km를 최대 기준으로 정규화 (0~1)
    normalized_distance = min(distance, MAX_DIST_KM) / MAX_DIST_KM
    
    # 유사도 점수 (거리가 짧을수록 점수가 높음)
    similarity_score = 1.0 - normalized_distance
    
    return similarity_score

def calculate_skill_similarity(user_skill: str, comp_grade: str, comp_sport: str) -> float:
    """실력 유사도 점수를 계산합니다 (0 ~ 1.0)."""
    
    # 1. 대회 등급을 실력 레벨로 변환
    comp_skill = get_skill_level_from_grade(comp_sport, comp_grade)
    
    # 2. 랭크 점수로 변환
    user_rank = SKILL_RANK.get(user_skill, 0)
    comp_rank = SKILL_RANK.get(comp_skill, 0)
    
    # 3. 랭크 차이 계산
    rank_difference = abs(user_rank - comp_rank)
    
    # 4. 유사도 점수 계산 및 정규화 (최대 차이 3으로 나눔)
    similarity_score = 1.0 - (rank_difference / 3.0) 
    
    return max(0.0, similarity_score)


def calculate_recommendation_score(user_profile: Dict[str, Any], competition: Dict[str, Any]) -> Tuple[float, Optional[float], Optional[float]]:
    """
    선행 필터링(종목, 성별, 나이) 후, 실력 및 위치 유사도를 계산하여 최종 점수를 반환합니다.
    (Score, Skill_Score, Location_Score)
    """
    
    # 0. 필수 데이터 확인 및 선행 필터 적용에 필요한 변수 추출
    comp_sport = competition.get("sport_category")
    user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
    
    user_age = user_profile.get("age")
    user_gender = user_profile.get("gender")
    
    comp_age = competition.get("age")
    comp_gender = competition.get("gender")
    
    user_lat = user_profile.get("user_latitude")
    user_lon = user_profile.get("user_longitude")
    comp_lat = competition.get("latitude")
    comp_lon = competition.get("longitude")
    
    # 1. 선행 필터링 (하나라도 불일치하면 바로 0점 반환)
    # 1-1. 종목 필터 (Exact Match)
    if comp_sport not in user_sports_map:
        return 0.0, None, None
        
    # 1-2. 성별 필터 (Exact Match)
    if not gender_matches(user_gender, comp_gender):
        return 0.0, None, None
        
    # 1-3. 나이 필터 (Rule-based Range Check)
    if not user_age or not age_matches(user_age, comp_age):
        return 0.0, None, None

    # 2. 유사도 계산
    
    # 2-1. 실력 유사도 계산 (Skill Similarity)
    user_skill = user_sports_map.get(comp_sport, "무관")
    comp_grade = competition.get("grade")
    skill_score = calculate_skill_similarity(user_skill, comp_grade, comp_sport)
    
    # 2-2. 위치 유사도 계산 (Location Similarity)
    if user_lat is None or comp_lat is None:
        # 위치 정보가 없으면 중간값 (0.5)으로 처리
        location_score = 0.5 
    else:
        location_score = calculate_location_similarity(user_lat, user_lon, comp_lat, comp_lon)

    # 3. 종합 추천 점수 계산 (가중치 합산)
    total_score = (SKILL_WEIGHT * skill_score) + (LOCATION_WEIGHT * location_score)
    
    return total_score, skill_score, location_score

# ====================================================
# DB 인터페이스
# ====================================================

async def get_user_profile(user_id: str) -> Dict[str, Any]:
    """profiles 및 interesting_sports 테이블에서 사용자 정보를 가져옵니다 (위치 포함)."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")
        
    # 'location' 컬럼을 추가하여 가져옵니다.
    profile_res = supabase.table("profiles").select("age, gender, location").eq("id", user_id).execute()
    
    if not profile_res.data:
        raise HTTPException(status_code=404, detail="사용자 프로필(profiles 테이블)을 찾을 수 없습니다.")
        
    user_profile = profile_res.data[0]
    
    # 1. 사용자 위치(location) WKB 파싱 및 위도/경도 추출
    user_profile['user_latitude'] = None
    user_profile['user_longitude'] = None
    if user_profile.get('location'):
        try:
            # WKB 16진수 문자열 파싱
            geom = wkb.loads(unhexlify(user_profile['location']))
            user_profile['user_longitude'] = geom.x
            user_profile['user_latitude'] = geom.y
        except Exception as e:
            print(f"⚠️ 사용자 위치 WKB 파싱 오류: {e}")
            
    user_profile.pop('location', None) # WKB 바이너리 제거
    
    # 2. interesting_sports 테이블에서 관심 종목 및 실력 가져오기
    
    # =========================================================================
    # ★★★ UUID 타입 매칭을 위한 수정 부분 ★★★
    try:
        # 1. user_id 문자열을 UUID 객체로 변환
        user_uuid = uuid.UUID(user_id)
        # 2. 쿼리에 UUID 객체를 직접 전달하여 Supabase 클라이언트가 
        #    PostgreSQL UUID 타입과 정확히 비교하도록 유도
        sports_res = supabase.table("interesting_sports").select("sport_name, skill").eq("user_id", user_uuid).execute()
        
    except ValueError:
        # 만약 user_id가 유효한 UUID 형식이 아니라면 (예외 상황), 기존처럼 문자열로 쿼리
        print(f"⚠️ 경고: user_id '{user_id}'가 유효한 UUID 형식이 아니므로 문자열로 쿼리합니다.")
        sports_res = supabase.table("interesting_sports").select("sport_name, skill").eq("user_id", user_id).execute()
        
    # =========================================================================
    
    user_profile['interesting_sports'] = sports_res.data
    
    # 디버깅: 이제 데이터가 잘 나오는지 최종 확인
    print(f"DEBUG UUID FIX: interesting_sports 조회 결과: {sports_res.data}")
    
    return user_profile

# ====================================================
# 엔드포인트
# ====================================================

@app.get("/")
def read_root():
    """헬스체크 엔드포인트"""
    return {
        "message": "Sports Competition API is running!",
        "version": "2.0.4",
        "supabase_connected": supabase is not None
    }


@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(None, description="운동 종목"),
    province: Optional[str] = Query(None, description="시/도 이름"),
    city_county: Optional[str] = Query(None, description="시/군/구 이름"),
    available_from: Optional[str] = Query(None, description="참가 가능 시작 날짜 (YYYY-MM-DD)")
):
    """
    사용자가 선택한 조건에 맞는 대회 검색 (기존 규칙 기반 검색 유지)
    """
    if not supabase:
        raise HTTPException(status_code=503, detail={"success": False, "message": "Supabase가 연결되지 않았습니다."})
    
    query_sport_category = sport_category.value if sport_category else None
    
    try:
        base_query = supabase.table("competitions").select("*")
        
        if query_sport_category:
            base_query = base_query.eq("sport_category", query_sport_category)
        
        if province and province != '전체 지역':
            base_query = base_query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구':
                base_query = base_query.eq("location_county_district", city_county)
                
        all_fetched_data = await fetch_all_competitions_paginated(base_query)
        
        processed_data: List[Dict[str, Any]] = []
        for item in all_fetched_data:
            processed_item = process_competition_data(item, available_from)
            if processed_item:
                processed_data.append(processed_item)
        
        return {
            "success": True,
            "count": len(processed_data),
            "total_fetched": len(all_fetched_data),
            "data": processed_data
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "대회 검색 중 오류가 발생했습니다."}
        )

@app.get("/recommend/competitions", response_model=Dict[str, Any])
async def recommend_competitions(
    user_id: str = Query(..., description="추천받을 사용자의 ID", examples=["user_1"]),
    # 사용자로부터 입력받을 top_n 인자를 명확히 정의합니다.
    top_n: int = Query(3, description="반환할 상위 추천 대회 개수", ge=1) 
):
    """
    [AI 추천 버튼] 클릭 시 호출: 선행 필터 후 실력 및 위치 유사도를 기반으로 대회를 추천합니다.
    """
    available_from: str = datetime.date.today().isoformat()
    
    if not supabase:
        raise HTTPException(
            status_code=503, 
            detail={"success": False, "message": "Supabase가 연결되지 않았습니다."}
        )
        
    # 1. 사용자 정보 가져오기 (위도/경도 포함)
    try:
        user_profile = await get_user_profile(user_id)
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "message": f"사용자 정보를 가져오는 중 오류가 발생했습니다: {e}"})

    # 2. 모든 대회 데이터 가져오기
    try:
        base_query = supabase.table("competitions").select("*")
        all_competitions = await fetch_all_competitions_paginated(base_query)
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "message": "대회 데이터를 가져오는 중 오류가 발생했습니다."})

    # 3. 추천 로직 적용 및 스코어링
    scored_competitions: List[Dict[str, Any]] = []
    
    for competition in all_competitions:
        # 1차 처리: WKB 파싱 및 날짜 필터링
        processed_item = process_competition_data(competition.copy(), available_from)
        
        if not processed_item:
            continue
            
        # 2차 처리: 선행 필터 및 유사도 기반 종합 점수 계산
        total_score, skill_score, location_score = calculate_recommendation_score(
            user_profile, 
            processed_item
        )
        
        if total_score > 0.0:
            # 점수가 0보다 큰 경우에만 추천 목록에 추가
            processed_item['recommendation_score'] = round(total_score, 4)
            processed_item['skill_similarity'] = round(skill_score, 4) if skill_score is not None else 0.0
            processed_item['location_similarity'] = round(location_score, 4) if location_score is not None else 0.0
            scored_competitions.append(processed_item)

    # 4. 종합 점수가 높은 순서대로 정렬
    recommended_competitions = sorted(
        scored_competitions, 
        key=lambda x: x['recommendation_score'], 
        reverse=True
    )
    
    # 5. ★★★ top_n 개수만큼 슬라이싱하여 최종 결과 반환 ★★★
    # 이 부분이 사용자가 지정한 대회 개수를 반영하는 핵심 로직입니다.
    top_recommended_competitions = recommended_competitions[:top_n]
    
    print(f"✅ AI 추천 결과: 총 {len(recommended_competitions)}개 중 상위 {len(top_recommended_competitions)}개 반환")
    
    return {
        "success": True,
        "user_profile_summary": {
            "age": user_profile.get("age"),
            "gender": user_profile.get("gender"),
            "location": f"({user_profile.get('user_latitude', 'N/A')}, {user_profile.get('user_longitude', 'N/A')})",
            "sports": user_profile.get("interesting_sports"),
        },
        "count": len(top_recommended_competitions),
        "total_scored_count": len(recommended_competitions), # 총 스코어링된 개수 추가
        "message": f"유사도 기반으로 사용자 ID {user_id}에게 총 {len(top_recommended_competitions)}개의 적합한 대회를 추천했습니다. (기준일: {available_from}, 요청 개수: {top_n}개)",
        "data": top_recommended_competitions
    }


# ====================================================
# 서버 실행
# ====================================================

@app.get("/health")
def health_check():
    """서버 상태 확인"""
    return {
        "status": "healthy",
        "supabase_connected": supabase is not None,
        "api_version": "2.0.4"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)