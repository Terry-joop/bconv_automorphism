import random
import math
import os
import time # 실행 시간 측정을 위해 추가

# ------------------------------------------------------------------------------
# 파라미터 설정 (Parameters Setup)
# ------------------------------------------------------------------------------
# 데이터 비트 폭 (DATA_WIDTH in Verilog)
DATA_WIDTH = 60
# Basis Q의 크기 파라미터 (l+1)
L = 12
NUM_Q = L + 1
# Basis P의 크기 파라미터 (k)
K = 5
NUM_P = K
# Shoup 곱셈을 위한 K 파라미터 (K_WIDTH in Verilog)
SHOUP_K_WIDTH = 60
# --- 테스트 케이스 개수 설정 ---
NUM_TESTS = 2**16 # 65,536개

# 생성될 파일들을 저장할 디렉토리 리스트
OUTPUT_DIRS = ["/home/jinjin/Split_LLM/bconv_test_vectors"]

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
        p |= (1 << (bits - 1))
        p |= 1
        if is_prime(p):
            return p

def calculate_shoup_z_pre(ratio, q, k_width):
    """Shoup 곱셈을 위한 사전 계산 값 z_pre를 계산"""
    return (ratio * (1 << k_width)) // q

def write_hex_to_file(filename, data, item_width_bits):
    """데이터 리스트를 16진수 포맷으로 여러 디렉토리에 저장 (행렬 전치 기능 추가)"""
    hex_width = math.ceil(item_width_bits / 4)
    formatter = f"{{:0{hex_width}x}}"
    
    for directory in OUTPUT_DIRS:
        filepath = os.path.join(directory, filename)
        with open(filepath, 'w') as f:
            if isinstance(data, list):
                if any(isinstance(i, list) for i in data): # 2D list (여러 테스트 케이스)
                    # 행과 열을 바꿔서(전치하여) 저장합니다.
                    transposed_data = list(zip(*data))
                    for row in transposed_data:
                        f.write(" ".join([formatter.format(item) for item in row]) + '\n')
                else: # 1D list (파라미터 등)
                    for item in data:
                        f.write(formatter.format(item) + '\n')
            else: # Single value
                f.write(formatter.format(data) + '\n')
    print(f"✅ Created test vector file: {filename} in {', '.join(OUTPUT_DIRS)}")


# ------------------------------------------------------------------------------
# 메인 로직 (Main Logic)
# ------------------------------------------------------------------------------

def main():
    """2^16개의 계수에 대한 테스트벡터 생성 메인 함수"""
    print(f"--- CU Test Vector Generator for {NUM_TESTS} Coefficients ---")
    start_time = time.time()

    # 모든 출력 디렉토리 생성
    for directory in OUTPUT_DIRS:
        if not os.path.exists(directory):
            os.makedirs(directory)
            print(f"Created output directory: {directory}")

    # ==========================================================================
    # STEP 1: 설정 (Setup Phase - 한 번만 실행)
    # ==========================================================================
    print("\n--- Running Setup Phase (One-Time Calculations) ---")
    
    # 1. Basis Q, P 생성
    print("Step 1.1: Generating prime numbers for Basis Q and P...")
    basis_q = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_Q)], reverse=True)
    basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)
    
    while len(set(basis_q) & set(basis_p)) > 0:
        print("Warning: Overlap found. Regenerating basis_p...")
        basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)

    write_hex_to_file("basis_q.txt", basis_q, DATA_WIDTH)
    write_hex_to_file("basis_p.txt", basis_p, DATA_WIDTH)

    # 2. 기저 변환 파라미터 계산
    print("Step 1.2: Calculating parameters for basis conversion...")
    q_total = math.prod(basis_q)
    q_hat = [q_total // q for q in basis_q]
    q_hat_inv = [pow(h, -1, q) for h, q in zip(q_hat, basis_q)]
    q_hat_mod_p = [[h % p for h in q_hat] for p in basis_p]
    

    write_hex_to_file("q_hat_inv.txt", q_hat_inv, DATA_WIDTH)
    write_hex_to_file("q_hat_mod_p.txt", [list(row) for row in zip(*q_hat_mod_p)], DATA_WIDTH)

    # ✨✨✨ --- EDIT START: mu 값 계산 및 저장 로직 추가 --- ✨✨✨
    # 3. Barrett Reduction을 위한 mu 파라미터 계산
    print("Step 1.3: Calculating mu parameters for Barrett reduction...")
    # mu = floor(2^(2*DATA_WIDTH) / q)
    mu_q = [(1 << (2 * DATA_WIDTH)) // q for q in basis_q]
    mu_p = [(1 << (2 * DATA_WIDTH)) // p for p in basis_p]
    # mu 값은 (2 * DATA_WIDTH) 비트 폭을 가질 수 있으므로 파일 저장 시 비트 폭을 2배로 설정
    write_hex_to_file("mu_q.txt", mu_q, 64)
    write_hex_to_file("mu_p.txt", mu_p, 64)
    # ✨✨✨ --- EDIT END --- ✨✨✨

    # ==========================================================================
    # STEP 2: 테스트 케이스 생성 (Test Case Generation - 루프 실행)
    # ==========================================================================
    print(f"\n--- Running Test Case Generation Phase ({NUM_TESTS} iterations) ---")
    
    # 결과를 저장할 리스트 초기화
    all_coeffs_q = []
    all_step1_results = []
    all_final_results = []
    all_golden_results = []

    for i in range(NUM_TESTS):
        # 진행 상황 표시 (4096번 마다)
        if (i + 1) % 4096 == 0:
            print(f"   -> Generating test case {i + 1}/{NUM_TESTS}...")

        # 1. 새로운 입력 계수 생성
        x_original = random.randint(0, q_total - 1)
        current_coeff_q = [x_original % q for q in basis_q]
        all_coeffs_q.append(current_coeff_q)

        # 2. 기저 변환 시뮬레이션
        # Step 1 결과: gamma_i = (coeff_i * q_hat_inv_i) mod q_i
        current_step1_results = [(c * inv) % q for c, inv, q in zip(current_coeff_q, q_hat_inv, basis_q)]
        all_step1_results.append(current_step1_results)

        # Step 2 결과 (최종 변환)
        current_final_results_p = []
        for j in range(NUM_P):
            p_j = basis_p[j]
            accumulator = 0
            for k in range(NUM_Q):
                gamma_k = current_step1_results[k]
                q_hat_mod_p_jk = q_hat_mod_p[j][k]
                term = (gamma_k * q_hat_mod_p_jk) % p_j
                accumulator = (accumulator + term) % p_j
            current_final_results_p.append(accumulator)
        all_final_results.append(current_final_results_p)
        
        # 3. Golden Reference 생성
        current_golden_results = [x_original % p for p in basis_p]
        all_golden_results.append(current_golden_results)

    print("\n--- All test cases generated. Now writing to files... ---")

    # ==========================================================================
    # STEP 3: 파일 쓰기 (File Writing Phase)
    # ==========================================================================
    write_hex_to_file("coeffs_q.txt", all_coeffs_q, DATA_WIDTH)
    write_hex_to_file("step1_results.txt", all_step1_results, DATA_WIDTH)
    write_hex_to_file("final_conversion_results.txt", all_final_results, DATA_WIDTH)
    write_hex_to_file("golden_results_p.txt", all_golden_results, DATA_WIDTH)
    
    end_time = time.time()
    print(f"\n--- ✅ All {NUM_TESTS} test vectors have been generated successfully! ---")
    print(f"Total execution time: {end_time - start_time:.2f} seconds.")


if __name__ == "__main__":
    main()












# import random
# import math
# import os
# import time # 실행 시간 측정을 위해 추가

# # ------------------------------------------------------------------------------
# # 파라미터 설정 (Parameters Setup)
# # ------------------------------------------------------------------------------
# # 데이터 비트 폭 (DATA_WIDTH in Verilog)
# DATA_WIDTH = 58
# # Basis Q의 크기 파라미터 (l+1)
# L = 12
# NUM_Q = L + 1
# # Basis P의 크기 파라미터 (k)
# K = 17
# NUM_P = K
# # Shoup 곱셈을 위한 K 파라미터 (K_WIDTH in Verilog)
# SHOUP_K_WIDTH = 58
# # --- ✨ EDIT START: 테스트 케이스 개수 설정 ---
# NUM_TESTS = 2**16 # 65,536개
# # --- ✨ EDIT END ---

# # 생성될 파일들을 저장할 디렉토리 리스트
# OUTPUT_DIRS = ["cu_test_vectors_full", "/mnt/c/Users/YEJIN/Desktop/split_llm_HW/cu_test_vectors_full"]

# # ------------------------------------------------------------------------------
# # 헬퍼 함수 (Helper Functions) - 기존과 동일
# # ------------------------------------------------------------------------------

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

# def generate_prime(bits):
#     """지정된 비트 수의 소수를 생성"""
#     while True:
#         p = random.getrandbits(bits)
#         p |= (1 << (bits - 1))
#         p |= 1
#         if is_prime(p):
#             return p

# def calculate_shoup_z_pre(ratio, q, k_width):
#     """Shoup 곱셈을 위한 사전 계산 값 z_pre를 계산"""
#     return (ratio * (1 << k_width)) // q

# def write_hex_to_file(filename, data, item_width_bits):
#     """데이터 리스트를 16진수 포맷으로 여러 디렉토리에 저장"""
#     hex_width = math.ceil(item_width_bits / 4)
#     formatter = f"{{:0{hex_width}x}}"
    
#     for directory in OUTPUT_DIRS:
#         filepath = os.path.join(directory, filename)
#         with open(filepath, 'w') as f:
#             if isinstance(data, list):
#                 if any(isinstance(i, list) for i in data): # 2D list (여러 테스트 케이스)
#                     for row in data:
#                         f.write(" ".join([formatter.format(item) for item in row]) + '\n')
#                 else: # 1D list (파라미터 등)
#                     for item in data:
#                         f.write(formatter.format(item) + '\n')
#             else: # Single value
#                 f.write(formatter.format(data) + '\n')
#     print(f"✅ Created test vector file: {filename} in {', '.join(OUTPUT_DIRS)}")


# # ------------------------------------------------------------------------------
# # 메인 로직 (Main Logic) - ✨ 수정된 부분 ✨
# # ------------------------------------------------------------------------------

# def main():
#     """2^16개의 계수에 대한 테스트벡터 생성 메인 함수"""
#     print(f"--- CU Test Vector Generator for {NUM_TESTS} Coefficients ---")
#     start_time = time.time()

#     # 모든 출력 디렉토리 생성
#     for directory in OUTPUT_DIRS:
#         if not os.path.exists(directory):
#             os.makedirs(directory)
#             print(f"Created output directory: {directory}")

#     # ==========================================================================
#     # STEP 1: 설정 (Setup Phase - 한 번만 실행)
#     # ==========================================================================
#     print("\n--- Running Setup Phase (One-Time Calculations) ---")
    
#     # 1. Basis Q, P 생성
#     print("Step 1.1: Generating prime numbers for Basis Q and P...")
#     basis_q = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_Q)], reverse=True)
#     basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)
    
#     while len(set(basis_q) & set(basis_p)) > 0:
#         print("Warning: Overlap found. Regenerating basis_p...")
#         basis_p = sorted([generate_prime(DATA_WIDTH) for _ in range(NUM_P)], reverse=True)

#     write_hex_to_file("basis_q.txt", basis_q, DATA_WIDTH)
#     write_hex_to_file("basis_p.txt", basis_p, DATA_WIDTH)

#     # 2. 기저 변환 파라미터 계산
#     print("Step 1.2: Calculating parameters for basis conversion...")
#     q_total = math.prod(basis_q)
#     q_hat = [q_total // q for q in basis_q]
#     q_hat_inv = [pow(h, -1, q) for h, q in zip(q_hat, basis_q)]
#     q_hat_mod_p = [[h % p for h in q_hat] for p in basis_p]

#     write_hex_to_file("q_hat_inv.txt", q_hat_inv, DATA_WIDTH)
#     write_hex_to_file("q_hat_mod_p.txt", q_hat_mod_p, DATA_WIDTH)

#     # 3. Shoup 곱셈 파라미터 계산
#     print("Step 1.3: Calculating precomputed values for Shoup multiplication...")
#     shoup_z_pre_step1 = [calculate_shoup_z_pre(ratio, q, SHOUP_K_WIDTH) 
#                          for ratio, q in zip(q_hat_inv, basis_q)]
#     shoup_z_pre_step2 = [[calculate_shoup_z_pre(ratio_val, basis_p[j], SHOUP_K_WIDTH)
#                           for ratio_val in ratio_row]
#                          for j, ratio_row in enumerate(q_hat_mod_p)]

#     write_hex_to_file("shoup_z_pre_step1.txt", shoup_z_pre_step1, DATA_WIDTH)
#     write_hex_to_file("shoup_z_pre_step2.txt", shoup_z_pre_step2, DATA_WIDTH)

#     # ==========================================================================
#     # STEP 2: 테스트 케이스 생성 (Test Case Generation - 루프 실행)
#     # ==========================================================================
#     print(f"\n--- Running Test Case Generation Phase ({NUM_TESTS} iterations) ---")
    
#     # 결과를 저장할 리스트 초기화
#     all_coeffs_q = []
#     all_step1_results = []
#     all_final_results = []
#     all_golden_results = []

#     for i in range(NUM_TESTS):
#         # 진행 상황 표시 (4096번 마다)
#         if (i + 1) % 4096 == 0:
#             print(f"  -> Generating test case {i + 1}/{NUM_TESTS}...")

#         # 1. 새로운 입력 계수 생성
#         x_original = random.randint(0, q_total - 1)
#         current_coeff_q = [x_original % q for q in basis_q]
#         all_coeffs_q.append(current_coeff_q)

#         # 2. 기저 변환 시뮬레이션
#         # Step 1 결과: gamma_i = (coeff_i * q_hat_inv_i) mod q_i
#         current_step1_results = [(c * inv) % q for c, inv, q in zip(current_coeff_q, q_hat_inv, basis_q)]
#         all_step1_results.append(current_step1_results)

#         # Step 2 결과 (최종 변환)
#         current_final_results_p = []
#         for j in range(NUM_P):
#             p_j = basis_p[j]
#             accumulator = 0
#             for k in range(NUM_Q):
#                 gamma_k = current_step1_results[k]
#                 q_hat_mod_p_jk = q_hat_mod_p[j][k]
#                 term = (gamma_k * q_hat_mod_p_jk) % p_j
#                 accumulator = (accumulator + term) % p_j
#             current_final_results_p.append(accumulator)
#         all_final_results.append(current_final_results_p)
        
#         # 3. Golden Reference 생성
#         current_golden_results = [x_original % p for p in basis_p]
#         all_golden_results.append(current_golden_results)

#         # (선택) 각 단계에서 즉시 검증
#         # assert current_final_results_p == current_golden_results, f"Error at test case {i}: Simulation mismatch!"

#     print("\n--- All test cases generated. Now writing to files... ---")

#     # ==========================================================================
#     # STEP 3: 파일 쓰기 (File Writing Phase)
#     # ==========================================================================
#     # 루프에서 누적된 모든 결과를 파일에 저장
#     write_hex_to_file("coeffs_q.txt", all_coeffs_q, DATA_WIDTH)
#     write_hex_to_file("step1_results.txt", all_step1_results, DATA_WIDTH)
#     write_hex_to_file("final_conversion_results.txt", all_final_results, DATA_WIDTH)
#     write_hex_to_file("golden_results_p.txt", all_golden_results, DATA_WIDTH)
    
#     end_time = time.time()
#     print(f"\n--- ✅ All {NUM_TESTS} test vectors have been generated successfully! ---")
#     print(f"Total execution time: {end_time - start_time:.2f} seconds.")


# if __name__ == "__main__":
#     main()