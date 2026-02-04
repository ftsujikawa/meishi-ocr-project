from fastapi import FastAPI, UploadFile, File, HTTPException, status
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


@app.on_event("startup")
async def _startup_init_ocr():
    _get_ocr()


@app.get("/")
async def health():
    return {"status": "ok"}


@app.post("/ocr")
async def ocr_api(file: UploadFile = File(...)):
    try:
        print(f"/ocr request: filename={file.filename}, content_type={file.content_type}")
    except Exception:
        pass
    if file.content_type is None or not file.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid content type: {file.content_type}",
        )
    img_bytes = await file.read()
    try:
        print(f"/ocr file size: {len(img_bytes)}")
    except Exception:
        pass
    if not img_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Empty file",
        )
    img_np = np.frombuffer(img_bytes, np.uint8)
    img = cv2.imdecode(img_np, cv2.IMREAD_COLOR)

    if img is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid image",
        )

    ocr = _get_ocr()
    try:
        result = ocr.ocr(img)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="OCR failed",
        )

    if not result or not result[0]:
        return {"blocks": []}

    blocks = []
    for line in result[0]:
        box, (text, score) = line
        blocks.append({"text": text, "confidence": score})

    return {
        "blocks": blocks
    }