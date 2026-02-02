from fastapi import FastAPI, UploadFile, File
from paddleocr import PaddleOCR
import cv2, numpy as np, re
import threading


app = FastAPI()
_ocr = None
_ocr_lock = threading.Lock()


def _get_ocr():
    global _ocr
    if _ocr is not None:
        return _ocr
    with _ocr_lock:
        if _ocr is None:
            _ocr = PaddleOCR(use_angle_cls=True, lang="japan")
    return _ocr


@app.get("/")
async def health():
    return {"status": "ok"}


@app.post("/ocr")
async def ocr_api(file: UploadFile = File(...)):
    img_bytes = await file.read()
    img_np = np.frombuffer(img_bytes, np.uint8)
    img = cv2.imdecode(img_np, cv2.IMREAD_COLOR)

    ocr = _get_ocr()
    result = ocr.ocr(img, cls=True)

    blocks = []
    for line in result[0]:
        box, (text, score) = line
        blocks.append({"text": text, "confidence": score})

    return {
        "blocks": blocks
    }