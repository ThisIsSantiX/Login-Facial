"""API de login con reconocimiento facial.

Endpoints:
  POST /register  (form: username, full_name, photo, photo_turn) -> registra el rostro
  POST /login     (form: username, photo, photo_turn)            -> devuelve un token
  GET  /me        (Authorization: Bearer <token>)     -> datos del usuario
  POST /logout    (Authorization: Bearer <token>)

`photo` es una selfie de frente y `photo_turn` otra con la cabeza girada hacia
un lado; con las dos se comprueba que hay una persona real (prueba de vida).
"""
import os
import secrets
import sqlite3
import time
from contextlib import closing
from pathlib import Path

import numpy as np
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile

from face_engine import FaceEngine, FaceError, FaceSample, LivenessError, log

DB_PATH = Path(os.environ.get("FACE_DB", Path(__file__).parent / "users.db"))
DEBUG_DIR = Path(os.environ["FACE_DEBUG_DIR"]) if os.environ.get("FACE_DEBUG_DIR") else None
MAX_UPLOAD_BYTES = 2 * 1024 * 1024
TOKEN_TTL_SECONDS = 7 * 24 * 3600
# Tras varios intentos fallidos se bloquea el usuario un rato.
MAX_FAILED_ATTEMPTS = 5
LOCK_SECONDS = 5 * 60

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
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES users(username),
                expires_at REAL NOT NULL
            );
            """
        )


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


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/register")
async def register(
    username: str = Form(...),
    full_name: str = Form(...),
    photo: UploadFile = File(...),
    photo_turn: UploadFile = File(...),
):
    username = clean_username(username)
    front, turned = analyze_pair(await read_photo(photo), await read_photo(photo_turn))
    try:
        engine.check_liveness(front, turned)
    except LivenessError as e:
        log.info("registro %s rechazado: %s", username, e)
        raise HTTPException(422, str(e))
    with closing(db()) as conn, conn:
        exists = conn.execute(
            "SELECT 1 FROM users WHERE username = ?", (username,)
        ).fetchone()
        if exists:
            raise HTTPException(409, "Ese usuario ya existe.")
        conn.execute(
            "INSERT INTO users (username, full_name, embedding, created_at) "
            "VALUES (?, ?, ?, ?)",
            (username, full_name.strip()[:80], front.vector.tobytes(), time.time()),
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
        if user["locked_until"] > now:
            wait = int(user["locked_until"] - now) // 60 + 1
            raise HTTPException(429, f"Demasiados intentos. Espera {wait} min.")

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

        if reason:
            attempts = user["failed_attempts"] + 1
            locked = now + LOCK_SECONDS if attempts >= MAX_FAILED_ATTEMPTS else 0
            conn.execute(
                "UPDATE users SET failed_attempts = ?, locked_until = ? "
                "WHERE username = ?",
                (0 if locked else attempts, locked, username),
            )
            # Sin commit explícito, la excepción haría rollback del contador.
            conn.commit()
            raise HTTPException(401, reason)

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
    return {
        "token": token,
        "username": username,
        "full_name": user["full_name"],
        "score": round(score, 3),
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


@app.get("/me")
def me(user: sqlite3.Row = Depends(current_user)):
    return {"username": user["username"], "full_name": user["full_name"]}


@app.post("/logout")
def logout(user: sqlite3.Row = Depends(current_user)):
    with closing(db()) as conn, conn:
        conn.execute("DELETE FROM sessions WHERE token = ?", (user["token"],))
    return {"ok": True}
