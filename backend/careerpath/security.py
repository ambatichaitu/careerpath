import os
from typing import Optional, Dict, Any
from pydantic import BaseModel
from fastapi import Header, HTTPException, status, Depends
import firebase_admin
from firebase_admin import auth, credentials
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
from google.auth import exceptions as google_auth_exceptions

class AuthenticatedUser(BaseModel):
    uid: str
    email: str
    email_verified: bool = False
    claims: Dict[str, Any] = {}

def is_email_verification_enforced() -> bool:
    """
    Checks if email verification is mandatory in the current environment.
    Enforced by default (returns True) for production security.
    Can be explicitly configured to 'false' or '0' for academic demonstrations or
    environments where institutional quarantine filters prevent verification delivery.
    """
    override = os.getenv("REQUIRE_EMAIL_VERIFICATION", "").lower()
    if override in ("false", "0"):
        return False
    if override in ("true", "1"):
        return True
    return True

# ------------------------------------------------------------------------------
# Firebase Admin SDK Initialization
# ------------------------------------------------------------------------------
_firebase_initialized = False

def init_firebase_admin() -> bool:
    global _firebase_initialized
    if _firebase_initialized or firebase_admin._apps:
        _firebase_initialized = True
        return True

    cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "secrets/firebase_service_account.json")
    project_id = os.getenv("FIREBASE_PROJECT_ID", "careerpath-26fa0")

    try:
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            print(f"[SECURITY] Firebase Admin initialized using service account: {cred_path}")
        else:
            # Fallback initialization for environments utilizing Application Default Credentials (ADC) or project options
            firebase_admin.initialize_app(options={"projectId": project_id})
            print(f"[SECURITY] Firebase Admin initialized with project: {project_id}")
        _firebase_initialized = True
        return True
    except Exception as e:
        print(f"[SECURITY WARNING] Firebase Admin initialization notice: {e}")
        return False

# Initialize at module load
init_firebase_admin()

# ------------------------------------------------------------------------------
# Fast-API Dependency: Verify Firebase ID Token
# ------------------------------------------------------------------------------
async def get_current_user(authorization: Optional[str] = Header(None)) -> AuthenticatedUser:
    """
    Validates Firebase Bearer ID Token on protected endpoints.
    Extracts and returns the verified Firebase UID and email claims.
    Rejects missing or invalid tokens with HTTP 401 Unauthorized.
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required. Missing Bearer authorization header.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authorization format. Expected 'Bearer <token>'.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = parts[1].strip()

    try:
        decoded_token = auth.verify_id_token(token)
        return AuthenticatedUser(
            uid=decoded_token["uid"],
            email=decoded_token.get("email", ""),
            email_verified=decoded_token.get("email_verified", False),
            claims=decoded_token,
        )
    except auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has expired. Please refresh your session.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except auth.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Firebase ID token has been revoked.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as e:
        # Fallback to Google OAuth public certificate verification if service account credential is not locally configured
        if "DefaultCredentialsError" in str(type(e)) or "credentials were not found" in str(e).lower():
            try:
                project_id = os.getenv("FIREBASE_PROJECT_ID", "careerpath-26fa0")
                claims = google_id_token.verify_firebase_token(
                    token,
                    google_requests.Request(),
                    audience=project_id,
                )
                
                # Strict security verification: issuer, audience, and subject validation
                expected_issuer = f"https://securetoken.google.com/{project_id}"
                if claims.get("iss") != expected_issuer:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid token issuer: token does not match authorized project ID.",
                        headers={"WWW-Authenticate": "Bearer"},
                    )
                if claims.get("aud") != project_id:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid token audience: token was not issued for this project.",
                        headers={"WWW-Authenticate": "Bearer"},
                    )
                
                uid = claims.get("sub") or claims.get("user_id")
                if not uid:
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Invalid token: missing subject claim.",
                        headers={"WWW-Authenticate": "Bearer"},
                    )

                return AuthenticatedUser(
                    uid=uid,
                    email=claims.get("email", ""),
                    email_verified=claims.get("email_verified", False),
                    claims=claims,
                )
            except Exception as inner_e:
                if "expired" in str(inner_e).lower():
                    raise HTTPException(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Firebase ID token has expired. Please refresh your session.",
                        headers={"WWW-Authenticate": "Bearer"},
                    )
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid or unauthorized authentication token.",
                    headers={"WWW-Authenticate": "Bearer"},
                )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or unauthorized authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

async def get_current_verified_user(
    user: AuthenticatedUser = Depends(get_current_user)
) -> AuthenticatedUser:
    """
    Enforces verified email requirement on protected student endpoints when verification policy is active.
    Rejects unverified users with HTTP 403 Forbidden in production environments.
    """
    if is_email_verification_enforced() and not user.email_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email address not verified. Please verify your email before accessing student endpoints.",
        )
    return user
