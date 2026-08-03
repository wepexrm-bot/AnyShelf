"""Email delivery for verification / password-reset links.

In development (no SMTP/Resend configured) links are logged and returned by
the auth routes so the flow works end to end. When `settings.resend_api_key`
is set, email is sent via the Resend HTTP API (reliable on cloud hosts that
block outbound SMTP). Otherwise plain SMTP is used as a fallback.
"""

import json
import logging
import smtplib
import urllib.error
import urllib.request
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger("Anyshelf.mail")


def send_email(to: str, subject: str, html: str) -> bool:
    """Send an HTML email. Returns True if sent (or queued in dev)."""
    if settings.resend_api_key:
        return _send_via_resend_api(to, subject, html)
    if settings.brevo_api_key:
        return _send_via_brevo_api(to, subject, html)
    return _send_via_smtp(to, subject, html)


def _send_via_resend_api(to: str, subject: str, html: str) -> bool:
    payload = {
        "from": settings.smtp_from,
        "to": [to],
        "subject": subject,
        "html": html,
    }
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {settings.resend_api_key}",
            "Content-Type": "application/json",
            "User-Agent": "anyshelf-backend/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status != 200:
                logger.error(
                    "Resend API returned %s for %s: %s",
                    resp.status,
                    to,
                    resp.read().decode("utf-8", "replace"),
                )
                return False
            return True
    except urllib.error.HTTPError as exc:
        logger.error(
            "Resend API HTTP %s for %s: %s",
            exc.code,
            to,
            exc.read().decode("utf-8", "replace"),
        )
        return False
    except Exception as exc:
        logger.error("Failed to send email via Resend API to %s: %s", to, exc)
        return False


def _send_via_brevo_api(to: str, subject: str, html: str) -> bool:
    sender = settings.smtp_from or f"Anyshelf <{to}>"
    payload = {
        "sender": _parse_address(sender),
        "to": [_parse_address(to)],
        "subject": subject,
        "htmlContent": html,
    }
    req = urllib.request.Request(
        "https://api.brevo.com/v3/smtp/email",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "api-key": settings.brevo_api_key,
            "Content-Type": "application/json",
            "User-Agent": "anyshelf-backend/1.0",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            if resp.status not in (200, 201):
                logger.error(
                    "Brevo API returned %s for %s: %s",
                    resp.status,
                    to,
                    resp.read().decode("utf-8", "replace"),
                )
                return False
            return True
    except urllib.error.HTTPError as exc:
        logger.error(
            "Brevo API HTTP %s for %s: %s",
            exc.code,
            to,
            exc.read().decode("utf-8", "replace"),
        )
        return False
    except Exception as exc:
        logger.error("Failed to send email via Brevo API to %s: %s", to, exc)
        return False


def _parse_address(addr: str) -> dict:
    import email.utils

    name, email = email.utils.parseaddr(addr)
    return {"name": name or "", "email": email}


def _send_via_smtp(to: str, subject: str, html: str) -> bool:
    if not settings.smtp_host:
        # Dev mode: log the content so it's visible in the console.
        logger.info("EMAIL(to=%s) subject=%s\n%s", to, subject, html)
        return False  # not actually sent

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from
    msg["To"] = to
    msg.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as server:
            server.starttls()
            if settings.smtp_user:
                server.login(settings.smtp_user, settings.smtp_password)
            server.sendmail(settings.smtp_from, [to], msg.as_string())
        return True
    except Exception as exc:
        logger.error("Failed to send email to %s: %s", to, exc)
        return False


def render_button_link(text: str, url: str) -> str:
    return (
        "<div style='font-family:sans-serif;margin:0;padding:24px;background:#fcf9f8'>"
        "<p style='font-family:Georgia,serif;font-size:18px;color:#1b1c1c'>Anyshelf</p>"
        "<p style='color:#42493e'>%s</p>"
        "<a href='%s' style='display:inline-block;margin-top:12px;padding:12px 24px;"
        "background:#154212;color:#ffffff;text-decoration:none;border-radius:6px'>%s</a>"
        "</div>"
    ) % (text, url, text)


def render_code_email(code: str, purpose: str = "sign up") -> str:
    """Email body that displays a 6-digit verification code prominently."""
    return (
        "<div style='font-family:sans-serif;margin:0;padding:24px;background:#fcf9f8'>"
        "<p style='font-family:Georgia,serif;font-size:18px;color:#1b1c1c'>Anyshelf</p>"
        "<p style='color:#42493e'>Use this verification code to %s:</p>"
        "<div style='margin:16px 0;padding:16px;background:#f0eded;border-radius:8px;"
        "font-size:28px;font-weight:bold;letter-spacing:10px;color:#154212;text-align:center'>%s</div>"
        "<p style='color:#72796e;font-size:12px'>This code expires in 60 minutes.</p>"
        "</div>"
    ) % (purpose, code)
