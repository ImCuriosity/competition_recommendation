from fastapi import FastAPI, Query, HTTPException
from dotenv import load_dotenv
import os
from typing import Optional, Dict, Any, List
import json
from enum import Enum
from supabase import create_client, Client
from supabase.lib.client_options import ClientOptions
from shapely import wkb
from binascii import unhexlify
import asyncio
import datetime # datetime 모듈 유지

# ====================================================
# 상수 및 초기 설정
# ====================================================

# Supabase REST API의 기본 최대 제한(LIMIT)은 1000개입니다. 
SUPABASE_PAGE_SIZE = 1000 

# 허용되는 스포츠 종목을 Enum으로 정의
class SportCategory(str, Enum):
    배드민턴 = "배드민턴"
    마라톤 = "마라톤"
    보디빌딩 = "보디빌딩"
    테니스 = "테니스"

# 환경변수 로드
load_dotenv()

# FastAPI 앱 생성
app = FastAPI(
    title="Sports Competition API (AI Recommendation)",
    description="운동 대회 검색 및 AI 추천 API (Sysdate 고정 적용)",
    version="1.1.2" # 버전 업데이트
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
    """
    Supabase의 1000개 제한을 우회하기 위해 페이지네이션을 사용하여 모든 데이터를 가져옵니다.
    """
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
    
    # 1. 날짜 필터링
    # available_from이 None이 아닌 경우에만 필터링을 수행합니다.
    if available_from and item.get('event_period'):
        try:
            # event_period가 "[YYYY-MM-DD, YYYY-MM-DD]" 형태라고 가정
            period_str = item['event_period']
            start_date_str = period_str.split(',')[0].replace('[', '').strip()
            
            # 대회 시작일이 기준일(available_from)보다 이전이면 필터링
            if start_date_str < available_from:
                return None 
        except Exception:
            pass # 날짜 파싱 오류 발생 시 필터링하지 않고 다음 단계로 진행

    # 2. WKB 파싱 및 위도/경도 추출
    if item.get('location'):
        try:
            geom = wkb.loads(unhexlify(item['location']))
            item['longitude'] = geom.x
            item['latitude'] = geom.y
        except Exception:
            item['longitude'] = None
            item['latitude'] = None
            
    else:
        item['longitude'] = None
        item['latitude'] = None

    # 3. 'start_date' 필드 정리 및 'location' 제거
    if item.get('event_period'):
        item['start_date'] = item.pop('event_period', '').split(',')[0].replace('[', '').strip()
    else:
        item['start_date'] = None
        
    item.pop('location', None) # WKB 바이너리 제거
    
    return item

# ====================================================
# AI 추천 로직 유틸리티 함수 (중략 - 로직 변경 없음)
# ====================================================

# 1. 등급(Grade)을 사용자 실력(Skill: 상/중/하)에 매핑하는 기준 정의
GRADE_SKILL_MAP: Dict[SportCategory, Dict[str, List[str]]] = {
    SportCategory.테니스: {
        "상": ["개나리부", "국화부", "통합부", "지도자부", "마스터스부", "챌린저부"],
        "중": ["오픈부", "신인부", "썸머부", "무궁화부", "랭킹부", "남자퓨처스부", "여자퓨처스부"],
        "하": ["입문부", "테린이", "초심부", "루키부"],
        "무관": ["무관", "", "전부"],
    },
    SportCategory.보디빌딩: {
        "상": ["프로", "마스터", "시니어", "엘리트", "오버롤"],
        "중": ["일반부", "주니어", "학생부", "미들", "시니어"],
        "하": ["비기너", "초심", "루키", "노비스"],
        "무관": ["무관", ""],
    },
    SportCategory.배드민턴: {
        "상": ["S급", "A급", "B급", "S조", "A조", "B조"],
        "중": ["C급", "D급", "C조", "D조"],
        "하": ["E급", "초심", "F급", "E조"],
        "무관": ["무관", ""],
    },
    SportCategory.마라톤: {
        "상": ["풀코스", "42.195km", "하프코스", "21km", "Half"],
        "중": ["10km", "하프", "12km", "15km", "10k"],
        "하": ["5km", "건강 달리기", "워킹", "3km", "5k"],
        "무관": ["무관", ""],
    },
}

def get_skill_level_from_grade(sport: SportCategory, grade: Optional[str]) -> Optional[str]:
    """대회 등급(grade)을 사용자 실력 레벨(상/중/하)로 변환"""
    grade = grade.strip().replace(' ', '') if grade else ""
    if not grade:
        return "무관"

    mapping = GRADE_SKILL_MAP.get(sport, {})
    for skill_level, grades in mapping.items():
        if grade in grades:
            return skill_level
    
    return None

def age_matches(user_age: int, competition_age_str: Optional[str]) -> bool:
    """사용자 나이가 대회 참가 연령 기준에 맞는지 확인 (한국식 나이 기준)"""
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
            
    except ValueError:
        return False
    except Exception:
        return False


def gender_matches(user_gender: Optional[str], competition_gender: Optional[str]) -> bool:
    """사용자 성별이 대회 성별 제한에 맞는지 확인"""
    if not competition_gender or competition_gender == "무관":
        return True

    user_gender = user_gender.strip() if user_gender else None
    comp_gender = competition_gender.strip()
    
    if not user_gender:
        return False
    
    if comp_gender == "남" and user_gender == "남":
        return True
    
    if comp_gender == "여" and user_gender == "여":
        return True
        
    return False

# ====================================================
# DB 인터페이스 (Profiles 및 Interesting_Sports)
# ====================================================

async def get_user_profile(user_id: str) -> Dict[str, Any]:
    """profiles 및 interesting_sports 테이블에서 사용자 정보를 가져옵니다."""
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")
        
    profile_res = supabase.table("profiles").select("age, gender").eq("id", user_id).execute()
    
    if not profile_res.data:
        raise HTTPException(status_code=404, detail="사용자 프로필(profiles 테이블)을 찾을 수 없습니다.")
        
    user_profile = profile_res.data[0]
    
    sports_res = supabase.table("interesting_sports").select("sport_name, skill").eq("user_id", user_id).execute()
    
    user_profile['interesting_sports'] = sports_res.data
    
    return user_profile


def is_competition_recommended(user_profile: Dict[str, Any], competition: Dict[str, Any]) -> bool:
    """
    4가지 기준(종목, 성별, 나이, 실력)을 모두 만족하는지 확인합니다.
    """
    
    # 1. 종목 매칭
    comp_sport = competition.get("sport_category")
    user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
    
    if comp_sport not in user_sports_map:
        return False

    # 2. 성별 매칭
    if not gender_matches(user_profile.get("gender"), competition.get("gender")):
        return False

    # 3. 나이 매칭
    user_age = user_profile.get("age")
    if not user_age or not age_matches(user_age, competition.get("age")):
        return False
        
    # 4. 실력/등급 매칭
    user_skill = user_sports_map.get(comp_sport)
    comp_grade = competition.get("grade")
    
    try:
        comp_skill_level = get_skill_level_from_grade(SportCategory(comp_sport), comp_grade)
    except ValueError:
        return False
        
    if comp_skill_level is None:
        return False
    
    if comp_skill_level == "무관":
        return True
    
    skill_ranking = {"상": 3, "중": 2, "하": 1}
    user_rank = skill_ranking.get(user_skill, 0)
    comp_rank = skill_ranking.get(comp_skill_level, 0)
    
    # 상위 실력자가 하위 등급 커버 허용
    if user_rank >= comp_rank and comp_rank > 0:
        return True
        
    return False

# ====================================================
# 엔드포인트
# ====================================================

@app.get("/")
def read_root():
    """헬스체크 엔드포인트"""
    return {
        "message": "Sports Competition API is running!",
        "version": "1.1.2",
        "supabase_connected": supabase is not None
    }


@app.get("/test/all-data")
async def test_all_data():
    """
    테스트용: 모든 데이터 확인 엔드포인트 (페이지네이션 적용)
    """
    if not supabase:
        raise HTTPException(
            status_code=503,
            detail={"success": False, "message": "Supabase가 연결되지 않았습니다."}
        )
    
    try:
        base_query = supabase.table("competitions").select("*")
        all_data = await fetch_all_competitions_paginated(base_query)
        total_count_fetched = len(all_data)
        
        print(f"📊 전체 대회 데이터: {total_count_fetched}개 (페이지네이션 적용)")
        
        return {
            "success": True,
            "total_count_fetched": total_count_fetched,
            "message": f"페이지네이션을 통해 총 {total_count_fetched}개의 데이터를 가져왔습니다.",
            "data": all_data
        }
        
    except Exception as e:
        print(f"\n❌ 에러: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "전체 데이터 조회 중 오류가 발생했습니다."}
        )


@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(None, description="운동 종목"),
    province: Optional[str] = Query(None, description="시/도 이름"),
    city_county: Optional[str] = Query(None, description="시/군/구 이름"),
    available_from: Optional[str] = Query(None, description="참가 가능 시작 날짜 (YYYY-MM-DD)")
):
    """
    사용자가 선택한 조건에 맞는 대회 검색 (종목, 지역, 기간) - 페이지네이션 적용
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
        print(f"❌ 에러: {str(e)}\n")
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "대회 검색 중 오류가 발생했습니다."}
        )


@app.get("/recommend/competitions", response_model=Dict[str, Any])
async def recommend_competitions(
    user_id: str = Query(..., description="추천받을 사용자의 ID", examples=["user_1"])
):
    """
    [AI 추천 버튼] 클릭 시 호출: 사용자의 4가지 기준(실력, 나이, 성별, 종목)을 바탕으로 오늘 이후에 시작하는 대회를 추천합니다.
    """
    # ★★★ 수정 사항: available_from을 함수 내부에서 시스템 날짜로 고정 ★★★
    available_from: str = datetime.date.today().isoformat()
    print(f"📌 추천 기준 날짜 (available_from): {available_from}")
    
    if not supabase:
        raise HTTPException(
            status_code=503, 
            detail={"success": False, "message": "Supabase가 연결되지 않았습니다."}
        )
        
    # 1. 사용자 정보 가져오기
    try:
        user_profile = await get_user_profile(user_id)
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "message": "사용자 정보를 가져오는 중 오류가 발생했습니다."})

    # 2. 모든 대회 데이터 가져오기 (페이지네이션 적용)
    try:
        base_query = supabase.table("competitions").select("*")
        all_competitions = await fetch_all_competitions_paginated(base_query)
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "message": "대회 데이터를 가져오는 중 오류가 발생했습니다."})

    # 3. 추천 로직 적용
    recommended_competitions: List[Dict[str, Any]] = []
    
    for competition in all_competitions:
        # 1차 처리: WKB 파싱 및 날짜 필터링 (고정된 available_from 기준)
        processed_item = process_competition_data(competition.copy(), available_from)
        
        if not processed_item:
            continue
            
        # 2차 처리: 4가지 AI 추천 기준 적용
        if is_competition_recommended(user_profile, processed_item):
            recommended_competitions.append(processed_item)
    
    print(f"✅ AI 추천 결과: 총 {len(recommended_competitions)}개")
    
    return {
        "success": True,
        "user_profile_summary": {
            "age": user_profile.get("age"),
            "gender": user_profile.get("gender"),
            "sports": user_profile.get("interesting_sports"),
        },
        "count": len(recommended_competitions),
        "message": f"사용자 ID {user_id}에게 총 {len(recommended_competitions)}개의 적합한 대회를 추천했습니다. (기준일: {available_from})",
        "data": recommended_competitions
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
        "api_version": "1.1.2"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)