from fastapi import FastAPI, Query, HTTPException, Body
from dotenv import load_dotenv
import os
from typing import Optional, Dict, Any, List, Tuple
from enum import Enum
from supabase import create_client, Client
from shapely import wkb
from binascii import unhexlify
import datetime
import math
import uuid
from pydantic import BaseModel

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
    # 기타 종목이 들어올 수 있으므로 필요시 확장 가능

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
    title="Sports Service API",
    description="운동 대회, 공공 체육, 동호회 및 팀원 모집 API",
    version="2.2.0" 
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
# Pydantic 모델 (신규 추가)
# ====================================================

class TeamBoardCreate(BaseModel):
    user_id: str
    title: str
    content: str
    sport_category: Optional[str] = None
    location_name: Optional[str] = None
    recruitment_status: str = "모집 중"
    required_skill_level: Optional[str] = None
    max_member_count: Optional[int] = None

class ReplyCreate(BaseModel):
    user_id: str
    content: str
    parent_id: Optional[int] = None
    is_application: bool = False

# ====================================================
# 핵심 유틸리티 함수: 페이지네이션 및 데이터 처리
# ====================================================

async def fetch_paginated_data(base_query: Any) -> List[Dict[str, Any]]:
    """페이지네이션을 사용하여 쿼리의 모든 데이터를 가져옵니다."""
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

# 기존 함수 유지 (대회 데이터 처리용)
async def fetch_all_competitions_paginated(base_query: Any) -> List[Dict[str, Any]]:
    return await fetch_paginated_data(base_query)

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
# AI 추천 관련 유틸리티 (기존 유지)
# ====================================================

def get_skill_level_from_grade(sport: str, grade: Optional[str]) -> str:
    grade = grade.strip().replace(' ', '') if grade else ""
    if not grade: return "무관"
    try:
        sport_enum = SportCategory(sport)
    except ValueError:
        return "무관"
    mapping = GRADE_SKILL_MAP.get(sport_enum, {})
    normalized_grade = grade.upper().replace(' ', '')
    for skill_level, grades in mapping.items():
        if normalized_grade in [g.upper().replace(' ', '') for g in grades]:
            return skill_level
    return "무관"

def age_matches(user_age: int, competition_age_str: Optional[str]) -> bool:
    if not competition_age_str or competition_age_str == "무관": return True
    try:
        age_str = competition_age_str.replace(' ', '').replace('세', '')
        if '~' not in age_str: return user_age == int(age_str)
        elif age_str.startswith('~'): return user_age < int(age_str[1:])
        elif age_str.endswith('~'): return user_age >= int(age_str[:-1])
        else:
            min_str, max_str = age_str.split('~')
            return int(min_str) <= user_age < int(max_str)
    except: return False

def gender_matches(user_gender: Optional[str], competition_gender: Optional[str]) -> bool:
    if not competition_gender or competition_gender == "무관": return True
    user_gender = user_gender.strip() if user_gender else None
    if not user_gender: return False
    return competition_gender.strip() == user_gender

def calculate_location_similarity(user_lat: float, user_lon: float, comp_lat: float, comp_lon: float) -> float:
    # Haversine implementation simplified for brevity (refer to original if needed)
    dlat = math.radians(comp_lat - user_lat)
    dlon = math.radians(comp_lon - user_lon)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(user_lat)) * math.cos(math.radians(comp_lat)) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    dist = EARTH_RADIUS_KM * c
    return 1.0 - (min(dist, MAX_DIST_KM) / MAX_DIST_KM)

def calculate_skill_similarity(user_skill: str, comp_grade: str, comp_sport: str) -> float:
    comp_skill = get_skill_level_from_grade(comp_sport, comp_grade)
    diff = abs(SKILL_RANK.get(user_skill, 0) - SKILL_RANK.get(comp_skill, 0))
    return max(0.0, 1.0 - (diff / 3.0))

def calculate_recommendation_score(user_profile: Dict[str, Any], competition: Dict[str, Any]) -> Tuple[float, Optional[float], Optional[float]]:
    comp_sport = competition.get("sport_category")
    user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
    
    if comp_sport not in user_sports_map: return 0.0, None, None
    if not gender_matches(user_profile.get("gender"), competition.get("gender")): return 0.0, None, None
    if not age_matches(user_profile.get("age"), competition.get("age")): return 0.0, None, None

    user_skill = user_sports_map.get(comp_sport, "무관")
    skill_score = calculate_skill_similarity(user_skill, competition.get("grade"), comp_sport)
    
    u_lat, u_lon = user_profile.get("user_latitude"), user_profile.get("user_longitude")
    c_lat, c_lon = competition.get("latitude"), competition.get("longitude")
    
    if u_lat is None or c_lat is None: location_score = 0.5
    else: location_score = calculate_location_similarity(u_lat, u_lon, c_lat, c_lon)

    return (SKILL_WEIGHT * skill_score) + (LOCATION_WEIGHT * location_score), skill_score, location_score

async def get_user_profile(user_id: str) -> Dict[str, Any]:
    if not supabase: raise HTTPException(status_code=503, detail="Supabase Disconnected")
    profile_res = supabase.table("profiles").select("age, gender, location").eq("id", user_id).execute()
    if not profile_res.data: raise HTTPException(status_code=404, detail="User not found")
    
    user_profile = profile_res.data[0]
    user_profile['user_latitude'], user_profile['user_longitude'] = None, None
    if user_profile.get('location'):
        try:
            geom = wkb.loads(unhexlify(user_profile['location']))
            user_profile['user_longitude'], user_profile['user_latitude'] = geom.x, geom.y
        except: pass
    user_profile.pop('location', None)
    
    try:
        uuid_obj = uuid.UUID(user_id)
        sports_res = supabase.table("interesting_sports").select("sport_name, skill").eq("user_id", uuid_obj).execute()
    except ValueError:
        sports_res = supabase.table("interesting_sports").select("sport_name, skill").eq("user_id", user_id).execute()
        
    user_profile['interesting_sports'] = sports_res.data
    return user_profile

# ====================================================
# 기존 엔드포인트
# ====================================================

@app.get("/")
def read_root():
    return {"message": "Sports Service API Running", "version": "2.2.0"}

@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(None),
    province: Optional[str] = Query(None),
    city_county: Optional[str] = Query(None),
    available_from: Optional[str] = Query(None)
):
    if not supabase: raise HTTPException(status_code=503, detail="Supabase Error")
    try:
        query = supabase.table("competitions").select("*")
        if sport_category: query = query.eq("sport_category", sport_category.value)
        if province and province != '전체 지역':
            query = query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구':
                query = query.eq("location_county_district", city_county)
        
        data = await fetch_all_competitions_paginated(query)
        processed = [p for p in [process_competition_data(d, available_from) for d in data] if p]
        return {"success": True, "count": len(processed), "data": processed}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/recommend/competitions", response_model=Dict[str, Any])
async def recommend_competitions(user_id: str = Query(...), top_n: int = Query(3, ge=1)):
    if not supabase: raise HTTPException(status_code=503, detail="Supabase Error")
    
    user_profile = await get_user_profile(user_id)
    user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
    if not user_sports_map: return {"success": True, "count": 0, "message": "No interests", "data": {}}
    
    all_comps = await fetch_all_competitions_paginated(supabase.table("competitions").select("*"))
    scored_by_sport = {s: [] for s in user_sports_map}
    
    for comp in all_comps:
        proc = process_competition_data(comp.copy(), datetime.date.today().isoformat())
        if not proc: continue
        
        score, skill, loc = calculate_recommendation_score(user_profile, proc)
        if score > 0.0 and proc['sport_category'] in scored_by_sport:
            proc.update({'recommendation_score': round(score, 4), 'skill_similarity': round(skill or 0, 4), 'location_similarity': round(loc or 0, 4)})
            scored_by_sport[proc['sport_category']].append(proc)
            
    final_recs = {}
    total = 0
    for sport, comps in scored_by_sport.items():
        top = sorted(comps, key=lambda x: x['recommendation_score'], reverse=True)[:top_n]
        final_recs[sport] = top
        total += len(top)
        
    return {"success": True, "count": total, "recommended_by_sport": final_recs}

# ====================================================
# [신규 추가 1] 공공 체육 프로그램 검색 엔드포인트
# ====================================================

@app.get("/public-programs", response_model=Dict[str, Any])
async def search_public_programs(
    sport_category: Optional[str] = Query(None, description="운동 종목 (예: 수영, 축구)"),
    province: Optional[str] = Query(None, description="시/도 이름"),
    city_county: Optional[str] = Query(None, description="시/군/구 이름")
):
    """
    공공 체육 프로그램(public_sport_programs)을 검색합니다.
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        base_query = supabase.table("public_sport_programs").select("*")

        if sport_category:
            base_query = base_query.eq("sport_category", sport_category)
        
        if province and province != '전체 지역':
            base_query = base_query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구':
                base_query = base_query.eq("location_county_district", city_county)
        
        # 최신 등록순 정렬 (옵션)
        base_query = base_query.order("id", desc=True)

        results = await fetch_paginated_data(base_query)

        return {
            "success": True,
            "count": len(results),
            "data": results
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "공공 체육 프로그램 조회 중 오류가 발생했습니다."}
        )


# ====================================================
# [신규 추가 2] 전국 체육 동호회 검색 엔드포인트
# ====================================================

@app.get("/clubs", response_model=Dict[str, Any])
async def search_clubs(
    sport_category: Optional[str] = Query(None, description="운동 종목"),
    province: Optional[str] = Query(None, description="시/도 이름"),
    city_county: Optional[str] = Query(None, description="시/군/구 이름")
):
    """
    전국 체육 동호회(sport_clubs) 정보를 검색합니다.
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        base_query = supabase.table("sport_clubs").select("*")

        if sport_category:
            base_query = base_query.eq("sport_category", sport_category)
        
        if province and province != '전체 지역':
            base_query = base_query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구':
                base_query = base_query.eq("location_county_district", city_county)

        results = await fetch_paginated_data(base_query)

        return {
            "success": True,
            "count": len(results),
            "data": results
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "동호회 조회 중 오류가 발생했습니다."}
        )


# ====================================================
# [신규 추가 3] 팀원 모집 게시판 (Team Board)
# ====================================================

@app.get("/team-board", response_model=Dict[str, Any])
async def get_team_board_posts(
    sport_category: Optional[str] = Query(None, description="운동 종목"),
    location: Optional[str] = Query(None, description="지역명 필터"),
    status: Optional[str] = Query(None, description="모집 상태 (예: 모집 중)"),
    limit: int = Query(50, description="가져올 게시글 수")
):
    """
    팀원 모집 게시글 목록을 조회합니다.
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        # User 프로필 정보를 조인해서 가져오면 좋지만, 여기서는 기본 테이블 조회
        base_query = supabase.table("team_board").select("*, profiles(nickname)").eq("is_active", True)

        if sport_category:
            base_query = base_query.eq("sport_category", sport_category)
        
        if location:
            base_query = base_query.ilike("location_name", f"%{location}%")
            
        if status:
            base_query = base_query.eq("recruitment_status", status)

        # 최신순 정렬
        response = base_query.order("created_at", desc=True).limit(limit).execute()
        
        return {
            "success": True,
            "count": len(response.data),
            "data": response.data
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={"success": False, "error": str(e), "message": "게시글 목록 조회 실패"}
        )

@app.get("/team-board/{board_id}", response_model=Dict[str, Any])
async def get_team_board_detail(board_id: int):
    """
    특정 게시글 상세 조회 (조회수 증가 포함)
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")
        
    try:
        # 1. 조회수 증가 (RPC 또는 직접 업데이트)
        # 동시성 문제가 중요하지 않다면 읽고 업데이트하는 방식 사용
        # 여기서는 간단히 increment RPC가 없다고 가정하고 로직 처리
        # (실제 운영환경에서는 increment_views RPC 함수를 만드는 것이 안전함)
        
        # 상세 데이터 조회 (작성자 프로필 포함)
        response = supabase.table("team_board").select("*, profiles(nickname, gender, age)").eq("id", board_id).execute()
        
        if not response.data:
            raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
            
        post = response.data[0]
        
        # 조회수 +1 업데이트 (비동기적으로 처리하거나 여기서 바로 처리)
        new_views = (post.get("views_count") or 0) + 1
        supabase.table("team_board").update({"views_count": new_views}).eq("id", board_id).execute()
        post["views_count"] = new_views # 응답용 데이터 업데이트

        return {"success": True, "data": post}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "error": str(e)})

@app.post("/team-board", response_model=Dict[str, Any])
async def create_team_board_post(post: TeamBoardCreate):
    """
    팀원 모집 게시글 작성
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        data = post.dict(exclude_none=True)
        # User ID가 UUID인지 확인 필요 (테이블 제약조건)
        
        response = supabase.table("team_board").insert(data).execute()
        
        if not response.data:
            raise HTTPException(status_code=400, detail="게시글 작성에 실패했습니다.")
            
        return {"success": True, "message": "게시글이 등록되었습니다.", "data": response.data[0]}
        
    except Exception as e:
        print(f"Error creating post: {e}")
        raise HTTPException(status_code=500, detail={"success": False, "error": str(e)})


# ====================================================
# [신규 추가 4] 댓글 기능 (Replies)
# ====================================================

@app.get("/team-board/{board_id}/replies", response_model=Dict[str, Any])
async def get_replies(board_id: int):
    """
    특정 게시글의 댓글 목록 조회
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        # 댓글과 작성자 정보 조인
        response = supabase.table("replies")\
            .select("*, profiles(nickname)")\
            .eq("board_id", board_id)\
            .order("created_at", desc=False)\
            .execute()
            
        return {"success": True, "count": len(response.data), "data": response.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "error": str(e)})

@app.post("/team-board/{board_id}/replies", response_model=Dict[str, Any])
async def create_reply(board_id: int, reply: ReplyCreate):
    """
    댓글 작성 (일반 댓글 또는 신청 댓글)
    """
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase가 연결되지 않았습니다.")

    try:
        data = reply.dict(exclude_none=True)
        data["board_id"] = board_id # URL path param 사용
        
        response = supabase.table("replies").insert(data).execute()
        
        if not response.data:
            raise HTTPException(status_code=400, detail="댓글 작성 실패")
            
        return {"success": True, "message": "댓글이 등록되었습니다.", "data": response.data[0]}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail={"success": False, "error": str(e)})

if __name__ == "__main__":
    import uvicorn
    # uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)
    pass