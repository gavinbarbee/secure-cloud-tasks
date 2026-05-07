"""
secure-cloud-tasks — minimal Flask API backed by PostgreSQL (SQLAlchemy 2.x).

Environment:
  DATABASE_URL — SQLAlchemy URL, e.g. postgresql+psycopg2://user:pass@host:5432/dbname
  FLASK_ENV    — optional; "development" enables debug-ish error surfaces (not for prod).

This module is intentionally small and readable for portfolio / interview walkthroughs.
"""

from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from typing import Any, Optional, Tuple

from flask import Flask, jsonify, render_template, request
from sqlalchemy import Boolean, DateTime, Integer, String, Text, create_engine, select
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=_utcnow,
        onupdate=_utcnow,
    )


def create_app() -> Flask:
    app = Flask(__name__)

    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required (set by systemd EnvironmentFile on EC2).")

    engine = create_engine(database_url, pool_pre_ping=True)
    SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)

    # RDS may not accept connections for a short window after user-data starts; retry so Gunicorn
    # workers do not exit immediately (which surfaces as ALB 502 + unhealthy targets).
    # User-data already waits for RDS and runs `import app` once; keep a short retry window for workers.
    for attempt in range(1, 16):
        try:
            Base.metadata.create_all(bind=engine)
            break
        except OperationalError:
            if attempt >= 15:
                raise
            time.sleep(4)

    def _session() -> Session:
        return SessionLocal()

    @app.get("/")
    def index() -> Any:
        return render_template("index.html")

    @app.get("/health")
    def health() -> Tuple[dict, int]:
        """ALB health checks hit this path; keep it cheap and dependency-free."""
        return {"status": "ok"}, 200

    @app.get("/tasks")
    def list_tasks() -> Any:
        with _session() as session:
            rows = session.scalars(select(Task).order_by(Task.id.asc())).all()
            return jsonify([_task_to_dict(t) for t in rows]), 200

    @app.post("/tasks")
    def create_task() -> Any:
        payload = request.get_json(silent=True) or {}
        title = (payload.get("title") or "").strip()
        if not title:
            return jsonify({"error": "title is required"}), 400

        task = Task(
            title=title,
            description=(payload.get("description") or "").strip() or None,
            completed=bool(payload.get("completed", False)),
        )

        with _session() as session:
            session.add(task)
            try:
                session.commit()
            except IntegrityError:
                session.rollback()
                return jsonify({"error": "could not create task"}), 409
            session.refresh(task)
            return jsonify(_task_to_dict(task)), 201

    @app.get("/tasks/<int:task_id>")
    def get_task(task_id: int) -> Any:
        with _session() as session:
            task = session.get(Task, task_id)
            if task is None:
                return jsonify({"error": "not found"}), 404
            return jsonify(_task_to_dict(task)), 200

    @app.put("/tasks/<int:task_id>")
    def update_task(task_id: int) -> Any:
        payload = request.get_json(silent=True) or {}

        with _session() as session:
            task = session.get(Task, task_id)
            if task is None:
                return jsonify({"error": "not found"}), 404

            if "title" in payload:
                title = (payload.get("title") or "").strip()
                if not title:
                    return jsonify({"error": "title cannot be empty"}), 400
                task.title = title

            if "description" in payload:
                desc = payload.get("description")
                task.description = None if desc in (None, "") else str(desc)

            if "completed" in payload:
                task.completed = bool(payload.get("completed"))

            task.updated_at = _utcnow()

            session.add(task)
            session.commit()
            session.refresh(task)
            return jsonify(_task_to_dict(task)), 200

    @app.delete("/tasks/<int:task_id>")
    def delete_task(task_id: int) -> Any:
        with _session() as session:
            task = session.get(Task, task_id)
            if task is None:
                return jsonify({"error": "not found"}), 404
            session.delete(task)
            session.commit()
            return "", 204

    return app


def _task_to_dict(task: Task) -> dict[str, Any]:
    return {
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "completed": task.completed,
        "created_at": task.created_at.isoformat() if task.created_at else None,
        "updated_at": task.updated_at.isoformat() if task.updated_at else None,
    }


# Gunicorn entrypoint: `gunicorn app:app`
app = create_app()
