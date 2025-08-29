import os
import torch
from flask import Flask, request, jsonify
from flask_cors import CORS
from transformers import AutoTokenizer, AutoModelForSequenceClassification


app = Flask(__name__)

# --- CORS 설정 (환경변수로 제어) ---
# CORS_ORIGINS: 콤마구분 허용 오리진 목록. 미설정 시 전체 허용("*")
_cors_origins = os.environ.get("CORS_ORIGINS")
if _cors_origins:
    allowed = [o.strip() for o in _cors_origins.split(",") if o.strip()]
    CORS(app, resources={r"/predict": {"origins": allowed}, r"/health": {"origins": "*"}})
else:
    CORS(app)


# --- 환경 변수 및 상수 ---
MODEL_PATH = os.environ.get("MODEL_PATH", "./kcbert_slang_filter_model")
MALICIOUS_THRESHOLD_CERTAIN = float(os.environ.get("MALICIOUS_THRESHOLD_CERTAIN", 0.999))
MALICIOUS_THRESHOLD_AMBIGUOUS = float(os.environ.get("MALICIOUS_THRESHOLD_AMBIGUOUS", 0.9))
API_KEY = os.environ.get("API_KEY")  # 선택: 설정 시 X-API-Key 헤더 검증

# Torch 스레드 튜닝(선택)
try:
    intra = os.environ.get("TORCH_INTRA_OP_THREADS")
    inter = os.environ.get("TORCH_INTER_OP_THREADS")
    if intra:
        torch.set_num_threads(int(intra))
    if inter:
        torch.set_num_interop_threads(int(inter))
except Exception:
    # 조용히 무시(환경에 따라 미지원일 수 있음)
    pass


# --- 모델 로드 (최초 1회) ---
tokenizer = None
model = None
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


def load_model():
    global tokenizer, model
    try:
        tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH)
        model = AutoModelForSequenceClassification.from_pretrained(MODEL_PATH)
        model.to(device)
        model.eval()
        app.logger.info("Model loaded successfully at %s", MODEL_PATH)
    except Exception as e:
        app.logger.exception("Failed to load model from %s: %s", MODEL_PATH, e)
        tokenizer = None
        model = None


load_model()


@app.before_request
def check_api_key():
    # API_KEY가 설정된 경우에만 검사
    if API_KEY:
        provided = request.headers.get("X-API-Key")
        if not provided or provided != API_KEY:
            return jsonify({"error": "Unauthorized"}), 401


def get_prediction_level(
    text: str,
    malicious_threshold_certain: float = MALICIOUS_THRESHOLD_CERTAIN,
    malicious_threshold_ambiguous: float = MALICIOUS_THRESHOLD_AMBIGUOUS,
):
    if not model or not tokenizer:
        return "모델 로드 오류", {"malicious": 0.0, "clean": 0.0}

    try:
        inputs = tokenizer(
            text,
            return_tensors="pt",
            truncation=True,
            padding=True,
            max_length=128,
        ).to(device)
        with torch.no_grad():
            outputs = model(**inputs)

        logits = outputs.logits
        probabilities = torch.softmax(logits, dim=1)[0]

        # 원본 데이터셋/모델 기준: 0=악성, 1=정상
        malicious_prob = probabilities[0].item()
        clean_prob = probabilities[1].item()

        if malicious_prob >= malicious_threshold_certain:
            level = "확실한 비속어"
        elif malicious_prob >= malicious_threshold_ambiguous:
            level = "애매한 비속어"
        else:
            level = "비속어 아님"

        probs_dict = {
            "malicious": round(malicious_prob, 4),
            "clean": round(clean_prob, 4),
        }

        return level, probs_dict
    except Exception as e:
        app.logger.exception("Prediction failed: %s", e)
        raise


@app.route("/health", methods=["GET"])  # Cloud Run 헬스체크 용도
def health():
    ready = bool(model and tokenizer)
    return jsonify(
        {
            "status": "ok" if ready else "degraded",
            "model_ready": ready,
            "model_path": MODEL_PATH,
            "thresholds": {
                "certain": MALICIOUS_THRESHOLD_CERTAIN,
                "ambiguous": MALICIOUS_THRESHOLD_AMBIGUOUS,
            },
            "version": os.environ.get("RELEASE", "dev"),
        }
    )


@app.route("/predict", methods=["POST"])
def handle_prediction():
    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 400

    data = request.get_json(silent=True) or {}
    text_to_predict = data.get("text")

    if not text_to_predict or not isinstance(text_to_predict, str):
        return jsonify({"error": "text 필드가 필요합니다."}), 400

    if len(text_to_predict.strip()) == 0:
        return jsonify({"error": "빈 문자열은 허용되지 않습니다."}), 400

    # 입력 길이 제한(선택): 과도한 길이 방지
    if len(text_to_predict) > 2000:
        return jsonify({"error": "입력 길이가 너무 깁니다.(<=2000자)"}), 413

    try:
        prediction_level, probabilities = get_prediction_level(text_to_predict)

        if prediction_level == "모델 로드 오류":
            return jsonify({"error": "서버 내부 오류: 모델이 로드되지 않았습니다."}), 500

        return jsonify(
            {
                "text": text_to_predict,
                "prediction_level": prediction_level,
                "probabilities": probabilities,
            }
        )
    except Exception:
        return jsonify({"error": "서버 내부 오류: 예측 실패"}), 500


@app.errorhandler(Exception)
def _unhandled_error(err):
    app.logger.exception("Unhandled error: %s", err)
    return jsonify({"error": "서버 내부 오류"}), 500


def create_app():
    # for gunicorn factory pattern if needed
    return app


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 9090))
    app.run(host="0.0.0.0", port=port)
