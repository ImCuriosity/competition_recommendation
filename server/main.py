import os
import json
from datetime import datetime
from typing import Optional, Dict, Any, List

from fastapi import FastAPI, Query, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from enum import Enum

from supabase import create_client, Client
from gotrue.errors import AuthApiError

# Supabase 클라이언트 설정을 위한 전역 변수
# Canvas 환경에서 제공되는 환경 변수를 사용합니다.
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

# --------------------
# 1. Supabase 초기화 및 연결
# --------------------

# 전역 Supabase 클라이언트 변수
supabase: Optional[Client] = None

# 비동기 Supabase 연결 초기화 함수
async def initialize_supabase():
    global supabase
    if SUPABASE_URL and SUPABASE_KEY:
        try:
            # Supabase 클라이언트 생성
            supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
            print("✅ Supabase 클라이언트 초기화 성공.")
            
            # 인증 토큰이 있다면, Canvas에서 제공하는 초기 인증 토큰을 사용합니다.
            initial_auth_token = os.environ.get("__initial_auth_token")
            if initial_auth_token:
                try:
                    # Supabase Auth에 커스텀 토큰으로 로그인 시도
                    # Gotrue.Client.sign_in(token) 대신 Gotrue.Client.set_session(access_token, refresh_token) 또는
                    # supabase.auth.sign_in_with_password() 등을 사용해야 하나,
                    # 여기서는 FastAPI 컨텍스트 내에서 인증이 이미 완료된 것으로 간주하고 클라이언트만 생성합니다.
                    # 실제 Supabase Python 클라이언트는 직접 토큰을 설정하는 sign_in_with_custom_token을 지원하지 않으므로
                    # 초기화 성공만 체크하고 넘어갑니다.
                    print("✅ 초기 인증 토큰 감지됨. 사용자 세션은 클라이언트 측에서 관리됩니다.")
                except AuthApiError as e:
                    print(f"❌ 초기 인증 토큰 사용 실패: {e}")
            else:
                print("⚠️ 초기 인증 토큰 없음. 인증 없이 Supabase에 접근합니다.")

        except Exception as e:
            print(f"❌ Supabase 클라이언트 초기화 실패: {e}")
            supabase = None
    else:
        print("❌ Supabase 환경 변수 (URL/KEY)가 설정되지 않았습니다.")
        supabase = None

# --------------------
# 2. FastAPI 애플리케이션 설정
# --------------------

# CORS 설정: 모든 출처 허용 (개발 환경)
origins = ["*"]

app = FastAPI(title="Competition Recommender API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --------------------
# 3. 데이터 모델 및 유틸리티
# --------------------

# 종목 Enum 정의 (프론트엔드/LLM 통일성을 위해)
class SportCategory(str, Enum):
    배드민턴 = "배드민턴"
    마라톤 = "마라톤"
    보디빌딩 = "보디빌딩"
    테니스 = "테니스"

# API 응답용 Pydantic 모델 (필요에 따라 확장 가능)
class Competition(BaseModel):
    # 필요한 컬럼만 정의
    id: int
    title: str
    association_name: Optional[str]
    sport_category: str
    sport_category_detail: Optional[str]
    gender: Optional[str]
    grade: Optional[str]
    age: Optional[str]
    registration_period: Optional[str]
    event_period: Optional[str]
    location_name: Optional[str]
    location_province_city: Optional[str]
    location_county_district: Optional[str]
    location: Optional[str] # WKB 타입 문자열
    homepage_url: Optional[str]
    created_at: str

# Supabase 쿼리의 페이지네이션 처리를 위한 유틸리티
async def fetch_all_competitions_paginated(base_query):
    """
    Supabase 쿼리에서 모든 데이터를 페이지네이션을 사용하여 가져옵니다.
    """
    PAGE_SIZE = 1000 # 한 번에 가져올 최대 레코드 수
    all_data = []
    
    # Supabase 클라이언트가 초기화되지 않았으면 빈 리스트 반환
    if not supabase:
        return []
    
    # 쿼리 수행
    while True:
        try:
            # range(start, end)
            start = len(all_data)
            end = start + PAGE_SIZE - 1
            
            # 페이지네이션 적용 후 데이터 가져오기 (PostgREST의 기본 range 기능 사용)
            response = base_query.range(start, end).execute()
            
            data = response.data
            
            if not data:
                break # 더 이상 데이터가 없으면 종료
            
            all_data.extend(data)
            
            if len(data) < PAGE_SIZE:
                break # 마지막 페이지
                
        except Exception as e:
            print(f"❌ Supabase 페이지네이션 쿼리 실행 중 오류 발생: {e}")
            break
            
    return all_data

# --------------------
# 4. 이벤트 핸들러 (시작 시 Supabase 초기화)
# --------------------

@app.on_event("startup")
async def startup_event():
    # 서버 시작 시 Supabase 연결 초기화
    await initialize_supabase()

# --------------------
# 5. API 엔드포인트
# --------------------

@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(
        None, 
        description="운동 종목 (배드민턴, 마라톤, 보디빌딩, 테니스 중 하나)",
        examples=[SportCategory.배드민턴.value] 
    ),
    province: Optional[str] = Query(
        None, 
        description="시/도 이름 (예: 경기도, 서울특별시)",
        examples=["서울특별시"]
    ),
    city_county: Optional[str] = Query(
        None, 
        description="시/군/구 이름 (예: 강남구, 수원시)",
        examples=["강남구"]
    ),
    available_from: Optional[str] = Query(
        None, 
        description="참가 가능 시작 날짜 (YYYY-MM-DD)",
        examples=["2025-11-01"]
    ),
    # ★★★ 난이도 필터링을 위한 신규 파라미터 추가 ★★★
    difficulty_level: Optional[str] = Query(
        None,
        description="대회 난이도/등급 (예: 'A급', '5km', '국화부'). 종목에 따라 grade 또는 sport_category_detail 컬럼으로 매칭됩니다.",
        examples=["A급"] 
    )
):
    """
    사용자가 선택한 조건에 맞는 대회 검색 (종목, 지역, 기간, 난이도 포함)
    """
    print("--- 쿼리 파라미터 ---")
    print(f"sport_category: {sport_category.value if sport_category else None}")
    print(f"province: {province}")
    print(f"city_county: {city_county}")
    print(f"available_from: {available_from}")
    print(f"difficulty_level: {difficulty_level}") 
    print("-------------------")
    
    if not supabase:
        raise HTTPException(status_code=503, detail="Supabase 연결 오류. API 키를 확인해주세요.")
    
    query_sport_category = sport_category.value if sport_category else None
    
    try:
        # 1. 기본 쿼리 빌드
        base_query = supabase.table("competitions").select("*")
        
        # [필터 1] 종목 필터링 (가장 먼저 적용)
        if query_sport_category:
            base_query = base_query.eq("sport_category", query_sport_category)
            
        # [필터 2] ★★★ 동적 난이도 필터링 로직 ★★★
        if difficulty_level and query_sport_category:
            
            # 난이도 문자열의 앞뒤 공백 제거 및 소문자 변환 (유연성 확보)
            normalized_difficulty = difficulty_level.strip().lower()
            
            print(f"🔍 난이도 필터링 적용 중... 종목: {query_sport_category}, 값: {normalized_difficulty}")

            # 1. 마라톤 (난이도 = 거리 정보, sport_category_detail 컬럼)
            if query_sport_category == SportCategory.마라톤.value:
                # 마라톤 거리는 세부 종목 이름(sport_category_detail)에 포함되는 경우가 많으므로 ilike(부분 일치)를 사용합니다.
                # 예: '10km' -> '10km 일반부', '10K 마스터즈' 등을 찾음
                base_query = base_query.ilike("sport_category_detail", f"%{normalized_difficulty}%") 
                print(" -> 컬럼: sport_category_detail (ilike)")
                
            # 2. 배드민턴, 테니스, 보디빌딩 (난이도 = 등급 정보, grade 컬럼)
            elif query_sport_category in [SportCategory.배드민턴.value, SportCategory.테니스.value, SportCategory.보디빌딩.value]:
                # 등급은 정확히 일치하는 문자열인 경우가 많으므로 eq(정확히 일치)를 사용합니다.
                # 예: 'A급' -> grade가 'A급'인 레코드만 찾음
                base_query = base_query.eq("grade", difficulty_level)
                print(" -> 컬럼: grade (eq)")

            # 3. 그 외 종목 (추후 확장 시)
            else:
                print(" -> 경고: 해당 종목의 난이도 필터링 로직이 정의되지 않았습니다. 필터링 건너뜀.")
        
        # [필터 3] 지역 필터링
        if province:
            base_query = base_query.eq("location_province_city", province)
        
        if city_county:
            base_query = base_query.eq("location_county_district", city_county)
                
        # 2. 페이지네이션을 사용하여 필터링된 모든 데이터를 가져옵니다.
        all_fetched_data = await fetch_all_competitions_paginated(base_query)
        
        # 3. WKB 파싱 및 날짜 필터링 (클라이언트 측 필터)
        final_competitions = []
        available_from_date = datetime.strptime(available_from, '%Y-%m-%d').date() if available_from else None

        for item in all_fetched_data:
            # WKB 데이터를 JSON으로 파싱 (필요하다면)
            # item["location_parsed"] = parse_wkb(item["location"]) 
            
            is_available = True
            
            # [필터 4] 등록 가능 날짜 필터링
            if available_from_date and item.get("registration_period"):
                try:
                    # registration_period는 'YYYY-MM-DD ~ YYYY-MM-DD' 형태라고 가정
                    reg_end_str = item["registration_period"].split('~')[-1].strip()
                    reg_end_date = datetime.strptime(reg_end_str, '%Y-%m-%d').date()
                    
                    # 사용자가 원하는 날짜(available_from_date)가 등록 마감일(reg_end_date) 이전이어야 함
                    if available_from_date > reg_end_date:
                        is_available = False
                except Exception as e:
                    # 날짜 파싱 오류 발생 시 필터링 건너뛰고 포함
                    print(f"⚠️ 등록 기간 파싱 오류 발생: {e} (데이터: {item.get('registration_period')})")
            
            if is_available:
                # Pydantic 모델에 맞게 데이터 정리
                comp = Competition.parse_obj(item)
                final_competitions.append(comp.dict())

        print(f"✅ Supabase에서 가져온 총 데이터: {len(all_fetched_data)}개")
        print(f"✅ 최종 필터링된 데이터: {len(final_competitions)}개")
        
        return {
            "query_info": {
                "sport_category": query_sport_category,
                "province": province,
                "city_county": city_county,
                "available_from": available_from,
                "difficulty_level": difficulty_level,
                "total_results": len(final_competitions)
            },
            "competitions": final_competitions
        }
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"데이터 검색 중 서버 오류 발생: {e}")

# --------------------
# 6. 상태 확인용 엔드포인트
# --------------------

@app.get("/")
async def root():
    return {"message": "Competition Recommender API is running."}