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
# Enum Key: DB 쿼리 값 (영어), Enum Value: 프론트엔드에서 받는 값 (한글)
class SportCategory(str, Enum):
    badminton = "배드민턴"
    running = "마라톤"
    fitness = "보디빌딩"
    tennis = "테니스"

# 환경변수 로드
load_dotenv()

# FastAPI 앱 생성
app = FastAPI(
    title="Sports Competition API (지역 검색 유연화)",
    description="운동 대회 검색 API (프론트엔드 한글 선택 → DB 영어 쿼리 및 유연한 지역 검색)",
    version="1.0.2" # 버전 업데이트
)

# Supabase 클라이언트 초기화 (조건부)
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")
supabase = None

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
        "version": "1.0.2",
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
        
        # 데이터가 너무 많으면 출력하지 않거나 일부만 출력
        if response.data and len(response.data) < 10:
             for idx, competition in enumerate(response.data, 1):
                print(f"\n[{idx}번째 대회]")
                print(json.dumps(competition, indent=2, ensure_ascii=False))
                print("-" * 70)
        
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


# 메인 검색 엔드포인트 (WKB 좌표 파싱 로직 수정됨)
@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[SportCategory] = Query(
        None, 
        description="운동 종목 (배드민턴, 마라톤, 보디빌딩, 테니스 중 하나)",
        examples=[SportCategory.badminton.value]
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
    사용자가 선택한 조건에 맞는 대회 검색 (종목, 지역, 기간) - 지역 검색 유연성 확보
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
    
    query_sport_category = None
    if sport_category:
        query_sport_category = sport_category.name
        
    try:
        query = supabase.table("competitions").select("*")
        
        if query_sport_category:
            query = query.eq("sport_category", query_sport_category)
        
        # 지역 필터링 로직 (변경 없음)
        if province and province != '전체 지역':
            location_filter_term = province
            
            if city_county and city_county != '전체 시/군/구':
                location_filter_term = f"{province} {city_county}"
                query = query.eq("location_city_county", location_filter_term)
            else:
                query = query.ilike("location_city_county", f"{location_filter_term}%")
                
        
        response = query.execute()
        
        # WKB 파싱해서 위도/경도 추출 + 날짜 필터링
        processed_data = []
        for item in response.data:
            # 날짜 필터링 (변경 없음)
            if available_from and item.get('event_period'):
                try:
                    period_str = item['event_period']
                    start_date_str = period_str.split(',')[0].replace('[', '').strip()
                    
                    if start_date_str < available_from:
                        continue
                except Exception as e:
                    print(f"⚠️ 날짜 파싱 실패 (ID: {item.get('id')}): {e}")
            
            # WKB 16진수 문자열을 파싱
            if item.get('location'):
                try:
                    geom = wkb.loads(unhexlify(item['location']))
                    item['longitude'] = geom.x
                    item['latitude'] = geom.y
                    # event_period가 있을 때만 start_date를 파싱
                    item['start_date'] = item.pop('event_period', '').split(',')[0].replace('[', '').strip()
                except Exception as e:
                    print(f"⚠️ 좌표 파싱 실패 (ID: {item.get('id')}): {e}")
                    item['longitude'] = None
                    item['latitude'] = None
            else:
                # 💡 [수정] location 필드가 없는 경우, 프론트엔드가 기대하는 필드에 None 할당
                item['longitude'] = None
                item['latitude'] = None
                item['start_date'] = item.pop('event_period', '').split(',')[0].replace('[', '').strip()

            # WKB 바이너리 제거
            item.pop('location', None)
            
            processed_data.append(item)
        
        print(f"\n🔍 API 요청: 종목={sport_category.value if sport_category else '전체'}, 시/도={province}, 시/군/구={city_county}, 기간={available_from}")
        print(f"✅ 검색 결과: {len(processed_data)}개")
        
        return {
            "success": True,
            "count": len(processed_data),
            "filters": {
                "sport_category": sport_category.value if sport_category else None,
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
        "supabase_key_configured": bool(supabase_key)
    }

if __name__ == "__main__":
    import uvicorn
    # 안드로이드 에뮬레이터 접근을 위해 host를 0.0.0.0으로 설정
    uvicorn.run(app, host="0.0.0.0", port=8080, reload=True)