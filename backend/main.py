"""API de login con reconocimiento facial.

Endpoints:
  POST /register   (form: username, pin, photo, photo_turn) -> registra rostro + PIN
  POST /login      (form: username, photo, photo_turn)      -> devuelve un token
  POST /login_pin  (form: username, pin)                    -> token sin escáner
  POST /identify   (form: photo, photo_turn)  -> reconoce quién es y devuelve un token
  GET  /me         (Authorization: Bearer <token>)     -> datos del usuario
  POST /logout     (Authorization: Bearer <token>)

`photo` es una selfie de frente y `photo_turn` otra con la cabeza girada hacia
un lado; con las dos se comprueba que hay una persona real (prueba de vida).
"""
import hashlib
import hmac
import os
import re
import secrets
import sqlite3
import time
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile

from face_engine import (
    COSINE_THRESHOLD,
    FaceEngine,
    FaceError,
    FaceSample,
    LivenessError,
    log,
)

DB_PATH = Path(os.environ.get("FACE_DB", Path(__file__).parent / "users.db"))
DEBUG_DIR = Path(os.environ["FACE_DEBUG_DIR"]) if os.environ.get("FACE_DEBUG_DIR") else None
CURRENT_TERMS_VERSION = "2026-11-23-v1"
MAX_UPLOAD_BYTES = 2 * 1024 * 1024
TOKEN_TTL_SECONDS = 7 * 24 * 3600
# Tras varios intentos fallidos se bloquea el usuario un rato.
MAX_FAILED_ATTEMPTS = 5
LOCK_SECONDS = 5 * 60
# PIN de los usuarios dados de alta antes de existir el PIN (solo migración).
LEGACY_PIN = "1234"
PIN_ITERATIONS = 100_000

app = FastAPI(title="Face Login")
engine = FaceEngine()


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with closing(db()) as conn, conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY,
                full_name TEXT NOT NULL,
                embedding BLOB NOT NULL,
                failed_attempts INTEGER NOT NULL DEFAULT 0,
                locked_until REAL NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                pin_hash TEXT,
                terms_accepted INTEGER NOT NULL DEFAULT 0,
                terms_version TEXT,
                consent_at REAL,
                ai_improvement_opt_in INTEGER NOT NULL DEFAULT 0,
                ai_consent_at REAL,
                consent_salt TEXT
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES users(username),
                expires_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS ai_improvement_samples (
                sample_id TEXT PRIMARY KEY,
                subject_hash TEXT NOT NULL,
                embedding BLOB NOT NULL,
                terms_version TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_ai_samples_subject
                ON ai_improvement_samples(subject_hash);
            """
        )
        cols = {row[1] for row in conn.execute("PRAGMA table_info(users)")}
        if "pin_hash" not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN pin_hash TEXT")
        new_user_columns = {
            "terms_accepted": "INTEGER NOT NULL DEFAULT 0",
            "terms_version": "TEXT",
            "consent_at": "REAL",
            "ai_improvement_opt_in": "INTEGER NOT NULL DEFAULT 0",
            "ai_consent_at": "REAL",
            "consent_salt": "TEXT",
        }
        for name, definition in new_user_columns.items():
            if name not in cols:
                conn.execute(f"ALTER TABLE users ADD COLUMN {name} {definition}")
        # Usuarios registrados antes del PIN reciben el PIN por defecto.
        legacy = conn.execute(
            "SELECT username FROM users WHERE pin_hash IS NULL"
        ).fetchall()
        for user in legacy:
            conn.execute(
                "UPDATE users SET pin_hash = ? WHERE username = ?",
                (hash_pin(LEGACY_PIN), user["username"]),
            )


def hash_pin(pin: str) -> str:
    """PBKDF2 con salt aleatorio: el PIN nunca se guarda en claro."""
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", pin.encode(), bytes.fromhex(salt), PIN_ITERATIONS
    )
    return f"{salt}:{digest.hex()}"


def check_pin(pin: str, stored: str) -> bool:
    try:
        salt, expected = stored.split(":", 1)
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac(
        "sha256", pin.encode(), bytes.fromhex(salt), PIN_ITERATIONS
    )
    return hmac.compare_digest(digest.hex(), expected)


init_db()


async def read_photo(photo: UploadFile) -> bytes:
    data = await photo.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(413, "La foto es demasiado grande (máx. 2 MB).")
    return data


def analyze_pair(front: bytes, turned: bytes) -> tuple[FaceSample, FaceSample]:
    # Solo en desarrollo: guarda el último par de fotos para revisar fallos.
    if DEBUG_DIR:
        DEBUG_DIR.mkdir(exist_ok=True)
        (DEBUG_DIR / "front.jpg").write_bytes(front)
        (DEBUG_DIR / "turned.jpg").write_bytes(turned)
    try:
        return engine.analyze(front), engine.analyze(turned)
    except FaceError as e:
        raise HTTPException(422, str(e))


def clean_username(username: str) -> str:
    username = username.strip().lower()
    if not 3 <= len(username) <= 30 or not username.replace("_", "").isalnum():
        raise HTTPException(400, "Usuario inválido (3-30 letras, números o _).")
    return username


def _create_session(conn: sqlite3.Connection, username: str, now: float) -> str:
    """Crea un token de sesión y limpia el estado del usuario."""
    token = secrets.token_urlsafe(32)
    conn.execute(
        "UPDATE users SET failed_attempts = 0, locked_until = 0 WHERE username = ?",
        (username,),
    )
    conn.execute("DELETE FROM sessions WHERE expires_at < ?", (now,))
    conn.execute(
        "INSERT INTO sessions (token, username, expires_at) VALUES (?, ?, ?)",
        (token, username, now + TOKEN_TTL_SECONDS),
    )
    return token


def clean_pin(pin: str) -> str:
    pin = pin.strip()
    if not re.fullmatch(r"\d{4}", pin):
        raise HTTPException(400, "El PIN debe tener 4 dígitos.")
    return pin


def _parse_consent_bool(value: str, field: str) -> bool:
    normalized = value.strip().lower()
    if normalized in {"true", "1", "yes", "si"}:
        return True
    if normalized in {"false", "0", "no"}:
        return False
    raise HTTPException(422, f"{field} no es válido.")


def _parse_consent_time(value: str) -> float:
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(422, "La fecha de consentimiento no es válida.")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


def _subject_hash(username: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}:{username}".encode()).hexdigest()


def _replace_ai_sample(
    conn: sqlite3.Connection,
    username: str,
    salt: str,
    embedding: bytes,
    enabled: bool,
    terms_version: str,
    now: float,
) -> None:
    subject = _subject_hash(username, salt)
    conn.execute("DELETE FROM ai_improvement_samples WHERE subject_hash = ?", (subject,))
    if enabled:
        conn.execute(
            "INSERT INTO ai_improvement_samples "
            "(sample_id, subject_hash, embedding, terms_version, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (secrets.token_hex(16), subject, embedding, terms_version, now),
        )


def _check_lock(user: sqlite3.Row, now: float) -> None:
    if user["locked_until"] > now:
        wait = int(user["locked_until"] - now) // 60 + 1
        raise HTTPException(429, f"Demasiados intentos. Espera {wait} min.")


def _register_failure(
    conn: sqlite3.Connection, username: str, failed_attempts: int, now: float
) -> None:
    """Suma un intento fallido y bloquea si se pasa del límite."""
    attempts = failed_attempts + 1
    locked = now + LOCK_SECONDS if attempts >= MAX_FAILED_ATTEMPTS else 0
    conn.execute(
        "UPDATE users SET failed_attempts = ?, locked_until = ? WHERE username = ?",
        (0 if locked else attempts, locked, username),
    )
    # El commit hace efectivo el contador antes de lanzar el 401.
    conn.commit()


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/register")
async def register(
    username: str = Form(...),
    pin: str = Form(...),
    photo: UploadFile = File(...),
    photo_turn: UploadFile = File(...),
    terms_accepted: str = Form(...),
    terms_version: str = Form(...),
    ai_improvement_opt_in: str = Form("false"),
    consent_at: str = Form(...),
):
    username = clean_username(username)
    pin = clean_pin(pin)
    if not _parse_consent_bool(terms_accepted, "terms_accepted"):
        raise HTTPException(422, "Debes aceptar los términos y condiciones.")
    if terms_version.strip() != CURRENT_TERMS_VERSION:
        raise HTTPException(409, "La versión de los términos no es vigente. Actualiza la app.")
    ai_opt_in = _parse_consent_bool(ai_improvement_opt_in, "ai_improvement_opt_in")
    consent_time = _parse_consent_time(consent_at)
    front, turned = analyze_pair(await read_photo(photo), await read_photo(photo_turn))
    try:
        engine.check_liveness(front, turned)
    except LivenessError as e:
        log.info("registro %s rechazado: %s", username, e)
        raise HTTPException(422, str(e))
    embedding = front.vector.tobytes()
    salt = secrets.token_hex(16)
    created_at = time.time()
    with closing(db()) as conn, conn:
        exists = conn.execute(
            "SELECT 1 FROM users WHERE username = ?", (username,)
        ).fetchone()
        if exists:
            raise HTTPException(409, "Ese usuario ya existe.")
        conn.execute(
            "INSERT INTO users (username, full_name, embedding, pin_hash, created_at, "
            "terms_accepted, terms_version, consent_at, ai_improvement_opt_in, "
            "ai_consent_at, consent_salt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                username,
                username,
                embedding,
                hash_pin(pin),
                created_at,
                1,
                CURRENT_TERMS_VERSION,
                consent_time,
                int(ai_opt_in),
                consent_time if ai_opt_in else None,
                salt,
            ),
        )
        _replace_ai_sample(
            conn,
            username,
            salt,
            embedding,
            ai_opt_in,
            CURRENT_TERMS_VERSION,
            created_at,
        )
    return {"ok": True, "message": "Rostro registrado."}


@app.post("/login")
async def login(
    username: str = Form(...),
    photo: UploadFile = File(...),
    photo_turn: UploadFile = File(...),
):
    username = clean_username(username)
    front_data = await read_photo(photo)
    turned_data = await read_photo(photo_turn)
    now = time.time()

    with closing(db()) as conn, conn:
        user = conn.execute(
            "SELECT * FROM users WHERE username = ?", (username,)
        ).fetchone()
        if user is None:
            raise HTTPException(404, "Usuario no registrado.")
        _check_lock(user, now)

        front, turned = analyze_pair(front_data, turned_data)
        stored = np.frombuffer(user["embedding"], dtype=np.float32)
        # Tanto una suplantación como un rostro distinto cuentan como intento fallido.
        reason = None
        try:
            engine.check_liveness(front, turned)
            ok, score = engine.is_match(front.vector, stored)
            log.info("login %s: coincidencia=%.2f", username, score)
            if not ok:
                reason = "El rostro no coincide."
        except LivenessError as e:
            reason = str(e)
        if reason:
            log.info("login %s rechazado: %s", username, reason)
            _register_failure(conn, username, user["failed_attempts"], now)
            raise HTTPException(401, reason)

        token = _create_session(conn, username, now)
    return {
        "token": token,
        "username": username,
        "full_name": user["full_name"],
        "score": round(score, 3),
    }


@app.post("/login_pin")
async def login_pin(username: str = Form(...), pin: str = Form(...)):
    """Entra con usuario y PIN, sin escáner facial."""
    username = clean_username(username)
    pin = pin.strip()
    now = time.time()

    with closing(db()) as conn, conn:
        user = conn.execute(
            "SELECT * FROM users WHERE username = ?", (username,)
        ).fetchone()
        if user is None:
            raise HTTPException(404, "Usuario no registrado.")
        _check_lock(user, now)
        if not user["pin_hash"]:
            raise HTTPException(401, "Este usuario no tiene PIN.")
        if not check_pin(pin, user["pin_hash"]):
            log.info("login_pin %s rechazado: PIN incorrecto", username)
            _register_failure(conn, username, user["failed_attempts"], now)
            raise HTTPException(401, "PIN incorrecto.")
        token = _create_session(conn, username, now)
    return {
        "token": token,
        "username": username,
        "full_name": user["full_name"],
    }


@app.post("/identify")
async def identify(
    photo: UploadFile = File(...),
    photo_turn: UploadFile = File(...),
):
    """Reconoce al usuario por el rostro, sin escribir el nombre."""
    front_data = await read_photo(photo)
    turned_data = await read_photo(photo_turn)
    now = time.time()

    front, turned = analyze_pair(front_data, turned_data)
    try:
        engine.check_liveness(front, turned)
    except LivenessError as e:
        log.info("identify rechazado: %s", e)
        raise HTTPException(401, str(e))

    with closing(db()) as conn, conn:
        users = conn.execute(
            "SELECT username, full_name, embedding FROM users"
        ).fetchall()
        if not users:
            raise HTTPException(401, "No hay usuarios registrados.")
        best_user = None
        best_score = -1.0
        for user in users:
            stored = np.frombuffer(user["embedding"], dtype=np.float32)
            score = engine.similarity(front.vector, stored)
            if score > best_score:
                best_score = score
                best_user = user
        log.info(
            "identify %s: coincidencia=%.2f", best_user["username"], best_score
        )
        if best_score < COSINE_THRESHOLD:
            raise HTTPException(401, "Rostro no reconocido.")
        token = _create_session(conn, best_user["username"], now)
    return {
        "token": token,
        "username": best_user["username"],
        "full_name": best_user["full_name"],
        "score": round(best_score, 3),
    }


def current_user(authorization: str = Header(default="")) -> sqlite3.Row:
    token = authorization.removeprefix("Bearer ").strip()
    with closing(db()) as conn:
        row = conn.execute(
            "SELECT u.username, u.full_name, s.token FROM sessions s "
            "JOIN users u ON u.username = s.username "
            "WHERE s.token = ? AND s.expires_at > ?",
            (token, time.time()),
        ).fetchone()
    if row is None:
        raise HTTPException(401, "Sesión inválida o vencida.")
    return row


@app.post("/consent")
def update_consent(
    ai_improvement_opt_in: str = Form(...),
    terms_version: str = Form(...),
    user: sqlite3.Row = Depends(current_user),
):
    enabled = _parse_consent_bool(ai_improvement_opt_in, "ai_improvement_opt_in")
    if terms_version.strip() != CURRENT_TERMS_VERSION:
        raise HTTPException(409, "La versión de los términos no es vigente. Actualiza la app.")
    now = time.time()
    with closing(db()) as conn, conn:
        row = conn.execute(
            "SELECT embedding, consent_salt FROM users WHERE username = ?",
            (user["username"],),
        ).fetchone()
        if row is None:
            raise HTTPException(404, "Usuario no registrado.")
        salt = row["consent_salt"] or secrets.token_hex(16)
        conn.execute(
            "UPDATE users SET terms_accepted = 1, terms_version = ?, "
            "consent_at = COALESCE(consent_at, ?), ai_improvement_opt_in = ?, "
            "ai_consent_at = ?, consent_salt = ? WHERE username = ?",
            (
                CURRENT_TERMS_VERSION,
                now,
                int(enabled),
                now,
                salt,
                user["username"],
            ),
        )
        _replace_ai_sample(
            conn,
            user["username"],
            salt,
            row["embedding"],
            enabled,
            CURRENT_TERMS_VERSION,
            now,
        )
    return {"ok": True, "ai_improvement_opt_in": enabled}


@app.get("/me")
def me(user: sqlite3.Row = Depends(current_user)):
    return {"username": user["username"], "full_name": user["full_name"]}


@app.post("/logout")
def logout(user: sqlite3.Row = Depends(current_user)):
    with closing(db()) as conn, conn:
        conn.execute("DELETE FROM sessions WHERE token = ?", (user["token"],))
    return {"ok": True}
