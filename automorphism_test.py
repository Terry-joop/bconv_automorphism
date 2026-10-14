import sys

def calculate_and_save_full_permutation(n_val, r_val, base, filename):
    """
    r값을 입력받아 k를 계산한 후 (음수 r은 모듈러 역원으로 처리),
    Automorphism 순열 결과(i, i', s)를 계산하고 CSV 형식으로 파일에 저장합니다.
    """
    # 모듈러 곱셈 역원 계산을 위한 M 값
    m_val = 2 * n_val
    
    try:
        # r값으로부터 k값 계산
        if r_val >= 0:
            k_val = pow(base, r_val)
            print(f"r={r_val} >= 0 이므로, k = {base}^{r_val} = {k_val} (으)로 계산을 시작합니다.")
        else: # r이 음수일 경우
            # base의 모듈러 곱셈 역원을 먼저 찾음
            base_inv = pow(base, -1, m_val)
            # k = (base^-1)^(-r) mod M 을 계산
            k_val = pow(base_inv, -r_val, m_val)
            print(f"r={r_val} < 0 이므로, k = ({base}^-1)^({-r_val}) mod {m_val} = {k_val} (으)로 계산을 시작합니다.")

        with open(filename, "w") as f:
            f.write("original_i,permuted_i,s_value\n")
            
            for i in range(n_val):
                i_times_k = i * k_val
                permuted_i = i_times_k % n_val
                
                if i_times_k % m_val >= n_val:
                    s_value = 1
                else:
                    s_value = 0
                
                f.write(f"{i},{permuted_i},{s_value}\n")
        
        print(f"✅ 성공: 총 {n_val}개의 계산 결과가 '{filename}' 파일에 저장되었습니다.")

    except Exception as e:
        print(f"❌ 오류가 발생했습니다: {e}")

if __name__ == "__main__":
    N = 2**16
    r_val = -1  # r = -1 테스트
    base_val = 5
    output_filename = f"automorphism_sigma_{base_val}_r{r_val}_full_results.csv"

    calculate_and_save_full_permutation(N, r_val, base_val, output_filename)