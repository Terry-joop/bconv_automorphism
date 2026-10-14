import random
import math
import os

# ------------------------------------------------------------------------------
# 파라미터 설정 (Parameters Setup)
# ------------------------------------------------------------------------------
# 데이터 비트 폭 (DATA_WIDTH in Verilog)
DATA_WIDTH = 58
# Basis Q의 크기 파라미터 (l+1)
L = 8
NUM_Q = L + 1
# Basis P의 크기 파라미터 (k)
K = 11
NUM_P = K
# Shoup 곱셈을 위한 K 파라미터 (K_WIDTH in Verilog)
SHOUP_K_WIDTH = 58

# --- EDIT START ---
# 생성될 파일들을 저장할 디렉토리 리스트
OUTPUT_DIRS = ["cu_test_vectors", "/mnt/c/Users/YEJIN/Desktop/conv_unit/cu_test_vectors"]
# --- EDIT END ---

# ------------------------------------------------------------------------------
# 헬퍼 함수 (Helper Functions)
# ------------------------------------------------------------------------------

def is_prime(n, k=5):
    """Miller-Rabin 소수 판별법"""
    if n < 2:
        return False
    if n == 2 or n == 3:
        return True
    if n % 2 == 0 or n % 3 == 0:
        return False

    d = n - 1
    s = 0
    while d % 2 == 0:
        d //= 2
        s += 1

    for _ in range(k):
        a = random.randrange(2, n - 1)
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(s - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True

def generate_prime(bits):
    """지정된 비트 수의 소수를 생성"""
    while True:
        p = random.getrandbits(bits)
        # 최상위 비트가 1이 되도록 보장
        p |= (1 << (bits - 1))
        # 홀수로 만듦
        p |= 1
        if is_prime(p):
            return p

def calculate_shoup_z_pre(ratio, q, k_width):
    """Shoup 곱셈을 위한 사전 계산 값 z_pre를 계산"""
    # z_pre = floor(ratio * 2^K / q)
    # return (ratio << k_width) // q
    return (ratio * (1 << k_width)) // q

def write_hex_to_file(filename, data, item_width_bits):
    """데이터 리스트를 16진수 포맷으로 여러 디렉토리에 저장"""
    hex_width = math.ceil(item_width_bits / 4)
    # zfill을 사용하여 0으로 너비를 맞춤
    formatter = f"{{:0{hex_width}x}}"
    
    # --- EDIT START ---
    # 지정된 모든 출력 디렉토리에 파일을 저장
    for directory in OUTPUT_DIRS:
        filepath = os.path.join(directory, filename)
        with open(filepath, 'w') as f:
            if isinstance(data, list):
                if any(isinstance(i, list) for i in data): # 2D list
                    for row in data:
                        f.write(" ".join([formatter.format(item) for item in row]) + '\n')
                else: # 1D list
                    for item in data:
                        f.write(formatter.format(item) + '\n')
            else: # Single value
                f.write(formatter.format(data) + '\n')
    # --- EDIT END ---
    print(f"✅ Created test vector file: {filename} in {', '.join(OUTPUT_DIRS)}")


# ------------------------------------------------------------------------------
# 메인 로직 (Main Logic)
# ------------------------------------------------------------------------------

def main():
    """테스트벡터 생성 메인 함수"""
    print("--- Conversion Unit (CU) Test Vector Generator ---")

    # --- EDIT START ---
    # 모든 출력 디렉토리 생성
    for directory in OUTPUT_DIRS:
        if not os.path.exists(directory):
            os.makedirs(directory)
            print(f"Created output directory: {directory}")
    # --- EDIT END ---

    # 1. Basis Q, P 생성 (Generate Bases)
    print("\nStep 1: Generating prime numbers for Basis Q and P...")
    basis_q = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_Q)], reverse=True)
    basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)
    
    # 중복 소수 방지
    while len(set(basis_q) & set(basis_p)) > 0:
        print("Warning: Overlap found between basis_q and basis_p. Regenerating basis_p...")
        basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)

    write_hex_to_file("basis_q.txt", basis_q, DATA_WIDTH)
    write_hex_to_file("basis_p.txt", basis_p, DATA_WIDTH)

    # 2. 입력 계수 생성 (Generate Input Coefficient)
    print("\nStep 2: Generating random input coefficient...")
    q_total = math.prod(basis_q)
    # 변환할 원본 값 x 생성 (x < q_total)
    x_original = random.randint(0, q_total - 1)
    
    # x를 Basis Q로 표현
    coeff_q = [x_original % q for q in basis_q]
    write_hex_to_file("coeff_q.txt", coeff_q, DATA_WIDTH)

    # 3. 기저 변환 파라미터 계산 (Calculate Conversion Parameters)
    print("\nStep 3: Calculating parameters for basis conversion...")
    q_hat = [q_total // q for q in basis_q]
    q_hat_inv = [pow(h, -1, q) for h, q in zip(q_hat, basis_q)]
    
    # q_hat_mod_p[j][i] = q_hat[i] mod p[j]
    # 행렬 구조를 (NUM_P, NUM_Q)로 변경
    q_hat_mod_p = [[h % p for h in q_hat] for p in basis_p]

    write_hex_to_file("q_hat_inv.txt", q_hat_inv, DATA_WIDTH)
    write_hex_to_file("q_hat_mod_p.txt", q_hat_mod_p, DATA_WIDTH)

    # 4. Shoup 곱셈 파라미터 계산 (Calculate Shoup Precomputed Ratios)
    print("\nStep 4: Calculating precomputed values for Shoup multiplication...")
    # Step 1: (coeff_i * q_hat_inv_i) mod q_i
    # ratio = q_hat_inv_i, q = q_i
    shoup_z_pre_step1 = [calculate_shoup_z_pre(ratio, q, SHOUP_K_WIDTH) 
                         for ratio, q in zip(q_hat_inv, basis_q)]
    
    # Step 2: (gamma_i * q_hat_mod_p_j) mod p_j
    # ratio = q_hat_mod_p_ij, q = p_j
    # 변경된 q_hat_mod_p 구조에 맞게 수정
    # 각 행(j)에 대해, 해당 행의 모듈러스인 basis_p[j]를 사용하여 z_pre 계산
    shoup_z_pre_step2 = [[calculate_shoup_z_pre(ratio_val, basis_p[j], SHOUP_K_WIDTH)
                          for ratio_val in ratio_row]
                         for j, ratio_row in enumerate(q_hat_mod_p)]

    write_hex_to_file("shoup_z_pre_step1.txt", shoup_z_pre_step1, DATA_WIDTH)
    write_hex_to_file("shoup_z_pre_step2.txt", shoup_z_pre_step2, DATA_WIDTH)

    # 5. 기저 변환 시뮬레이션 (Simulate Basis Conversion)
    print("\nStep 5: Simulating the conversion process...")
    # Step 1 결과 계산: gamma_i = (coeff_i * q_hat_inv_i) mod q_i
    step1_results = [(c * inv) % q for c, inv, q in zip(coeff_q, q_hat_inv, basis_q)]
    write_hex_to_file("step1_results.txt", step1_results, DATA_WIDTH)
    print("  -> Step 1 simulation complete.")

    # Step 2 결과 계산 (최종 변환)
    final_results_p = []
    step2_mult = []
    step2_accum = []
    for j in range(NUM_P):
        p_j = basis_p[j]
        accumulator = 0
        for i in range(NUM_Q):
            gamma_i = step1_results[i]
            # 변경된 행렬 구조에 맞게 인덱싱 수정 (i, j -> j, i)
            q_hat_mod_p_ij = q_hat_mod_p[j][i]
            term = (gamma_i * q_hat_mod_p_ij) % p_j
            accumulator = (accumulator + term) % p_j
            if j==16:
                step2_mult.append(term)
                step2_accum.append(accumulator)
        final_results_p.append(accumulator)
    
    # final_results_p_2 = []
    # for j in range(NUM_P):
    #     p_j = basis_p[j]
    #     accumulator = 0
    #     for i in range(NUM_Q):
    #         gamma_i = step1_results[i]
    #         q_hat_mod_p_ij = q_hat[i]
    #         term = (gamma_i * q_hat_mod_p_ij) 
    #         accumulator = (accumulator + term) 
    #     # accumulator = accumulator % q_total
    #     accumulator = accumulator % p_j
    #     final_results_p_2.append(accumulator)
    
    write_hex_to_file("final_conversion_results.txt", final_results_p, DATA_WIDTH)
    # write_hex_to_file("final_conversion_results_2.txt", final_results_p_2, DATA_WIDTH)
    write_hex_to_file("step2_mult.txt", step2_mult, DATA_WIDTH)
    write_hex_to_file("step2_accum.txt", step2_accum, DATA_WIDTH)

    print("  -> Step 2 simulation (final conversion) complete.")

    # 6. Golden Reference 검증 (Verify with Golden Reference)
    print("\nStep 6: Verifying results with golden reference...")
    golden_results_p = [x_original % p for p in basis_p]
    write_hex_to_file("golden_results_p.txt", golden_results_p, DATA_WIDTH)
    
    # assert final_results_p == golden_results_p, "Error: Simulation result does not match the golden reference!"
    
    # print("  -> Verification successful! Simulated results match the golden reference.")
    # 오차 계산
    errors = []
    for j in range(NUM_P):
        p_j = basis_p[j]
        diff = (final_results_p[j] - golden_results_p[j]) % p_j
        errors.append(diff)

    # 최대/평균 오차 확인
    max_error = max(errors)
    avg_error = sum(errors) / len(errors)

    print("Errors per modulus p_j:", errors)
    print(f"Max error = {max_error}")
    print(f"Average error = {avg_error}")

    # assert 대신 오차 출력만
    if all(e == 0 for e in errors):
        print("  -> Perfect match with golden reference!")
    else:
        print("  -> Non-zero errors detected (expected in approximate algorithm).")

        print("\n--- All test vectors have been generated successfully! ---")


if __name__ == "__main__":
    main()





















# import random
# import math
# import sys

# # ==============================================================================
# # Script Configuration
# # ==============================================================================

# # RNS-CKKS 파라미터 설정
# # Basis Q의 크기 = L + 1
# L = 12
# # Basis P의 크기 = K
# K = 17
# # 소수 모듈러스의 비트 크기
# MOD_BIT_SIZE = 58
# # Shoup 곱셈기의 K 파라미터 비트 크기 (일반적으로 MOD_BIT_SIZE와 동일)
# SHOUP_K_BIT_SIZE = 58

# # 생성할 테스트 벡터의 개수
# NUM_TEST_VECTORS = 1

# # ==============================================================================
# # Helper Functions
# # ==============================================================================

# def is_prime(n, k=5):
#     """Miller-Rabin 소수 판별법"""
#     if n < 2:
#         return False
#     if n == 2 or n == 3:
#         return True
#     if n % 2 == 0 or n % 3 == 0:
#         return False
    
#     d = n - 1
#     s = 0
#     while d % 2 == 0:
#         d //= 2
#         s += 1

#     for _ in range(k):
#         a = random.randrange(2, n - 1)
#         x = pow(a, d, n)
#         if x == 1 or x == n - 1:
#             continue
#         for _ in range(s - 1):
#             x = pow(x, 2, n)
#             if x == n - 1:
#                 break
#         else:
#             return False
#     return True

# def generate_prime(bit_size):
#     """주어진 비트 크기의 소수를 생성합니다."""
#     while True:
#         p = random.getrandbits(bit_size)
#         # 최상위 비트가 1이 되도록 하여 비트 크기를 보장합니다.
#         p |= (1 << (bit_size - 1))
#         # 홀수로 만듭니다.
#         p |= 1
#         if is_prime(p):
#             return p

# def write_hex_to_file(filename, data_list, bits):
#     """
#     정수 리스트를 16진수 형식으로 파일에 씁니다.
#     각 값은 한 줄에 하나씩 기록됩니다.
#     """
#     hex_width = math.ceil(bits / 4)
#     # 2D 리스트를 1D로 변환
#     if any(isinstance(el, list) for el in data_list):
#         data_list = [item for sublist in data_list for item in sublist]
        
#     try:
#         with open(filename, 'w') as f:
#             for item in data_list:
#                 # f-string을 사용하여 0으로 채워진 16진수 문자열 생성
#                 f.write(f'{item:0{hex_width}x}\n')
#         print(f"Successfully wrote to {filename}")
#     except IOError as e:
#         print(f"Error writing to file {filename}: {e}")

# # ==============================================================================
# # Main Test Vector Generation Logic
# # ==============================================================================

# def generate_vectors():
#     """테스트 벡터를 생성하고 파일에 저장하는 메인 함수"""
    
#     print("--- RNS Basis Conversion Test Vector Generation ---")
#     print(f"Parameters: l={L}, k={K}, modulus_bits={MOD_BIT_SIZE}")
#     print("-" * 50)

#     # 1. Basis Q와 P를 위한 소수 생성
#     # ------------------------------------------------
#     print("Step 1: Generating prime moduli for Basis Q and P...")
#     num_q = L + 1
#     num_p = K
    
#     random.seed(2025)
    
#     # 중복을 피하기 위해 집합(set) 사용
#     primes = set()
#     while len(primes) < num_q + num_p:
#         primes.add(generate_prime(MOD_BIT_SIZE))
    
#     prime_list = list(primes)
#     basis_q = prime_list[:num_q]
#     basis_p = prime_list[num_q:]
    
#     print(f"Generated {num_q} primes for Basis Q.")
#     print(f"Generated {num_p} primes for Basis P.")
#     print("-" * 50)

#     # 2. CRT(중국인의 나머지 정리)를 위한 사전 계산 값 생성
#     # ------------------------------------------------
#     print("Step 2: Calculating pre-computed values for CRT...")
    
#     # Q_product = q0 * q1 * ... * q_l
#     Q_product = math.prod(basis_q)

#     # q_hat_i = Q_product / q_i
#     # q_hat_inv_i = (q_hat_i)^-1 mod q_i
#     q_hat_list = [Q_product // q for q in basis_q]
#     # Python 3.8+의 pow(base, exp, mod)는 모듈러 역원을 직접 계산할 수 있습니다.
#     q_hat_inv_list = [pow(q_hat, -1, q) for q_hat, q in zip(q_hat_list, basis_q)]

#     # q_hat_mod_p_ij = q_hat_i mod p_j
#     # q_hat_mod_p_matrix = [[q_hat % p for p in basis_p] for q_hat in q_hat_list]
#     q_hat_mod_p_matrix = [[q_hat % p for q_hat in q_hat_list] for p in basis_p]
    
#     print("Calculated q_hat_inv and q_hat_mod_p values.")
#     print("-" * 50)

#     # 3. Shoup 곱셈을 위한 사전 계산 값 생성
#     # ------------------------------------------------
#     print("Step 3: Calculating pre-computed values for Shoup multiplication...")
#     # ratio_precomp = floor(2^k / q)
#     # CU 모듈은 각 연산마다 다른 q (q_in)를 입력받으므로, basis_q의 모든 소수에 대해 생성합니다.
#     shoup_ratios_q = [(1 << SHOUP_K_BIT_SIZE) // q for q in basis_q]
#     shoup_ratios_p = [(1 << SHOUP_K_BIT_SIZE) // p for p in basis_p] 
#     print("Calculated Shoup ratios.")
#     print("-" * 50)

#     # 4. 임의의 입력 데이터 생성 및 골든 모델 실행
#     # ------------------------------------------------
#     for i in range(NUM_TEST_VECTORS):
#         print(f"--- Generating Vector Set {i+1}/{NUM_TEST_VECTORS} ---")
        
#         # Basis Q의 범위를 벗어나지 않는 임의의 큰 정수 'x'를 생성
        
#         x = random.randint(0, Q_product - 1)
#         print(f"Generated random integer x = {x} (mod Q_product = {Q_product})")

#         # 'x'를 Basis Q로 표현 (이것이 CU의 입력 coeff가 됨)
#         coeffs_q = [x % q for q in basis_q]

#         # --- 골든 모델: RNS 기수 변환 시뮬레이션 ---
        
#         # Step 1 결과 계산: gamma_i = (coeff_i * q_hat_inv_i) mod q_i
#         # 이 값들은 CU 내부 버퍼에 저장됩니다.
#         step1_results = [(c * inv) % q for c, inv, q in zip(coeffs_q, q_hat_inv_list, basis_q)]

#         # 최종 결과 계산: y_j = (SUM_i [gamma_i * (q_hat_i mod p_j)]) mod p_j
#         final_results_p = []
#         for j, p_j in enumerate(basis_p):
#             sum_val = 0
#             for i_idx in range(num_q):
#                 gamma_i = step1_results[i_idx]
#                 # q_hat_mod_p_ij = q_hat_mod_p_matrix[i_idx][j]
#                 q_hat_mod_p_ij = q_hat_mod_p_matrix[j][i_idx]
#                 # ✨ FIX: 하드웨어와 동일하게 매 연산마다 모듈러를 적용합니다.
#                 term = (gamma_i * q_hat_mod_p_ij)
#                 sum_val = (sum_val + term) % p_j
#             final_results_p.append(sum_val)

#         # (검증) 골든 모델의 결과가 실제 값과 일치하는지 확인
#         expected_p = [x % p for p in basis_p]
#         # assert final_results_p == expected_p, "Golden model calculation is incorrect!"
#         print("Golden model calculation verified successfully.")

#         # 5. 모든 벡터를 16진수 텍스트 파일로 저장
#         # ------------------------------------------------
#         print("Step 4: Writing all vectors to .txt files...")
        
#         # 파일 이름에 인덱스 추가 (여러 세트 생성 시)
#         suffix = f"_{i}" if NUM_TEST_VECTORS > 1 else ""

#         # ✨ UPDATE: basis_q와 basis_p 파일 생성 추가
#         write_hex_to_file(f"basis_q{suffix}.txt", basis_q, MOD_BIT_SIZE)
#         write_hex_to_file(f"basis_p{suffix}.txt", basis_p, MOD_BIT_SIZE)
        
#         write_hex_to_file(f"coeff_q{suffix}.txt", coeffs_q, MOD_BIT_SIZE)
#         write_hex_to_file(f"q_hat_inv{suffix}.txt", q_hat_inv_list, MOD_BIT_SIZE)
#         write_hex_to_file(f"q_hat_mod_p{suffix}.txt", q_hat_mod_p_matrix[0], MOD_BIT_SIZE)
#         write_hex_to_file(f"shoup_ratio_q{suffix}.txt", shoup_ratios_q, MOD_BIT_SIZE)
#         write_hex_to_file(f"shoup_ratio_p{suffix}.txt", shoup_ratios_p, MOD_BIT_SIZE)
        
#         write_hex_to_file(f"step1_results_golden{suffix}.txt", step1_results, MOD_BIT_SIZE)
#         write_hex_to_file(f"final_results_p_golden{suffix}.txt", final_results_p, MOD_BIT_SIZE)
        
#         print("-" * 50)

# if __name__ == '__main__':
#     # Python 버전 확인 (3.8 이상 권장)
#     if sys.version_info < (3, 8):
#         sys.exit("This script requires Python 3.8 or higher for modular inverse calculation.")
#     generate_vectors()
#     print("All test vectors generated successfully!")

