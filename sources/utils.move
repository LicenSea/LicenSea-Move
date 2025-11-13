module licensea::utils;

// 이 파일이 이 서비스의 정책에 따라 암호화된 콘텐츠인가?를 검증.
/// Returns true if `prefix` is a prefix of `word`.
public(package) fun is_prefix(prefix: vector<u8>, word: vector<u8>): bool {
    if (prefix.length() > word.length()) {
        return false
    };
    let mut i = 0;
    while (i < prefix.length()) {
        if (prefix[i] != word[i]) {
            return false
        };
        i = i + 1;
    };
    true
}
