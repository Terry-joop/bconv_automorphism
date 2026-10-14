import random

# --- Configuration ---
NUM_VECTORS = 100      # 생성할 테스트 벡터의 개수
N = 2**16              # Modulus (65536)
I_FILE = './au_test_vectors/i_vectors.txt'
K_FILE = './au_test_vectors/k_vectors.txt'
RESULT_FILE = './au_test_vectors/result_vectors.txt'
I_FILE_2 = '/mnt/c/Users/YEJIN/Desktop/split_llm_HW/au_test_vectors/i_vectors.txt'
K_FILE_2 = '/mnt/c/Users/YEJIN/Desktop/split_llm_HW/au_test_vectors/k_vectors.txt'
RESULT_FILE_2 = '/mnt/c/Users/YEJIN/Desktop/split_llm_HW/au_test_vectors/result_vectors.txt'


def generate_seperate_test_vectors():
    """
    i, k, result 값을 각각 별도의 hex 파일에 저장합니다.
    각 파일에는 한 줄에 하나의 값만 저장됩니다.
    """
    # 3개의 파일을 동시에 열기
    with open(I_FILE, 'w') as f_i, \
         open(K_FILE, 'w') as f_k, \
         open(RESULT_FILE, 'w') as f_result, \
         open(I_FILE_2, 'w') as f_i2, \
         open(K_FILE_2, 'w') as f_k2, \
         open(RESULT_FILE_2, 'w') as f_result2:

        for _ in range(NUM_VECTORS):
            # 1. 임의의 i, r 값 생성 (0 ~ 65535)
            i = random.randint(0, N - 1)
            # k를 생성하기 위한 r은 여전히 필요
            r = random.randint(0, N - 1)

            # 2. k 값 계산 (k = 5^r mod 2N)
            k = pow(5, r, 2*N)
            # k = 5**r

            # 3. 최종 결과 계산 (result = (i * k) mod N)
            result = (i * k) % N
            # 4. 각 파일에 16진수 값과 줄바꿈 문자를 저장
            f_i.write(f"{i:04x}\n")
            f_k.write(f"{k:04x}\n")
            f_result.write(f"{result:04x}\n")
            f_i2.write(f"{i:04x}\n")
            f_k2.write(f"{k:04x}\n")
            f_result2.write(f"{result:04x}\n")

    print(f"테스트 벡터 생성 완료:")
    print(f"-> 입력 i: '{I_FILE}'")
    print(f"-> 상수 k: '{K_FILE}'")
    print(f"-> 결과 result: '{RESULT_FILE}'")


# 함수 실행
generate_seperate_test_vectors()