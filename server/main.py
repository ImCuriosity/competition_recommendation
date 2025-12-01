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

# ====================================================
# 상수 및 초기 설정
# ====================================================

# Supabase REST API의 기본 최대 제한(LIMIT)은 1000개입니다. 
# 1000개 이상의 데이터를 가져오려면 이 크기로 반복 요청해야 합니다.
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
    title="Sports Competition API (Pagination Fix)",
    description="운동 대회 검색 API (Supabase 1000개 제한 해제를 위한 페이지네이션 적용)",
    version="1.0.6" # 버전 업데이트
)

# Supabase 클라이언트 초기화 (조건부)
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")
supabase: Optional[Client] = None

if supabase_url and supabase_key and supabase_url != "your-supabase-url":
    try:
        # Supabase 클라이언트 초기화
        supabase = create_client(supabase_url, supabase_key)
        print("✅ Supabase 연결 성공!")
    except Exception as e:
        print(f"⚠️ Supabase 연결 실패: {e}")
else:
    print("⚠️ Supabase 설정이 없습니다. 나중에 .env 파일을 설정하세요.")

# ====================================================
# 핵심 유틸리티 함수: 페이지네이션
# ====================================================

async def fetch_all_competitions_paginated(base_query: Any) -> List[Dict[str, Any]]:
    """
    Supabase의 1000개 제한을 우회하기 위해 페이지네이션을 사용하여 모든 데이터를 가져옵니다.
    """
    all_data = []
    offset = 0
    
    while True:
        try:
            # 현재 offset과 limit으로 데이터를 요청
            response = base_query.range(offset, offset + SUPABASE_PAGE_SIZE - 1).execute()
            
            current_data = response.data
            all_data.extend(current_data)
            
            # 현재 페이지의 데이터가 페이지 크기보다 작으면 마지막 페이지이므로 루프 종료
            if len(current_data) < SUPABASE_PAGE_SIZE:
                break
            
            # 다음 페이지로 이동
            offset += SUPABASE_PAGE_SIZE
            
        except Exception as e:
            print(f"❌ 페이지네이션 중 오류 발생 (Offset: {offset}): {e}")
            break # 오류 발생 시 루프 종료

    return all_data


def process_competition_data(item: Dict[str, Any], available_from: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """WKB 파싱 및 날짜 필터링/처리 로직"""
    
    # 1. 날짜 필터링
    if available_from and item.get('event_period'):
        try:
            period_str = item['event_period']
            # event_period가 "[YYYY-MM-DD, YYYY-MM-DD]" 형태라고 가정
            start_date_str = period_str.split(',')[0].replace('[', '').strip()
            
            if start_date_str < available_from:
                return None # 필터링 조건 불충족 (시작 날짜가 선택일보다 이전)
        except Exception as e:
            # 날짜 파싱 실패해도 일단 포함
            pass

    # 2. WKB 파싱 및 위도/경도 추출
    if item.get('location'):
        try:
            # WKB 16진수 문자열을 파싱
            geom = wkb.loads(unhexlify(item['location']))
            item['longitude'] = geom.x
            item['latitude'] = geom.y
        except Exception as e:
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
# 엔드포인트
# ====================================================

@app.get("/")
def read_root():
    """헬스체크 엔드포인트"""
    return {
        "message": "Sports Competition API is running!",
        "version": "1.0.6",
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
        # 페이지네이션 함수를 사용하여 모든 데이터를 가져옵니다.
        base_query = supabase.table("competitions").select("*")
        all_data = await fetch_all_competitions_paginated(base_query)
        
        total_count_fetched = len(all_data)
        
        print("\n" + "="*70)
        print(f"📊 전체 대회 데이터: {total_count_fetched}개 (페이지네이션 적용)")
        print("="*70)
        
        # 데이터가 너무 많으면 출력하지 않거나 일부만 출력
        if all_data and total_count_fetched < 10:
            for idx, competition in enumerate(all_data, 1):
                print(f"\n[{idx}번째 대회]")
                print(json.dumps(competition, indent=2, ensure_ascii=False))
                print("-" * 70)
        
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
    )
):
    """
    사용자가 선택한 조건에 맞는 대회 검색 (종목, 지역, 기간) - 페이지네이션 적용
    """
    print("sport_category:", sport_category)
    print("province:", province)
    print("city_county:", city_county)
    print("available_from:", available_from)
    
    if not supabase:
        raise HTTPException(
            status_code=503,
            detail={"success": False, "message": "Supabase가 연결되지 않았습니다."}
        )
    
    query_sport_category = sport_category.value if sport_category else None
    
    try:
        # 1. 기본 쿼리 빌드
        base_query = supabase.table("competitions").select("*")
        
        # 1-1. 종목 필터 적용
        if query_sport_category:
            base_query = base_query.eq("sport_category", query_sport_category)
        
        # 1-2. 🚀 최종 수정된 지역 필터링 로직 (DB 컬럼: location_province_city, location_county_district 사용)
        if province and province != '전체 지역':
            
            # 시/도 필터: location_province_city 컬럼과 정확히 일치 (EQ)
            base_query = base_query.eq("location_province_city", province)
            
            if city_county and city_county != '전체 시/군/구':
                # 시/군/구 필터: location_county_district 컬럼과 정확히 일치 (EQ)
                base_query = base_query.eq("location_county_district", city_county)
                
        # 2. 페이지네이션을 사용하여 필터링된 모든 데이터를 가져옵니다.
        all_fetched_data = await fetch_all_competitions_paginated(base_query)
        
        # 3. WKB 파싱 및 날짜 필터링 (클라이언트 측 필터)
        processed_data: List[Dict[str, Any]] = []
        for item in all_fetched_data:
            processed_item = process_competition_data(item, available_from)
            if processed_item:
                processed_data.append(processed_item)
        
        
        print(f"\n🔍 API 요청: 종목={query_sport_category if query_sport_category else '전체'}, 시/도={province}, 시/군/구={city_county}, 기간={available_from}")
        print(f"✅ Supabase에서 가져온 총 데이터: {len(all_fetched_data)}개")
        print(f"✅ 검색 결과 (날짜 필터링 후): {len(processed_data)}개")
        
        return {
            "success": True,
            "count": len(processed_data),
            "total_fetched": len(all_fetched_data),
            "filters": {
                "sport_category": query_sport_category,
                "province": province,
                "city_county": city_county,
                "available_from": available_from
            },
            "data": processed_data
        }
        
    except Exception as e:
        print(f"❌ 에러: {str(e)}\n")
        raise HTTPException(
            status_code=500,
            detail={
                "success": False,
                "error": str(e),
                "message": "대회 검색 중 오류가 발생했습니다."
            }
        )


@app.get("/health")
def health_check():
    """서버 상태 확인"""
    return {
        "status": "healthy",
        "supabase_connected": supabase is not None,
        "supabase_url_configured": bool(supabase_url),
        "supabase_key_configured": bool(supabase_key),
        "api_version": "1.0.6"
    }

if __name__ == "__main__":
    import uvicorn
    # 안드로이드 에뮬레이터 접근을 위해 host를 0.0.0.0으로 설정
    uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)