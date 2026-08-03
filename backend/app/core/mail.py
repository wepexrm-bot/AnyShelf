"""Email delivery for verification / password-reset links.

In development (no SMTP configured) links are logged and returned by the
auth routes so the flow works end to end. When `settings.smtp_host` is set,
email is sent via SMTP instead.
"""

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger("Anyshelf.mail")


def send_email(to: str, subject: str, html: str) -> bool:
    """Send an HTML email. Returns True if sent (or queued in dev)."""
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
