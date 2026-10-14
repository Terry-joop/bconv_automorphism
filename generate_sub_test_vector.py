import random

# --- 주요 설정 ---
WORD_WIDTH = 60  # Verilog 모듈의 WORD_WIDTH 파라미터와 일치
NUM_VECTORS = 256 # 생성할 총 벡터 개수
OUTPUT_FILE = "./mod_test_vectors/mod_sub_vectors_fixed_q.txt" # 저장될 파일 이름

# 📌 테스트에 사용할 60비트 q 값을 여기에 고정합니다.
# (덧셈 테스트와 동일한 값을 사용하여 일관성 유지)
FIXED_Q = 1152921504606846923 

# --- 메인 로직 ---
def generate_mod_sub_vectors_fixed_q():
    """하나의 고정된 q에 대해 모듈러 뺄셈 테스트벡터를 생성합니다."""
    
    hex_digits = WORD_WIDTH // 4
    max_val = (1 << WORD_WIDTH) - 1
    
    if FIXED_Q > max_val:
        raise ValueError(f"FIXED_Q must be {WORD_WIDTH}-bit or less.")
        
    vectors = []
    
    # --- 1. 주요 경계값 테스트 케이스 (Edge Cases) 추가 ---
    
    # Case 1: a < b (언더플로우 발생, 결과는 q를 더해 보정)
    # 예: (100 - 200) mod q = -100 mod q = q - 100
    vectors.append({'a': 100, 'b': 200})
    
    # Case 2: a > b (일반적인 뺄셈)
    vectors.append({'a': 200, 'b': 100})
    
    # Case 3: a = b (결과 = 0)
    vectors.append({'a': 12345, 'b': 12345})
    
    # Case 4: a = 0 또는 b = 0
    # 0 - 12345 = q - 12345
    vectors.append({'a': 0, 'b': 12345})
    # 54321 - 0 = 54321
    vectors.append({'a': 54321, 'b': 0})

    # Case 5: 경계값 근처 테스트
    # 0 - 1 = q - 1
    vectors.append({'a': 0, 'b': 1})
    # (q-1) - (q-2) = 1
    vectors.append({'a': FIXED_Q - 1, 'b': FIXED_Q - 2})
    

    # --- 2. 랜덤 테스트 케이스 생성 ---
    num_random_vectors = NUM_VECTORS - len(vectors)
    for _ in range(num_random_vectors):
        a = random.randint(0, FIXED_Q - 1)
        b = random.randint(0, FIXED_Q - 1)
        vectors.append({'a': a, 'b': b})

    # --- 3. 파일에 16진수 형태로 저장 ---
    with open(OUTPUT_FILE, 'w') as f:

        for vec in vectors:
            a = vec['a']
            b = vec['b']
            # Python의 % 연산자는 음수 결과도 올바르게 모듈러 처리해 줌
            # 예: (100 - 200) % 1000 = -100 % 1000 = 900
            expected_result = (a - b) % FIXED_Q
            
            a_hex = f"{a:0{hex_digits}x}"
            b_hex = f"{b:0{hex_digits}x}"
            q_hex = f"{FIXED_Q:0{hex_digits}x}"
            expected_hex = f"{expected_result:0{hex_digits}x}"
            
            f.write(f"{a_hex} {b_hex} {q_hex} {expected_hex}\n")

    print(f"✅ 성공! '{OUTPUT_FILE}' 파일에 {len(vectors)}개의 테스트벡터를 생성했습니다.")

# 스크립트 실행
if __name__ == "__main__":
    generate_mod_sub_vectors_fixed_q()