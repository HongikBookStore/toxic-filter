import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import sys
import re

# 1. 저장된 모델과 토크나이저 로드
model_save_path = "./kcbert_model"
print(f"'{model_save_path}' 경로에서 모델과 토크나이저를 로드합니다...")

try:
    loaded_tokenizer = AutoTokenizer.from_pretrained(model_save_path)
    loaded_model = AutoModelForSequenceClassification.from_pretrained(model_save_path)
except Exception as e:
    print(f"모델 로드 중 오류 발생: {e}")
    print("이전에 모델을 성공적으로 훈련하고 저장했는지 확인해주세요.")
    sys.exit()

# GPU 사용 설정
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
loaded_model.to(device)
loaded_model.eval() # 평가 모드로 전환
print(f"모델이 {device}에 로드되었습니다.")

# 2. 예측 함수 정의 (라벨 해석 반전)
def predict_slang(text):
    # 한글이 포함되어 있는지 확인
    if not re.search(r"[\uac00-\ud7a3]", text):
        return "비악성 채팅", [0.0, 1.0]  # 한글이 없으면 비악성으로 처리
    
    inputs = loaded_tokenizer(text, return_tensors="pt", truncation=True, padding=True, max_length=128).to(device)
    with torch.no_grad():
        outputs = loaded_model(**inputs)
    
    logits = outputs.logits
    probabilities = torch.softmax(logits, dim=1)
    predicted_class_id = torch.argmax(probabilities, dim=1).item()
    
    # 원본 데이터셋: 0=악성, 1=정상
    # 원본 모델은 0을 악성으로, 1을 정상으로 학습했음
    # 따라서, 예측된 ID가 0이면 "악성", 1이면 "비악성"으로 해석
    result = "악성 채팅" if predicted_class_id == 0 else "비악성 채팅"
    
    return result, probabilities[0].tolist()

# 3. 간단한 예측 예시
print("\n간단한 예측 예시 (수정된 로직):")

test_sentences = [
    "일안하는 시간은 쉬고싶어서 그런게 아닐까",
    "예수 십새끼 개새끼 창녀아들 애비실종 가정교육 못받은 무뇌충",
    "나이쳐먹고 피시방가는 놈들은 대가리에 똥만찬 놈들임",
    "원 리더십, 원 메시지로 내부 결속을 더 강화하고 다시 교회로 모일수 있기를",
    "협박스킬은 패시브랑께",
    "this is english text",
    "this is english text with some special characters !@#$%",
]

for sentence in test_sentences:
    result, probs = predict_slang(sentence)
    # 확률은 [비악성 확률, 악성 확률] 순서로 가정하고 출력 (원본 데이터셋 기준)
    # 원본 모델은 0=악성, 1=정상으로 학습했으므로 probs[0]이 악성 확률, probs[1]이 정상 확률
    print(f"문장: '{sentence}' -> 예측: {result} (악성 확률: {probs[0]:.4f}, 정상 확률: {probs[1]:.4f})")
