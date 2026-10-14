import random

# --- 주요 설정 ---
WORD_WIDTH = 60  # Verilog 모듈의 WORD_WIDTH 파라미터와 일치
NUM_VECTORS = 256 # 생성할 총 벡터 개수
OUTPUT_FILE = "./mod_test_vectors/barrett_mult_vectors.txt" # 저장될 파일 이름

# =========================================================================
# 밀러-라빈 소수 판별 함수 🤓
# =========================================================================
def is_prime(n, k=20):
    """
    밀러-라빈 소수 판별법을 사용하여 n이 소수인지 테스트합니다.
    k는 테스트 반복 횟수로, 높을수록 정확도가 올라갑니다.
    """
    if n < 2:
        return False
    if n == 2 or n == 3:
        return True
    if n % 2 == 0:
        return False

    # n-1 = 2^s * d 로 분해
    s, d = 0, n - 1
    while d % 2 == 0:
        s += 1
        d //= 2

    for _ in range(k):
        a = random.randint(2, n - 2)
        x = pow(a, d, n)  # a^d mod n

        if x == 1 or x == n - 1:
            continue

        for _ in range(s - 1):
            x = pow(x, 2, n) # x^2 mod n
            if x == n - 1:
                break
        else:
            # 루프가 break 없이 끝나면 합성수
            return False
            
    # 모든 테스트를 통과하면 소수일 가능성이 매우 높음
    return True

# --- 메인 로직 ---
def generate_barrett_mult_vectors():
    """Barrett 모듈러 곱셈을 위한 테스트벡터를 생성합니다."""
    
    # WORD_WIDTH에 맞춰 16진수 자릿수 계산
    hex_digits_word = WORD_WIDTH // 4      # A, B, q, result (60-bit -> 15 hex)
    hex_digits_mu = (2 * WORD_WIDTH) // 4  # mu (120-bit -> 30 hex)
    
    max_val = (1 << WORD_WIDTH) - 1
    
    vectors = []
    
    # --- 1. 주요 경계값 테스트 케이스 (Edge Cases) 추가 ---
    # 경계값 테스트를 위한 q는 소수로 고정
    q_edge = 1152921504606846923 

    # Case 3: 제곱 (A = B)
    vectors.append({'a': 98765, 'b': 98765, 'q': q_edge})
    
    # Case 1: 0 곱하기 (결과 = 0)
    vectors.append({'a': 12345, 'b': 0, 'q': q_edge})
    
    # Case 2: 1 곱하기
    vectors.append({'a': 54321, 'b': 1, 'q': q_edge})
    
    
    # Case 4: (q-1) * (q-1) mod q = 1
    vectors.append({'a': q_edge - 1, 'b': q_edge - 1, 'q': q_edge})


    # --- 2. 48~60비트 소수 q를 사용한 랜덤 테스트 케이스 생성 ---
    num_random_vectors = NUM_VECTORS - len(vectors)
    print(f"Generating {num_random_vectors} random vectors with 48-60 bit prime q...")
    
    for i in range(num_random_vectors):
        # 소수를 찾을 때까지 루프
        while True:
            # 1. q의 범위를 48~60비트로 제한
            min_q = 1 << 58  # 48비트 숫자의 시작 (2^47)
            max_q = (1 << 60) - 1 # 60비트 숫자의 끝
            
            # 2. 범위 내에서 홀수 후보군 생성
            candidate_q = random.randint(min_q, max_q)
            if candidate_q % 2 == 0:
                candidate_q += 1

            # 3. 소수인지 판별하고, 소수이면 루프 탈출
            if is_prime(candidate_q):
                q = candidate_q
                print(f"  Found prime q for vector {len(vectors) + 1}: {q}")
                break
        
        a = random.randint(0, q - 1)
        b = random.randint(0, q - 1)
        
        vectors.append({'a': a, 'b': b, 'q': q})

    # --- 3. 파일에 16진수 형태로 저장 ---
    with open(OUTPUT_FILE, 'w') as f:

        for vec in vectors:
            a = vec['a']
            b = vec['b']
            q = vec['q']
            
            # mu = floor(2^(2*WORD_WIDTH) / q)
            mu = (1 << (2 * WORD_WIDTH)) // q
            
            # 기대 결과
            expected_result = (a * b) % q
            
            # 16진수 문자열로 변환
            a_hex = f"{a:0{hex_digits_word}x}"
            b_hex = f"{b:0{hex_digits_word}x}"
            q_hex = f"{q:0{hex_digits_word}x}"
            mu_hex = f"{mu:0{hex_digits_mu}x}" # mu는 2*WORD_WIDTH 비트
            expected_hex = f"{expected_result:0{hex_digits_word}x}"
            
            f.write(f"{a_hex} {b_hex} {q_hex} {mu_hex} {expected_hex}\n")

    print(f"\n✅ 성공! '{OUTPUT_FILE}' 파일에 {len(vectors)}개의 테스트벡터를 생성했습니다.")

# 스크립트 실행
if __name__ == "__main__":
    generate_barrett_mult_vectors()