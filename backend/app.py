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


def _normalize_url_text(text: str) -> str:
    s = text.strip()
    if not s:
        return s

    s = s.replace("：", ":").replace("／", "/")
    s = s.replace("ー", "-").replace("－", "-").replace("―", "-").replace("−", "-")

    s = re.sub(r"\s+", "", s)

    # Drop obvious trailing noise.
    s = re.sub(r"[!\)\]\}。．…]+$", "", s)

    # Keep URL-ish characters only (helps against stray punctuation like '!').
    s = re.sub(r"[^A-Za-z0-9:/?#[\]@!$&'()*+,;=._%\-]", "", s)
    s = s.replace("!", "")

    # Common OCR confusions around scheme separator.
    # e.g. "httpsrn" -> "https://" ("rn" is often read instead of "://")
    s = re.sub(r"^(https?)(rn)", r"\1://", s, flags=re.IGNORECASE)
    s = re.sub(r"^(https?)(:)?(//)?(rn)", r"\1://", s, flags=re.IGNORECASE)

    # Common OCR confusions for scheme itself.
    s = re.sub(r"^nttps", "https", s, flags=re.IGNORECASE)
    s = re.sub(r"^nhttps", "https", s, flags=re.IGNORECASE)
    s = re.sub(r"^nttp", "http", s, flags=re.IGNORECASE)

    # Another scheme-separator confusion: '://'(or '://') read as 'lynw'/'lnw'/etc.
    s = re.sub(r"^(https?)(lynw|lnw|lynw)", r"\1://", s, flags=re.IGNORECASE)

    # Yet another confusion variant: '://'/':/' read as 'yl'.
    s = re.sub(r"^(https?)(yl)", r"\1://", s, flags=re.IGNORECASE)

    # Common OCR confusions for "www."
    s = re.sub(r"^(https?://)?(wvvw|vvvw|wwvw|wvw|ww|vvv|vv)", r"\1www.", s, flags=re.IGNORECASE)

    m = re.match(r"^(https?)[:;]?/*", s, flags=re.IGNORECASE)
    if m is not None:
        scheme = m.group(1).lower()
        rest = s[m.end():]
        s = f"{scheme}://{rest}"
    else:
        s = re.sub(r"^www\.", "www.", s, flags=re.IGNORECASE)

    s = re.sub(r"^(https?)(:)(/)([^/])", r"\1://\4", s, flags=re.IGNORECASE)

    # Clean up common domain-level noise.
    s = re.sub(r"^(https?://)-+", r"\1", s, flags=re.IGNORECASE)
    s = re.sub(r"^(https?://)(kww|kww\.|-kww\.)", r"\1www.", s, flags=re.IGNORECASE)
    s = re.sub(r"^(https?://)(-+)(www\.)", r"\1\3", s, flags=re.IGNORECASE)
    s = re.sub(r"\.-+", ".", s)
    s = re.sub(r"-+\.", ".", s)
    s = re.sub(r"\.{2,}", ".", s)
    s = re.sub(r"-{2,}", "-", s)

    # Very common brand-level OCR confusion.
    s = re.sub(r"sagawra", "sagawa", s, flags=re.IGNORECASE)

    # Common TLD confusion (jp vs ip) seen in OCR.
    s = re.sub(r"\.co\.ip\b", ".co.jp", s, flags=re.IGNORECASE)
    s = re.sub(r"\.or\.ip\b", ".or.jp", s, flags=re.IGNORECASE)
    s = re.sub(r"\.ne\.ip\b", ".ne.jp", s, flags=re.IGNORECASE)

    # Fix punctuation inserted before TLD.
    s = re.sub(r"\.co[!\-\._]*jp\b", ".co.jp", s, flags=re.IGNORECASE)
    return s


_FW_DIGITS = str.maketrans(
    {
        "０": "0",
        "１": "1",
        "２": "2",
        "３": "3",
        "４": "4",
        "５": "5",
        "６": "6",
        "７": "7",
        "８": "8",
        "９": "9",
        "＋": "+",
    }
)


_PHONE_OCR_REPL = {
    "O": "0",
    "o": "0",
    "D": "0",
    "C": "0",
    "c": "0",
    "I": "1",
    "l": "1",
    "|": "1",
    "!": "1",
    "A": "4",
    "a": "4",
    "Z": "2",
    "S": "5",
    "B": "8",
    "g": "9",
    "q": "9",
}


def _phone_sanitize_for_digits(text: str) -> str:
    s = text.strip().translate(_FW_DIGITS)
    if not s:
        return s
    return "".join(_PHONE_OCR_REPL.get(ch, ch) for ch in s)


def _phone_digits_candidates(text: str) -> list[str]:
    s = text.strip().translate(_FW_DIGITS)
    if not s:
        return []

    s1 = _phone_sanitize_for_digits(s)
    d1 = re.sub(r"\D", "", s1)

    # '!' is often just noise near hyphens in phone numbers, so also try removing it.
    s2 = s.replace("!", "")
    s2 = _phone_sanitize_for_digits(s2)
    d2 = re.sub(r"\D", "", s2)

    d3 = ""
    d4 = ""
    # Sometimes an extra leading digit is hallucinated (e.g. "4074355..." instead of "074355...").
    # If dropping the first digit yields a plausible JP number, keep it as a candidate.
    if d2 and len(d2) == 11 and d2.startswith("40"):
        cand = d2[1:]
        if cand.startswith("0") and len(cand) == 10:
            d3 = cand

    # Another common artifact: two extra leading digits (e.g. "43" + "0743...").
    if d2 and len(d2) == 12 and d2.startswith("43"):
        cand = d2[2:]
        if cand.startswith("0") and len(cand) == 10:
            d4 = cand

    out: list[str] = []
    for d in (d1, d2, d3, d4):
        if d and d not in out:
            out.append(d)
    return out


def _looks_like_phone(text: str) -> bool:
    s = _phone_sanitize_for_digits(text)
    if not s:
        return False

    if re.search(r"https?://|\bwww\b", s, flags=re.IGNORECASE):
        return False
    if "@" in s:
        return False

    digits_list = _phone_digits_candidates(text)
    digits = digits_list[0] if digits_list else ""
    # NTT Navi Dial (0570-xx-xxxx) may be partially recognized but still valuable to capture.
    # Accept shorter lengths for 0570-prefix.
    if any(d.startswith("0570") and len(d) >= 6 for d in digits_list):
        pass
    elif any(len(d) >= 9 for d in digits_list):
        pass
    else:
        return False

    allowed = re.sub(r"[0-9\s\-\(\)\+\.／/ー－―−]", "", s)
    if allowed and len(allowed) >= 3:
        return False

    if re.search(r"\b(fax|tel|phone|mobile)\b", s, flags=re.IGNORECASE):
        return True

    if re.search(r"\d{2,4}[-ー－―−]\d{2,4}[-ー－―−]\d{3,4}", s):
        return True

    if digits.startswith("0") and len(digits) in (10, 11):
        return True

    if s.startswith("+") and len(digits) >= 10:
        return True

    return False


def _normalize_phone_text(text: str) -> str:
    s = text.strip().translate(_FW_DIGITS)
    if not s:
        return s

    s = s.replace("：", ":").replace("／", "/")
    s = s.replace("ー", "-").replace("－", "-").replace("―", "-").replace("−", "-")
    s = s.replace("^", "-")

    # Leading labels like TEL/FAX are often partially recognized (e.g. "FA073..."), so strip them.
    s = re.sub(r"^\s*(tel|phone|mobile|fax)\s*[:：]?\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"^\s*fa\s*[:：]?\s*", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\s+", "", s)

    # OCR misreads that often happen inside phone numbers.
    # Apply conservatively: only to characters that are part of a phone-ish token.
    s = _phone_sanitize_for_digits(s)

    m = re.match(r"^(\+)", s)
    plus = "+" if m else ""
    digits_candidates = _phone_digits_candidates(text)
    digits = ""
    if digits_candidates:
        # Prefer a candidate that can be formatted as 0570-xx-xxxx.
        for d in digits_candidates:
            if d.startswith("0570") and len(d) == 10:
                digits = d
                break
        if not digits:
            # Otherwise prefer the longest (most information).
            digits = max(digits_candidates, key=len)

    if len(digits) < 9:
        # For 0570, allow shorter partials (e.g. OCR dropped last digits).
        if digits.startswith("0570") and len(digits) >= 6:
            return digits
        return text.strip()

    # Basic JP formatting heuristics.
    if plus:
        return plus + digits

    if digits.startswith("0"):
        # NTT Navi Dial formatting: 0570-xx-xxxx
        if digits.startswith("0570") and len(digits) == 10:
            return f"{digits[:4]}-{digits[4:6]}-{digits[6:]}"
        # Some JP area codes are 4 digits (e.g. 0743). Prefer 4-2-4 in such cases.
        if digits.startswith("0743") and len(digits) == 10:
            return f"{digits[:4]}-{digits[4:6]}-{digits[6:]}"
        if len(digits) == 10 and digits[:2] in ("03", "06"):
            return f"{digits[:2]}-{digits[2:6]}-{digits[6:]}"
        if len(digits) == 11 and digits[:3] in ("070", "080", "090"):
            return f"{digits[:3]}-{digits[3:7]}-{digits[7:]}"
        if len(digits) == 10:
            return f"{digits[:3]}-{digits[3:6]}-{digits[6:]}"
        if len(digits) == 11:
            return f"{digits[:3]}-{digits[3:7]}-{digits[7:]}"

    # Fallback: return digit-only to avoid emitting broken punctuation.
    return digits


def _preprocess_for_ocr(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    short_side = min(h, w)
    if short_side < 1200:
        scale = 1200.0 / float(short_side)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    thr = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)[1]

    # Prefer angle estimated from long near-horizontal lines.
    # This tends to be more stable than minAreaRect when thresholding picks up large regions.
    hough_angle = None
    try:
        edges = cv2.Canny(gray, 50, 150)
        min_len = int(min(img.shape[0], img.shape[1]) * 0.25)
        lines = cv2.HoughLinesP(
            edges,
            rho=1,
            theta=np.pi / 180.0,
            threshold=120,
            minLineLength=min_len,
            maxLineGap=20,
        )
        if lines is not None and len(lines) >= 6:
            angles = []
            for x1, y1, x2, y2 in lines[:, 0]:
                dx = float(x2 - x1)
                dy = float(y2 - y1)
                if dx == 0.0:
                    continue
                a = np.degrees(np.arctan2(dy, dx))
                # Normalize to [-45, 45]
                if a > 45:
                    a -= 90
                elif a < -45:
                    a += 90
                if abs(a) <= 25:
                    angles.append(a)
            if len(angles) >= 6:
                hough_angle = float(np.median(np.array(angles, dtype=np.float32)))
                print(f"deskew hough angle={hough_angle:.3f}, n={len(angles)}/{len(lines)}")
    except Exception:
        hough_angle = None

    angle = hough_angle
    if angle is None:
        coords = np.column_stack(np.where(thr > 0))
        if coords.size >= 2000:
            rect = cv2.minAreaRect(coords.astype(np.float32))
            angle = float(rect[-1])
            # OpenCV returns angles in different ranges depending on version/build.
            # Normalize to [-45, 45] degrees.
            if angle > 45:
                angle = angle - 90
            elif angle < -45:
                angle = angle + 90
            try:
                print(f"deskew minAreaRect raw={rect[-1]:.3f}, angle(norm)={angle:.3f}, coords={coords.size}")
            except Exception:
                pass

    if angle is not None and abs(angle) > 0.2:
        angle = max(-15.0, min(15.0, float(angle)))
        (hh, ww) = img.shape[:2]
        center = (ww // 2, hh // 2)
        M = cv2.getRotationMatrix2D(center, angle, 1.0)
        img = cv2.warpAffine(
            img,
            M,
            (ww, hh),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE,
        )

    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l2 = clahe.apply(l)
    lab2 = cv2.merge((l2, a, b))
    img = cv2.cvtColor(lab2, cv2.COLOR_LAB2BGR)
    return img


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

    img = _preprocess_for_ocr(img)

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
        t = text
        if _looks_like_phone(t):
            t = _normalize_phone_text(t)
        elif re.search(r"\bhttps?\b|\bwww\b", t, flags=re.IGNORECASE):
            t = _normalize_url_text(t)
        blocks.append({"text": t, "confidence": score})

    return {
        "blocks": blocks
    }