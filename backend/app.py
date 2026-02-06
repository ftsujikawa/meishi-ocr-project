from fastapi import FastAPI, UploadFile, File, HTTPException, status
import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("NUMEXPR_NUM_THREADS", "1")
os.environ.setdefault("FLAGS_use_mkldnn", "0")

from paddleocr import PaddleOCR
import cv2, numpy as np, re
import json
import threading
import httpx
import traceback
from pydantic import BaseModel, Field, ValidationError

app = FastAPI()
_ocr = None
_ocr_lock = threading.Lock()


class BusinessCardLLM(BaseModel):
    name: str = ""
    company: str = ""
    department: str = ""
    title: str = ""
    phones: list[str] = Field(default_factory=list)
    mobiles: list[str] = Field(default_factory=list)
    faxes: list[str] = Field(default_factory=list)
    emails: list[str] = Field(default_factory=list)
    urls: list[str] = Field(default_factory=list)
    postal_code: str = ""
    address: str = ""
    other: list[str] = Field(default_factory=list)


def _coerce_str(v) -> str:
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    if isinstance(v, (int, float, bool)):
        return str(v)
    if isinstance(v, (list, tuple)):
        parts = [str(x).strip() for x in v if x is not None]
        parts = [p for p in parts if p]
        return " ".join(parts)
    if isinstance(v, dict):
        try:
            return json.dumps(v, ensure_ascii=False)
        except Exception:
            return str(v)
    return str(v)


def _coerce_list_str(v) -> list[str]:
    if v is None:
        return []
    if isinstance(v, str):
        s = v.strip()
        return [s] if s else []
    if isinstance(v, (list, tuple)):
        out: list[str] = []
        for x in v:
            s = _coerce_str(x).strip()
            if s:
                out.append(s)
        return out
    if isinstance(v, (int, float, bool)):
        return [str(v)]
    return []


async def _openai_extract_card_from_blocks(blocks: list[dict]) -> dict:

    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OPENAI_API_KEY is not set",
        )

    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini").strip() or "gpt-4o-mini"

    lines: list[str] = []
    for b in blocks:
        t = (b.get("text") or "").strip()
        if not t:
            continue
        c = b.get("confidence")
        if isinstance(c, (int, float)):
            lines.append(f"{t} (conf={float(c):.2f})")
        else:
            lines.append(t)

    joined = "\n".join(lines)
    system = (
        "You are a careful Japanese business card information extractor. "
        "Return ONLY valid JSON (no markdown)."
    )
    user = (
        "Extract business card fields from the OCR lines below. "
        "Do not hallucinate. If unknown, use empty string or empty list. "
        "Output JSON with this schema:\n"
        "{\n"
        "  \"name\": \"\",\n"
        "  \"company\": \"\",\n"
        "  \"department\": \"\",\n"
        "  \"title\": \"\",\n"
        "  \"phones\": [],\n"
        "  \"mobiles\": [],\n"
        "  \"faxes\": [],\n"
        "  \"emails\": [],\n"
        "  \"urls\": [],\n"
        "  \"postal_code\": \"\",\n"
        "  \"address\": \"\",\n"
        "  \"other\": []\n"
        "}\n\n"
        "OCR lines:\n"
        f"{joined}"
    )

    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": 0,
    }

    timeout = httpx.Timeout(45.0, connect=15.0)
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
    except httpx.HTTPError as e:
        try:
            print(f"OpenAI request failed: {type(e).__name__}: {e}")
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"OpenAI request failed: {type(e).__name__}",
        )

    if r.status_code >= 400:
        body = (r.text or "").strip()
        body_snip = body[:1000]
        try:
            print(f"OpenAI API error: status={r.status_code}, body={body_snip}")
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"OpenAI API error: {r.status_code} {body_snip}",
        )

    try:
        data = r.json()
    except Exception:
        body = (r.text or "").strip()
        body_snip = body[:1000]
        try:
            print(f"OpenAI response JSON parse failed: status={r.status_code}, body={body_snip}")
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"OpenAI response JSON parse failed: {body_snip}",
        )

    content = (
        ((data.get("choices") or [{}])[0].get("message") or {}).get("content") or ""
    ).strip()
    if not content:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="OpenAI API returned empty content",
        )

    parsed = None
    try:
        parsed = json.loads(content)
    except Exception:
        m = re.search(r"\{[\s\S]*\}", content)
        if not m:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"OpenAI output is not JSON: {content[:200]}",
            )
        try:
            parsed = json.loads(m.group(0))
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"OpenAI output JSON parse failed: {content[:200]}",
            )

    if not isinstance(parsed, dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"OpenAI output JSON must be an object: got {type(parsed).__name__}",
        )

    coerced = {
        "name": _coerce_str(parsed.get("name")),
        "company": _coerce_str(parsed.get("company")),
        "department": _coerce_str(parsed.get("department")),
        "title": _coerce_str(parsed.get("title")),
        "phones": _coerce_list_str(parsed.get("phones")),
        "mobiles": _coerce_list_str(parsed.get("mobiles")),
        "faxes": _coerce_list_str(parsed.get("faxes")),
        "emails": _coerce_list_str(parsed.get("emails")),
        "urls": _coerce_list_str(parsed.get("urls")),
        "postal_code": _coerce_str(parsed.get("postal_code")),
        "address": _coerce_str(parsed.get("address")),
        "other": _coerce_list_str(parsed.get("other")),
    }

    try:
        validated = BusinessCardLLM.model_validate(coerced)
        return validated.model_dump()
    except ValidationError as e:
        try:
            print("OpenAI output schema validation failed (fallback to defaults):")
            print(e)
        except Exception:
            pass
        return BusinessCardLLM().model_dump()


def _get_ocr():
    global _ocr
    if _ocr is not None:
        return _ocr
    with _ocr_lock:
        if _ocr is None:
            _ocr = PaddleOCR(use_angle_cls=True, lang="japan")
    return _ocr


def _extract_text_score_from_ocr_line(line):
    if line is None:
        return None

    if isinstance(line, dict):
        text = line.get("text") or line.get("label") or line.get("rec_text")
        score = line.get("score")
        if score is None:
            score = line.get("confidence")
        if text is None:
            return None
        return str(text), float(score) if isinstance(score, (int, float)) else None

    if isinstance(line, (list, tuple)):
        if len(line) == 2:
            a, b = line
            if isinstance(b, (list, tuple)) and len(b) >= 1:
                text = b[0]
                score = b[1] if len(b) >= 2 else None
                if isinstance(text, str):
                    return text, float(score) if isinstance(score, (int, float)) else None

            if isinstance(a, str) and isinstance(b, (int, float)):
                return a, float(b)

        if len(line) == 3:
            a, b, c = line
            if isinstance(b, str) and isinstance(c, (int, float)):
                return b, float(c)
            if isinstance(a, str) and isinstance(b, (int, float)):
                return a, float(b)

        text = None
        score = None
        for v in line:
            if text is None and isinstance(v, str):
                text = v
            if score is None and isinstance(v, (int, float)):
                score = float(v)
        if text is not None:
            return text, score
    return None


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
    try:
        import asyncio

        async def _warmup():
            try:
                await asyncio.to_thread(_get_ocr)
            except Exception:
                try:
                    print("OCR startup warmup failed:")
                    print(traceback.format_exc())
                except Exception:
                    pass

        asyncio.create_task(_warmup())
    except Exception:
        try:
            print("OCR startup warmup scheduling failed:")
            print(traceback.format_exc())
        except Exception:
            pass


@app.get("/")
async def health():
    return {"status": "ok"}


def _llm_to_blocks(llm: dict) -> list[dict]:
    def _add(out: list[dict], label: str, value: str):
        t = (value or "").strip()
        if not t:
            return
        out.append({"text": t, "labels": [label], "source": "llm"})

    out: list[dict] = []
    if not isinstance(llm, dict):
        return out

    _add(out, "氏名", str(llm.get("name") or ""))
    _add(out, "会社", str(llm.get("company") or ""))
    _add(out, "部署", str(llm.get("department") or ""))
    _add(out, "役職", str(llm.get("title") or ""))
    _add(out, "郵便番号", str(llm.get("postal_code") or ""))
    _add(out, "住所", str(llm.get("address") or ""))

    for v in (llm.get("phones") or []):
        _add(out, "電話", str(v))
    for v in (llm.get("mobiles") or []):
        _add(out, "携帯", str(v))
    for v in (llm.get("faxes") or []):
        _add(out, "FAX", str(v))
    for v in (llm.get("emails") or []):
        _add(out, "メール", str(v))
    for v in (llm.get("urls") or []):
        _add(out, "URL", str(v))
    for v in (llm.get("other") or []):
        _add(out, "その他", str(v))
    return out


@app.post("/ocr")
async def ocr_api(file: UploadFile = File(...), use_llm: bool = False):

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
        try:
            print("OCR exception:")
            print(traceback.format_exc())
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="OCR failed",
        )

    if not result or not result[0]:
        return {"blocks": []}

    blocks = []
    lines = result[0] if isinstance(result, (list, tuple)) else result
    if not isinstance(lines, (list, tuple)):
        lines = []

    for line in lines:
        extracted = _extract_text_score_from_ocr_line(line)
        if not extracted:
            continue
        text, score = extracted

        t = (text or "").strip()
        if not t:
            continue
        if _looks_like_phone(t):
            t = _normalize_phone_text(t)
        elif re.search(r"\bhttps?\b|\bwww\b", t, flags=re.IGNORECASE):
            t = _normalize_url_text(t)

        b = {"text": t}
        if isinstance(score, (int, float)):
            b["confidence"] = float(score)
        blocks.append(b)

    try:
        head_n = 10
        print(f"/ocr blocks: count={len(blocks)}")
        print(
            "/ocr blocks head: "
            + json.dumps(blocks[:head_n], ensure_ascii=False)[:8000]
        )
    except Exception:
        pass

    resp = {"blocks": blocks}
    if use_llm:
        try:
            llm = await _openai_extract_card_from_blocks(blocks)
            resp["llm"] = llm
            llm_blocks = _llm_to_blocks(llm)
            if llm_blocks:
                resp["blocks"] = llm_blocks + blocks
        except Exception:
            pass
    return resp