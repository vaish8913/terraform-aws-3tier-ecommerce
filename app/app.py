import re
import secrets
from functools import wraps

import bcrypt
import os
import pymysql
from flask import Flask, g, jsonify, request

from dbconfig import get_conn

app = Flask(__name__)

COOKIE_SECURE = os.environ.get("COOKIE_SECURE", "false") == "true"
SESSION_HOURS = 8
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
DUMMY_HASH = bcrypt.hashpw(b"dummy-password", bcrypt.gensalt())  # equalises timing for unknown emails


def db():
    if "db" not in g:
        g.db = get_conn()
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def err(message, code):
    return jsonify(error=message), code


@app.before_request
def json_only_writes():
    # Writes must be JSON: a cross-site HTML form cannot send application/json (basic CSRF defence)
    if request.method not in ("GET", "HEAD", "OPTIONS") and not request.is_json:
        return err("JSON body required", 415)


@app.errorhandler(Exception)
def unhandled(e):
    if hasattr(e, "code") and isinstance(e.code, int):
        return err(getattr(e, "description", "error"), e.code)
    app.logger.exception("unhandled error")
    return err("server error", 500)


def current_user():
    sid = request.cookies.get("sid")
    if not sid:
        return None
    with db().cursor() as c:
        c.execute(
            "SELECT u.id, u.name, u.email FROM sessions s JOIN users u ON u.id = s.user_id "
            "WHERE s.session_id = %s AND s.expires_at > NOW()",
            (sid,),
        )
        return c.fetchone()


def login_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        user = current_user()
        if not user:
            return err("login required", 401)
        g.user = user
        return fn(*args, **kwargs)

    return wrapper


@app.get("/api/health")
def health():
    return jsonify(status="ok")


# ---------------- auth ----------------
@app.post("/api/auth/register")
def register():
    d = request.get_json(silent=True) or {}
    name = str(d.get("name", "")).strip()
    email = str(d.get("email", "")).strip().lower()
    pw = str(d.get("password", ""))
    if not name or len(name) > 100 or not EMAIL_RE.match(email) or len(email) > 255:
        return err("invalid name or email", 400)
    if len(pw) < 8 or len(pw.encode()) > 72:
        return err("password must be 8 to 72 characters", 400)
    pw_hash = bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()
    try:
        with db().cursor() as c:
            c.execute(
                "INSERT INTO users (name, email, password_hash) VALUES (%s, %s, %s)",
                (name, email, pw_hash),
            )
        db().commit()
    except pymysql.err.IntegrityError:
        db().rollback()
        return err("email already registered", 409)
    return jsonify(message="registered"), 201


@app.post("/api/auth/login")
def login():
    d = request.get_json(silent=True) or {}
    email = str(d.get("email", "")).strip().lower()
    pw = str(d.get("password", "")).encode()[:72]
    with db().cursor() as c:
        c.execute("SELECT id, name, email, password_hash FROM users WHERE email = %s", (email,))
        user = c.fetchone()
    stored = user["password_hash"].encode() if user else DUMMY_HASH
    ok = bcrypt.checkpw(pw, stored) and user is not None
    if not ok:
        return err("invalid email or password", 401)  # same message for unknown email and wrong password
    sid = secrets.token_urlsafe(32)
    with db().cursor() as c:
        c.execute("DELETE FROM sessions WHERE expires_at < NOW()")
        c.execute(
            "INSERT INTO sessions (session_id, user_id, expires_at) "
            "VALUES (%s, %s, DATE_ADD(NOW(), INTERVAL %s HOUR))",
            (sid, user["id"], SESSION_HOURS),
        )
    db().commit()
    resp = jsonify(name=user["name"], email=user["email"])
    resp.set_cookie(
        "sid", sid, max_age=SESSION_HOURS * 3600, httponly=True,
        secure=COOKIE_SECURE, samesite="Lax", path="/",
    )
    return resp


@app.post("/api/auth/logout")
def logout():
    sid = request.cookies.get("sid")
    if sid:
        with db().cursor() as c:
            c.execute("DELETE FROM sessions WHERE session_id = %s", (sid,))
        db().commit()
    resp = jsonify(message="logged out")
    resp.delete_cookie("sid", path="/")
    return resp


@app.get("/api/auth/me")
@login_required
def me():
    return jsonify(name=g.user["name"], email=g.user["email"])


# ---------------- products ----------------
@app.get("/api/products")
def products():
    with db().cursor() as c:
        c.execute("SELECT id, name, price, stock FROM products ORDER BY id")
        return jsonify(c.fetchall())


# ---------------- cart ----------------
@app.get("/api/cart")
@login_required
def get_cart():
    with db().cursor() as c:
        c.execute(
            "SELECT p.id AS product_id, p.name, p.price, ci.quantity FROM cart_items ci "
            "JOIN products p ON p.id = ci.product_id WHERE ci.user_id = %s ORDER BY p.id",
            (g.user["id"],),
        )
        return jsonify(c.fetchall())


@app.post("/api/cart")
@login_required
def add_to_cart():
    d = request.get_json(silent=True) or {}
    try:
        product_id = int(d.get("product_id"))
        qty = int(d.get("quantity", 1))
    except (TypeError, ValueError):
        return err("invalid product or quantity", 400)
    if not 1 <= qty <= 20:
        return err("quantity must be 1 to 20", 400)
    with db().cursor() as c:
        c.execute("SELECT id FROM products WHERE id = %s", (product_id,))
        if not c.fetchone():
            return err("product not found", 404)
        c.execute(
            "INSERT INTO cart_items (user_id, product_id, quantity) VALUES (%s, %s, %s) AS new "
            "ON DUPLICATE KEY UPDATE quantity = LEAST(cart_items.quantity + new.quantity, 20)",
            (g.user["id"], product_id, qty),
        )
    db().commit()
    return jsonify(message="added"), 201


@app.delete("/api/cart/<int:product_id>")
@login_required
def remove_from_cart(product_id):
    with db().cursor() as c:
        c.execute(
            "DELETE FROM cart_items WHERE user_id = %s AND product_id = %s",
            (g.user["id"], product_id),
        )
    db().commit()
    return jsonify(message="removed")


# ---------------- orders ----------------
@app.post("/api/orders")
@login_required
def checkout():
    conn = db()
    uid = g.user["id"]
    try:
        with conn.cursor() as c:
            c.execute(
                "SELECT ci.product_id, ci.quantity, p.price, p.stock FROM cart_items ci "
                "JOIN products p ON p.id = ci.product_id WHERE ci.user_id = %s FOR UPDATE",
                (uid,),
            )
            items = c.fetchall()
            if not items:
                conn.rollback()
                return err("cart is empty", 400)
            for it in items:
                if it["quantity"] > it["stock"]:
                    conn.rollback()
                    return err("not enough stock for product %d" % it["product_id"], 409)
            total = sum(it["price"] * it["quantity"] for it in items)
            c.execute("INSERT INTO orders (user_id, total) VALUES (%s, %s)", (uid, total))
            order_id = c.lastrowid
            for it in items:
                c.execute(
                    "INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase) "
                    "VALUES (%s, %s, %s, %s)",
                    (order_id, it["product_id"], it["quantity"], it["price"]),
                )
                c.execute(
                    "UPDATE products SET stock = stock - %s WHERE id = %s",
                    (it["quantity"], it["product_id"]),
                )
            c.execute("DELETE FROM cart_items WHERE user_id = %s", (uid,))
        conn.commit()  # order, order items, stock and cart clear succeed or fail together
    except Exception:
        conn.rollback()
        raise
    return jsonify(order_id=order_id, total=total), 201


@app.get("/api/orders")
@login_required
def list_orders():
    with db().cursor() as c:
        c.execute(
            "SELECT o.id, o.total, o.status, o.created_at, p.name, oi.quantity, oi.price_at_purchase "
            "FROM orders o JOIN order_items oi ON oi.order_id = o.id "
            "JOIN products p ON p.id = oi.product_id WHERE o.user_id = %s ORDER BY o.id DESC",
            (g.user["id"],),
        )
        rows = c.fetchall()
    orders = {}
    for r in rows:
        o = orders.setdefault(
            r["id"],
            {"id": r["id"], "total": r["total"], "status": r["status"],
             "created_at": r["created_at"], "items": []},
        )
        o["items"].append({"name": r["name"], "quantity": r["quantity"], "price": r["price_at_purchase"]})
    return jsonify(list(orders.values()))
