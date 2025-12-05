from fastapi import FastAPI, Query, HTTPException, Depends, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from dotenv import load_dotenv
import os
import jwt
from typing import Optional, Dict, Any, List, Tuple
from enum import Enum
from supabase import create_client, Client
# ✅ 공식 경로 사용 (권장)
from supabase import ClientOptions
from shapely import wkb
from binascii import unhexlify
import datetime
import math
import uuid
from pydantic import BaseModel

# ====================================================
# 환경변수 및 상수 설정
# ====================================================

load_dotenv()

supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_ANON_KEY")
supabase_jwt_secret = os.getenv("SUPABASE_JWT_SECRET")

SUPABASE_PAGE_SIZE = 1000
EARTH_RADIUS_KM = 6371.0
MAX_DIST_KM = 500.0
SKILL_WEIGHT = 0.6
LOCATION_WEIGHT = 0.4
SKILL_RANK = {"상": 3, "중": 2, "하": 1, "무관": 0}

# ====================================================
# FastAPI 앱 및 Supabase 클라이언트 초기화
# ====================================================

app = FastAPI(
    title="Sports Competition API (V2.3 - Edit/Delete)",
    description="운동 대회 검색, AI 추천, 게시판 API (수정/삭제 기능 추가)",
    version="2.3.0"
)

# 익명 클라이언트 (공개 데이터 조회용)
supabase: Optional[Client] = None
if supabase_url and supabase_key:
    try:
        supabase = create_client(supabase_url, supabase_key)
        print("✅ Supabase 익명 클라이언트 연결 성공!")
    except Exception as e:
        print(f"⚠️ Supabase 익명 클라이언트 연결 실패: {e}")

# ====================================================
# Pydantic 모델
# ====================================================

class TeamBoardUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    sport_category: Optional[str] = None
    location_name: Optional[str] = None
    recruitment_status: Optional[str] = None
    required_skill_level: Optional[str] = None
    max_member_count: Optional[int] = None

class TeamBoardCreate(BaseModel):
    title: str
    content: str
    sport_category: Optional[str] = None
    location_name: Optional[str] = None
    recruitment_status: str = "모집 중"
    required_skill_level: Optional[str] = None
    max_member_count: Optional[int] = None

class ReplyCreate(BaseModel):
    content: str
    parent_id: Optional[int] = None
    is_application: bool = False

class SportCategory(str, Enum):
    배드민턴 = "배드민턴"
    마라톤 = "마라톤"
    보디빌딩 = "보디빌딩"
    테니스 = "테니스"

GRADE_SKILL_MAP: Dict[SportCategory, Dict[str, List[str]]] = {
    SportCategory.테니스: {
        "상": ["챌린저부", "마스터스부", "지도자부", "개나리부", "국화부", "통합부", "마스터스", "챌린저"],
        "중": ["전국신인부", "남자오픈부", "여자퓨처스부", "남자퓨처스부", "세미오픈부", "베테랑부", "오픈부", "신인부", "썸머부", "무궁화부", "랭킹부", "퓨처스부"],
        "하": ["남자테린이부", "여자테린이부", "지역 신인부", "입문부", "테린이", "초심", "루키", "신인"],
        "무관": ["무관", "", "전부"],
    },
    SportCategory.보디빌딩: {"상": ["마스터즈", "시니어", "오픈", "프로", "엘리트", "오버롤", "마스터"], "중": ["주니어", "미들", "일반부", "학생부"], "하": ["루키", "노비스", "비기너", "초심"], "무관": ["무관", ""]},
    SportCategory.배드민턴: {"상": ["S급", "A급", "B급", "S조", "A조", "B조", "자강"], "중": ["C급", "D급", "C조", "D조"], "하": ["E급", "초심", "왕초", "신인", "F급", "E조"], "무관": ["무관", ""]},
    SportCategory.마라톤: {
        "상": ["풀", "하프", "42.195km", "21.0975km", "100km", "50km", "48km", "40km", "35km", "32km", "32.195km", "25km", "16km", "15km", "Full", "Half", "마니아"],
        "중": ["13km", "12km", "11.19km", "10km", "7.5km", "7km", "10k"],
        "하": ["5km", "3km", "5km 걷기", "7인1조 단체전", "5k", "3k", "걷기"],
        "무관": ["무관", "", "전부"],
    },
}

# ====================================================
# 인증
# ====================================================

security = HTTPBearer()

def get_authed_supabase_client(token: str) -> Client:
    if not supabase_url or not supabase_key: raise HTTPException(503, "Supabase 설정 없음")
    return create_client(supabase_url, supabase_key, options=ClientOptions(headers={"Authorization": f"Bearer {token}"}))

async def get_current_user_id(credentials: HTTPAuthorizationCredentials = Depends(security)) -> str:
    token = credentials.credentials
    
    if not supabase_jwt_secret: 
        raise HTTPException(500, "JWT 시크릿 설정 없음")
        
    try:
        payload = jwt.decode(
            token, 
            supabase_jwt_secret, 
            algorithms=["HS256"], 
            audience="authenticated"
        )
        
        user_id = payload.get("sub")
        if not user_id: 
            raise HTTPException(401, "유효하지 않은 토큰 (ID 없음)")
            
        return user_id
        
    except jwt.ExpiredSignatureError: 
        raise HTTPException(401, "토큰 만료")
    except (jwt.PyJWTError, Exception) as e:
        print(f"DEBUG Error: {e}")
        raise HTTPException(401, "유효하지 않은 토큰")

# ====================================================
# 유틸리티 함수
# ====================================================
async def fetch_paginated_data(base_query: Any) -> List[Dict[str, Any]]:
    all_data = []
    offset = 0
    while True:
        try:
            response = base_query.range(offset, offset + SUPABASE_PAGE_SIZE - 1).execute()
            all_data.extend(response.data)
            if len(response.data) < SUPABASE_PAGE_SIZE: break
            offset += SUPABASE_PAGE_SIZE
        except: break
    return all_data

def process_competition_data(item: Dict[str, Any], available_from: Optional[str] = None) -> Optional[Dict[str, Any]]:
    if available_from and item.get('event_period'):
        try:
            if item['event_period'].split(',')[0].replace('[', '').strip() < available_from: return None
        except: pass
    if item.get('location'):
        try:
            geom = wkb.loads(unhexlify(item['location']))
            item['longitude'] = geom.x; item['latitude'] = geom.y
        except: item['longitude'] = None; item['latitude'] = None
    else: item['longitude'] = None; item['latitude'] = None
    if item.get('event_period'): item['start_date'] = item.pop('event_period', '').split(',')[0].replace('[', '').strip()
    else: item['start_date'] = None
    item.pop('location', None)
    return item

def get_skill_level_from_grade(sport: str, grade: Optional[str]) -> str:
    grade = grade.strip().replace(' ', '') if grade else ""
    if not grade: return "무관"
    try: sport_enum = SportCategory(sport)
    except ValueError: return "무관"
    mapping = GRADE_SKILL_MAP.get(sport_enum, {})
    normalized_grade = grade.upper().replace(' ', '')
    for skill_level, grades in mapping.items():
        if normalized_grade in [g.upper().replace(' ', '') for g in grades]: return skill_level
    return "무관"

def age_matches(user_age: int, competition_age_str: Optional[str]) -> bool:
    if not competition_age_str or competition_age_str == "무관": return True
    try:
        age_str = competition_age_str.replace(' ', '').replace('세', '')
        if '~' not in age_str: return user_age == int(age_str)
        elif age_str.startswith('~'): return user_age < int(age_str[1:])
        elif age_str.endswith('~'): return user_age >= int(age_str[:-1])
        else:
            min_str, max_str = age_str.split('~'); return int(min_str) <= user_age < int(max_str)
    except: return False

def gender_matches(user_gender: Optional[str], competition_gender: Optional[str]) -> bool:
    if not competition_gender or competition_gender == "무관": return True
    user_gender = user_gender.strip() if user_gender else None
    comp_gender = competition_gender.strip()
    if not user_gender: return False
    if comp_gender == user_gender: return True
    return False

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    return EARTH_RADIUS_KM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def calculate_location_similarity(user_lat: float, user_lon: float, comp_lat: float, comp_lon: float) -> float:
    distance = haversine_distance(user_lat, user_lon, comp_lat, comp_lon)
    return 1.0 - min(distance, MAX_DIST_KM) / MAX_DIST_KM

def calculate_skill_similarity(user_skill: str, comp_grade: str, comp_sport: str) -> float:
    comp_skill = get_skill_level_from_grade(comp_sport, comp_grade)
    user_rank, comp_rank = SKILL_RANK.get(user_skill, 0), SKILL_RANK.get(comp_skill, 0)
    return max(0.0, 1.0 - (abs(user_rank - comp_rank) / 3.0))

def calculate_recommendation_score(user_profile: Dict[str, Any], competition: Dict[str, Any]) -> Tuple[float, Optional[float], Optional[float]]:
    comp_sport = competition.get("sport_category")
    user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
    user_age, user_gender = user_profile.get("age"), user_profile.get("gender")
    comp_age, comp_gender = competition.get("age"), competition.get("gender")
    user_lat, user_lon = user_profile.get("user_latitude"), user_profile.get("user_longitude")
    comp_lat, comp_lon = competition.get("latitude"), competition.get("longitude")
    if comp_sport not in user_sports_map: return 0.0, None, None
    if not gender_matches(user_gender, comp_gender): return 0.0, None, None
    if not user_age or not age_matches(user_age, comp_age): return 0.0, None, None
    user_skill = user_sports_map.get(comp_sport, "무관")
    comp_grade = competition.get("grade")
    skill_score = calculate_skill_similarity(user_skill, comp_grade, comp_sport)
    location_score = 0.5 if user_lat is None or comp_lat is None else calculate_location_similarity(user_lat, user_lon, comp_lat, comp_lon)
    return (SKILL_WEIGHT * skill_score) + (LOCATION_WEIGHT * location_score), skill_score, location_score


# ====================================================
# 공개 엔드포인트 (인증 불필요)
# ====================================================

@app.get("/")
def read_root(): return {"message": "Sports API is running!", "version": "2.3.0"}

@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(sport_category: Optional[SportCategory] = None, province: Optional[str] = None, city_county: Optional[str] = None, available_from: Optional[str] = None):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        query = supabase.table("competitions").select("*")
        if sport_category: query = query.eq("sport_category", sport_category.value)
        if province and province != '전체 지역':
            query = query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구': query = query.eq("location_county_district", city_county)
            
        all_data = await fetch_paginated_data(query)
        processed = [p for item in all_data if (p := process_competition_data(item, available_from))]
        
        seen_titles = set()
        unique_competitions = []
        
        for item in processed:
            title = item.get('title')
            if title and title not in seen_titles:
                seen_titles.add(title)
                unique_competitions.append(item)
        
        return {"success": True, "count": len(unique_competitions), "data": unique_competitions}

    except Exception as e: raise HTTPException(500, f"대회 검색 오류: {e}")

@app.get("/public-programs", response_model=Dict[str, Any])
async def search_public_programs(sport_category: Optional[str] = None, province: Optional[str] = None, city_county: Optional[str] = None):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        query = supabase.table("public_sport_programs").select("*")
        if sport_category and sport_category != '전체 종목': query = query.eq("sport_category", sport_category)
        if province and province != '전체 지역': 
            query = query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구': query = query.eq("location_county_district", city_county)
        results = await fetch_paginated_data(query)
        return {"success": True, "count": len(results), "data": results}
    except Exception as e: raise HTTPException(500, f"공공 체육 프로그램 조회 오류: {e}")

@app.get("/clubs", response_model=Dict[str, Any])
async def search_clubs(sport_category: Optional[str] = None, province: Optional[str] = None, city_county: Optional[str] = None):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        query = supabase.table("sport_clubs").select("*")
        if sport_category and sport_category != '전체 종목': query = query.eq("sport_category", sport_category)
        if province and province != '전체 지역': 
            query = query.eq("location_province_city", province)
            if city_county and city_county != '전체 시/군/구': query = query.eq("location_county_district", city_county)
        results = await fetch_paginated_data(query)
        return {"success": True, "count": len(results), "data": results}
    except Exception as e: raise HTTPException(500, f"동호회 조회 오류: {e}")

@app.get("/team-board", response_model=Dict[str, Any])
async def get_team_board_posts(sport_category: Optional[str] = None, recruitment_status: Optional[str] = None):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        query = supabase.table("team_board").select("*, profiles(nickname)").eq("is_active", True)
        if sport_category and sport_category != '전체 종목': query = query.eq("sport_category", sport_category)
        if recruitment_status and recruitment_status != '전체': query = query.eq("recruitment_status", recruitment_status)
        response = query.order("created_at", desc=True).limit(100).execute()
        return {"success": True, "data": response.data}
    except Exception as e: raise HTTPException(500, f"게시글 목록 조회 실패: {e}")

@app.get("/team-board/{board_id}", response_model=Dict[str, Any])
async def get_team_board_detail(board_id: int):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        # profiles 조인을 제거하고 user_id를 직접 선택
        post_res = supabase.table("team_board").select("*, user_id").eq("id", board_id).single().execute()
        if not post_res.data: raise HTTPException(404, "게시글을 찾을 수 없습니다.")
        
        # 조회수 업데이트는 그대로 유지
        new_views = (post_res.data.get("views_count") or 0) + 1
        supabase.table("team_board").update({"views_count": new_views}).eq("id", board_id).execute()
        post_res.data['views_count'] = new_views
        
        # 클라이언트에서 작성자 닉네임을 사용하기 위해 profiles 테이블에서 닉네임을 별도로 조회
        author_profile_res = supabase.table("profiles").select("nickname").eq("id", post_res.data['user_id']).single().execute()
        if author_profile_res.data:
            post_res.data['profiles'] = {'nickname': author_profile_res.data['nickname']}
        else:
            post_res.data['profiles'] = {'nickname': '익명'}
            
        return {"success": True, "data": post_res.data}
    except Exception as e: raise HTTPException(500, f"게시글 상세 조회 실패: {e}")

@app.get("/team-board/{board_id}/replies", response_model=Dict[str, Any])
async def get_replies(board_id: int):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        res = supabase.table("replies").select("*, profiles(nickname)").eq("board_id", board_id).order("created_at").execute()
        return {"success": True, "data": res.data}
    except Exception as e: raise HTTPException(500, f"댓글 조회 실패: {e}")

# ====================================================
# 🔐 인증이 필요한 엔드포인트
# ====================================================

@app.post("/team-board", response_model=Dict[str, Any])
async def create_team_board_post(post: TeamBoardCreate, current_user_id: str = Depends(get_current_user_id), authorization: HTTPAuthorizationCredentials = Depends(security)):
    try:
        supabase_authed = get_authed_supabase_client(authorization.credentials)
        data = post.dict()
        data['user_id'] = current_user_id
        response = supabase_authed.table("team_board").insert(data).execute()
        return {"success": True, "message": "게시글이 등록되었습니다.", "data": response.data[0]}
    except Exception as e: raise HTTPException(500, f"게시글 작성 오류: {e}")

@app.put("/team-board/{board_id}", response_model=Dict[str, Any])
async def update_team_board_post(board_id: int, post_update: TeamBoardUpdate, current_user_id: str = Depends(get_current_user_id), authorization: HTTPAuthorizationCredentials = Depends(security)):
    try:
        supabase_authed = get_authed_supabase_client(authorization.credentials)
        
        # 1. 게시글 조회 및 작성자 확인
        post_res = supabase_authed.table("team_board").select("user_id").eq("id", board_id).single().execute()
        if not post_res.data: raise HTTPException(404, "게시글 없음")
        if post_res.data['user_id'] != current_user_id: raise HTTPException(403, "수정 권한 없음")

        # 2. 데이터 업데이트
        update_data = post_update.dict(exclude_unset=True)
        if not update_data: raise HTTPException(400, "수정할 내용 없음")
        
        response = supabase_authed.table("team_board").update(update_data).eq("id", board_id).execute()
        return {"success": True, "message": "게시글이 수정되었습니다.", "data": response.data[0]}
    except Exception as e: raise HTTPException(500, f"게시글 수정 오류: {e}")

@app.delete("/team-board/{board_id}", response_model=Dict[str, Any])
async def delete_team_board_post(board_id: int, current_user_id: str = Depends(get_current_user_id), authorization: HTTPAuthorizationCredentials = Depends(security)):
    try:
        supabase_authed = get_authed_supabase_client(authorization.credentials)
        
        # 1. 게시글 조회 및 작성자 확인
        post_res = supabase_authed.table("team_board").select("user_id").eq("id", board_id).single().execute()
        if not post_res.data: raise HTTPException(404, "게시글 없음")
        if post_res.data['user_id'] != current_user_id: raise HTTPException(403, "삭제 권한 없음")

        # 2. 데이터 삭제 (is_active를 False로)
        response = supabase_authed.table("team_board").update({"is_active": False}).eq("id", board_id).execute()
        return {"success": True, "message": "게시글이 삭제되었습니다."}
    except Exception as e: raise HTTPException(500, f"게시글 삭제 오류: {e}")

@app.post("/team-board/{board_id}/replies", response_model=Dict[str, Any])
async def create_reply(board_id: int, reply: ReplyCreate, current_user_id: str = Depends(get_current_user_id), authorization: HTTPAuthorizationCredentials = Depends(security)):
    try:
        supabase_authed = get_authed_supabase_client(authorization.credentials)
        data = reply.dict()
        data["board_id"] = board_id
        data["user_id"] = current_user_id
        response = supabase_authed.table("replies").insert(data).execute()
        return {"success": True, "message": "댓글이 등록되었습니다.", "data": response.data[0]}
    except Exception as e: raise HTTPException(500, f"댓글 작성 오류: {e}")

async def get_user_profile(user_id: str, supabase_authed: Client) -> Dict[str, Any]:
    profile_res = supabase_authed.table("profiles").select("*, interesting_sports(*)").eq("id", user_id).maybe_single().execute()
    if not profile_res.data: raise HTTPException(404, "사용자 프로필을 찾을 수 없습니다.")
    user_profile = profile_res.data
    if user_profile.get('location'):
        try:
            geom = wkb.loads(unhexlify(user_profile['location']))
            user_profile['user_latitude'] = geom.x
            user_profile['user_longitude'] = geom.y
        except: pass
    return user_profile

@app.get("/recommend/competitions", response_model=Dict[str, Any])
async def recommend_competitions(current_user_id: str = Depends(get_current_user_id), authorization: HTTPAuthorizationCredentials = Depends(security), top_n: int = 3):
    if not supabase: raise HTTPException(503, "Supabase 연결 실패")
    try:
        supabase_authed = get_authed_supabase_client(authorization.credentials)
        user_profile = await get_user_profile(current_user_id, supabase_authed)
        user_sports_map = {s['sport_name']: s['skill'] for s in user_profile.get('interesting_sports', [])}
        if not user_sports_map: return {"success": True, "count": 0, "message": "관심 종목 없음"}
        all_competitions = await fetch_paginated_data(supabase.table("competitions").select("*"))
        
        scored_competitions_by_sport: Dict[str, List[Dict[str, Any]]] = {s: [] for s in user_sports_map}
        available_from = datetime.date.today().isoformat()
        for comp in all_competitions:
            proc_comp = process_competition_data(comp.copy(), available_from)
            if not proc_comp: continue
            score, skill_s, loc_s = calculate_recommendation_score(user_profile, proc_comp)
            if score > 0 and proc_comp.get("sport_category") in scored_competitions_by_sport:
                proc_comp.update({'recommendation_score': score, 'skill_similarity': skill_s, 'location_similarity': loc_s})
                scored_competitions_by_sport[proc_comp["sport_category"]].append(proc_comp)

        unique_scored_competitions = {} 
        
        for sport, scored_list in scored_competitions_by_sport.items():
            best_by_title: Dict[str, Dict[str, Any]] = {}
            for comp in scored_list:
                title = comp.get('title')
                score = comp.get('recommendation_score', 0.0)
                
                if title and (title not in best_by_title or score > best_by_title[title]['recommendation_score']):
                    best_by_title[title] = comp
            
            unique_scored_competitions[sport] = list(best_by_title.values())

        final_recs = {
            s: sorted(c, key=lambda x: x['recommendation_score'], reverse=True)[:top_n] 
            for s, c in unique_scored_competitions.items()
        }
        
        total_count = sum(len(v) for v in final_recs.values())
        return {"success": True, "count": total_count, "recommended_by_sport": final_recs}
    except Exception as e: raise HTTPException(500, f"AI 추천 오류: {e}")