import random

# --- 주요 설정 ---
WORD_WIDTH = 60  # Verilog 모듈의 WORD_WIDTH 파라미터와 일치
NUM_VECTORS = 256 # 생성할 총 벡터 개수
OUTPUT_FILE = "./mod_test_vectors/mod_add_vectors_fixed_q.txt" # 저장될 파일 이름

# 📌 테스트에 사용할 60비트 q 값을 여기에 고정합니다.
# (아래는 60비트 소수(prime) 중 하나이며, 원하는 값으로 변경 가능)
FIXED_Q = 1152921504606846923 

# --- 메인 로직 ---
def generate_mod_add_vectors_fixed_q():
    """하나의 고정된 q에 대해 모듈러 덧셈 테스트벡터를 생성합니다."""
    
    # WORD_WIDTH에 맞춰 16진수 자릿수 계산 (60 / 4 = 15)
    hex_digits = WORD_WIDTH // 4
    max_val = (1 << WORD_WIDTH) - 1
    
    # FIXED_Q가 WORD_WIDTH 내에 있는지 확인
    if FIXED_Q > max_val:
        raise ValueError(f"FIXED_Q must be {WORD_WIDTH}-bit or less.")
        
    vectors = []
    
    # --- 1. 주요 경계값 테스트 케이스 (Edge Cases) 추가 ---
    # 고정된 q 값에 대한 경계 케이스들을 집중적으로 생성
    
    # Case 3: a + b < q (wrap-around 없음)
    vectors.append({'a': 100, 'b': 200})
    
    # Case 1: a + b = q (결과 = 0)
    vectors.append({'a': FIXED_Q - 1, 'b': 1})
    
    # Case 2: a = 0 또는 b = 0
    vectors.append({'a': 0, 'b': 12345})
    vectors.append({'a': 54321, 'b': 0})
    
    
    # Case 4: a + b > q (wrap-around 발생)
    vectors.append({'a': FIXED_Q - 10, 'b': FIXED_Q - 20})
    

    # --- 2. 랜덤 테스트 케이스 생성 ---
    # 남은 수량만큼 랜덤 케이스 생성
    num_random_vectors = NUM_VECTORS - len(vectors)
    for _ in range(num_random_vectors):
        # a, b를 0부터 q-1 사이에서 랜덤하게 선택
        a = random.randint(0, FIXED_Q - 1)
        b = random.randint(0, FIXED_Q - 1)
        vectors.append({'a': a, 'b': b})

    # --- 3. 파일에 16진수 형태로 저장 ---
    with open(OUTPUT_FILE, 'w') as f:

        for vec in vectors:
            a = vec['a']
            b = vec['b']
            # 모든 연산의 기대값은 FIXED_Q를 기준으로 계산
            expected_result = (a + b) % FIXED_Q
            
            a_hex = f"{a:0{hex_digits}x}"
            b_hex = f"{b:0{hex_digits}x}"
            q_hex = f"{FIXED_Q:0{hex_digits}x}" # q 값은 항상 고정
            expected_hex = f"{expected_result:0{hex_digits}x}"
            
            f.write(f"{a_hex} {b_hex} {q_hex} {expected_hex}\n")
            

    print(f"✅ 성공! '{OUTPUT_FILE}' 파일에 {len(vectors)}개의 테스트벡터를 생성했습니다.")

# 스크립트 실행
if __name__ == "__main__":
    generate_mod_add_vectors_fixed_q()