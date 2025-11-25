from fastapi import FastAPI, Query, HTTPException
from dotenv import load_dotenv
import os
from typing import Optional, Dict, Any
import json
from enum import Enum
from supabase import create_client, Client
from shapely import wkb
from binascii import unhexlify


# 허용되는 스포츠 종목을 Enum으로 정의하여 유효성 검사 강화
# Enum Key: DB 쿼리 값 (영어)
# Enum Value: 프론트엔드에서 받는 값 (한글)
class SportCategory(str, Enum):
    badminton = "배드민턴"
    running = "마라톤"
    fitness = "보디빌딩"
    tennis = "테니스"

# 환경변수 로드
load_dotenv()

# FastAPI 앱 생성
app = FastAPI(
    title="Sports Competition API (한글-영어 매핑 버전)",
    description="운동 대회 검색 API (프론트엔드 한글 선택 → DB 영어 쿼리)",
    version="1.0.0"
)

# Supabase 클라이언트 초기화 (조건부)
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")
supabase = None

# Supabase 설정이 있을 때만 연결
if supabase_url and supabase_key and supabase_url != "your-supabase-url":
    try:
        supabase: Client = create_client(supabase_url, supabase_key)
        print("✅ Supabase 연결 성공!")
    except Exception as e:
        print(f"⚠️ Supabase 연결 실패: {e}")
else:
    print("⚠️ Supabase 설정이 없습니다. 나중에 .env 파일을 설정하세요.")


@app.get("/")
def read_root():
    """헬스체크 엔드포인트"""
    return {
        "message": "Sports Competition API is running!",
        "version": "1.0.0",
        "supabase_connected": supabase is not None
    }


# 테스트용: 모든 데이터 확인 엔드포인트는 그대로 유지합니다.
@app.get("/test/all-data")
async def test_all_data():
    if not supabase:
        return {
            "success": False,
            "message": "Supabase가 연결되지 않았습니다."
        }
    
    try:
        response = supabase.table("competitions").select("*").execute()
        
        print("\n" + "="*70)
        print(f"📊 전체 대회 데이터: {len(response.data)}개")
        print("="*70)
        
        if response.data:
            for idx, competition in enumerate(response.data, 1):
                print(f"\n[{idx}번째 대회]")
                print(json.dumps(competition, indent=2, ensure_ascii=False))
                print("-" * 70)
        else:
            print("\n❌ DB에 데이터가 없습니다.")
        
        return {
            "success": True,
            "total_count": len(response.data),
            "data": response.data
        }
        
    except Exception as e:
        print(f"\n❌ 에러: {str(e)}")
        return {
            "success": False,
            "error": str(e)
        }


# 메인 검색 엔드포인트
@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(
        None, 
        description="운동 종목 (배드민턴, 마라톤, 보디빌딩, 테니스 중 하나)",
        examples=[SportCategory.badminton.value]
    ),
    location_city_county: Optional[str] = Query(
        None, 
        description="지역 (시/구)",
        examples=["서울특별시 강남구"]
    ),
    available_from: Optional[str] = Query(
        None, 
        description="참가 가능 시작 날짜 (YYYY-MM-DD) - 이 날짜 이후에 시작하는 대회만 표시",
        examples=["2025-11-01"]
    )
):
    """
    사용자가 선택한 조건에 맞는 대회 검색 (종목, 지역, 기간)
    """
    print("sport_category:",sport_category)
    print("location_city_county:",location_city_county)
    print("available_from:",available_from)
    
    if not supabase:
        raise HTTPException(
            status_code=503,
            detail={"success": False, "message": "Supabase가 연결되지 않았습니다."}
        )
    
    query_sport_category = None
    if sport_category:
        query_sport_category = sport_category.name
        
    try:
        # 일반 쿼리 (날짜 필터는 Python에서 처리)
        query = supabase.table("competitions").select("*")
        
        if query_sport_category:
            query = query.eq("sport_category", query_sport_category)
        
        if location_city_county:
            query = query.eq("location_city_county", location_city_county)
        
        # 날짜 필터는 제거 (Python에서 처리)
        # if available_from:
        #     query = query.gte("event_start_date", available_from)  # ← 이 줄 삭제!
        
        response = query.execute()
        
        # WKB 파싱해서 위도/경도 추출 + 날짜 필터링
        processed_data = []
        for item in response.data:
            # 날짜 필터링 (Python에서 처리)
            if available_from and item.get('event_period'):
                try:
                    # event_period: "[2025-11-15,2025-11-17)"
                    # 시작 날짜 추출
                    period_str = item['event_period']
                    start_date_str = period_str.split(',')[0].replace('[', '').strip()
                    
                    # 날짜 비교 (문자열 비교로 충분 - YYYY-MM-DD 형식)
                    if start_date_str < available_from:
                        continue  # 조건에 맞지 않으면 스킵
                except Exception as e:
                    print(f"⚠️ 날짜 파싱 실패 (ID: {item.get('id')}): {e}")
                    # 날짜 파싱 실패해도 데이터는 포함
            
            # WKB 16진수 문자열을 파싱
            if item.get('location'):
                try:
                    geom = wkb.loads(unhexlify(item['location']))
                    item['location_lng'] = geom.x
                    item['location_lat'] = geom.y
                except Exception as e:
                    print(f"⚠️ 좌표 파싱 실패 (ID: {item.get('id')}): {e}")
                    item['location_lng'] = None
                    item['location_lat'] = None
            else:
                item['location_lng'] = None
                item['location_lat'] = None
            
            # WKB 바이너리 제거
            item.pop('location', None)
            
            processed_data.append(item)
        
        print(f"\n🔍 API 요청: 종목={sport_category.value if sport_category else '전체'}, 지역={location_city_county}, 기간={available_from}")
        print(f"✅ 검색 결과: {len(processed_data)}개")
        
        return {
            "success": True,
            "count": len(processed_data),
            "filters": {
                "sport_category": sport_category.value if sport_category else None,
                "location_city_county": location_city_county,
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
        "supabase_key_configured": bool(supabase_key)
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)