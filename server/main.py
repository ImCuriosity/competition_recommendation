from fastapi import FastAPI, Query, HTTPException
from dotenv import load_dotenv
import os
from typing import Optional, Dict, Any

# 환경변수 로드
load_dotenv()

# FastAPI 앱 생성
app = FastAPI(
    title="Sports Competition API",
    description="운동 대회 검색 API",
    version="1.0.0"
)

# Supabase 클라이언트 초기화 (조건부)
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")
supabase = None

# Supabase 설정이 있을 때만 연결
if supabase_url and supabase_key and supabase_url != "your-supabase-url":
    try:
        from supabase import create_client, Client
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


@app.get("/competitions", response_model=Dict[str, Any])
async def search_competitions(
    sport_category: Optional[str] = Query(
        None, 
        description="운동 종목",
        examples=["배드민턴"]
    ),
    location_city_county: Optional[str] = Query(
        None, 
        description="지역 (시/구)",
        examples=["서울특별시 강남구"]
    ),
    available_from: Optional[str] = Query(
        None, 
        description="참가 가능 시작 날짜 (YYYY-MM-DD) - 이 날짜 이후에 시작하는 대회만 표시",
        examples=["2024-03-01"]
    )
):
    """
    사용자가 선택한 조건에 맞는 대회 검색
    
    - **sport_category**: 배드민턴, 마라톤, 보디빌딩, 테니스
    - **location_city_county**: 서울특별시 강남구, 경기도 수원시 등
    - **available_from**: 이 날짜 이후에 시작하는 대회만 검색
    """
    # Supabase 연결 확인
    print("sport_category:",sport_category)
    print("location_city_county:",location_city_county)
    print("available_from:",available_from)
    if not supabase:
        return {
            "success": False,
            "message": "Supabase가 연결되지 않았습니다.",
            "note": "나중에 .env 파일에 SUPABASE_URL과 SUPABASE_KEY를 설정하세요.",
            "filters": {
                "sport_category": sport_category,
                "location_city_county": location_city_county,
                "available_from": available_from
            }
        }
    
    try:
        # RPC 함수 호출 방식
        response = supabase.rpc(
                "search_competitions",
                {
                    # ⬇️ Supabase Stored Procedure의 정의 순서에 맞게 키-값 쌍을 배치합니다. ⬇️

                    # 1. 종목 (p_sport_category)
                    "p_sport_category": sport_category, 
                    
                    # 2. 지역 (p_location_city_county)
                    "p_location_city_county": location_city_county, 
                    
                    # 3. 날짜 (p_available_from)
                    "p_available_from": available_from
                }
            ).execute()
        
        return {
            "success": True,
            "count": len(response.data),
            "filters": {
                "sport_category": sport_category,
                "location_city_county": location_city_county,
                "available_from": available_from
            },
            "data": response.data
        }
        
    except Exception as e:
        # 💡 로그를 콘솔에 추가 출력하여 디버깅을 돕습니다.
        print(f"--- Supabase RPC Error ---")
        print(f"Filter: {sport_category}, {location_city_county}, {available_from}")
        print(f"Error: {str(e)}")
        print(f"--------------------------")
        
        raise HTTPException(
            status_code=500,
            detail={
                "success": False,
                "error": str(e), # Supabase에서 온 오류 메시지
                "message": "대회 검색 중 오류가 발생했습니다."
            }
        )


@app.get("/competitions/simple", response_model=Dict[str, Any])
async def search_competitions_simple(
    sport_category: Optional[str] = Query(None),
    location_city_county: Optional[str] = Query(None)
):
    """
    간단한 검색 (기간 필터 없이)
    종목과 지역만으로 검색
    """
    # Supabase 연결 확인
    if not supabase:
        return {
            "success": False,
            "message": "Supabase가 연결되지 않았습니다."
        }
    
    try:
        # Supabase 쿼리 시작
        query = supabase.table("competitions").select("*")
        
        # 종목 필터
        if sport_category:
            query = query.eq("sport_category", sport_category)
        
        # 지역 필터
        if location_city_county:
            query = query.eq("location_city_county", location_city_county)
        
        # 쿼리 실행
        response = query.execute()
        
        return {
            "success": True,
            "count": len(response.data),
            "data": response.data
        }
        
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail={
                "success": False,
                "error": str(e)
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