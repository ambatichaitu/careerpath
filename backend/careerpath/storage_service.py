import os
import io
import uuid
import logging
from typing import Optional, Dict, Any, Tuple, List
from fastapi import HTTPException, status
from PIL import Image
import pymupdf as fitz

from database import (
    get_supabase_client,
    is_explicit_test_mode,
    create_file_record,
    get_file_record,
    delete_file_record,
    list_student_files,
    set_profile_image,
    get_profile_image_file_id,
    DatabaseUnavailableError
)

logger = logging.getLogger("careerpath.storage")

# -----------------------------------------------------------------------------
# Storage Constants & Configuration
# -----------------------------------------------------------------------------
RESUMES_BUCKET = "resumes"
PROFILE_IMAGES_BUCKET = "profile-images"

MAX_RESUME_SIZE = 5 * 1024 * 1024       # 5 MB
MAX_PROFILE_IMAGE_SIZE = 2 * 1024 * 1024 # 2 MB

MAX_PDF_PAGES = 15
MAX_IMAGE_DIMENSION = 4096
# Anti-decompression bomb limit: 16 megapixels max
Image.MAX_IMAGE_PIXELS = 16_000_000

# In-memory mock storage dictionary for isolated automated tests: "{bucket}/{path}" -> bytes
_mock_storage_objects: Dict[str, bytes] = {}

# -----------------------------------------------------------------------------
# Input Validation & Sanitization Helpers
# -----------------------------------------------------------------------------
def sanitize_filename(filename: str) -> str:
    """Strips path traversal elements, directory separators, and control characters."""
    base = os.path.basename(filename).strip()
    clean = "".join(c for c in base if c.isalnum() or c in (".", "_", "-", " "))
    return clean or "uploaded_document"

def validate_pdf_content(content: bytes, filename: str) -> None:
    """
    Validates uploaded resume PDF content:
    - Empty file check
    - File size limit (5 MB)
    - Magic bytes signature (%PDF-)
    - Extension check
    - PyMuPDF parseability, encryption, and page count limit
    """
    if not content or len(content) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file is empty. Please select a valid PDF resume."
        )

    if len(content) > MAX_RESUME_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"Resume file size ({len(content) / (1024*1024):.1f} MB) exceeds maximum allowed limit of 5 MB."
        )

    # Magic bytes check
    if not (content.startswith(b"%PDF-") or b"%PDF-" in content[:1024]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid file signature. Only standard PDF documents are accepted."
        )

    # Extension verification
    clean_name = sanitize_filename(filename).lower()
    if not clean_name.endswith(".pdf"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid file extension. Resume files must have a .pdf extension."
        )

    # PyMuPDF integrity verification
    try:
        doc = fitz.open(stream=content, filetype="pdf")
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Corrupted or malformed PDF resume cannot be parsed: {str(e)}"
        )

    if doc.is_encrypted:
        doc.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Encrypted or password-protected PDF resumes are not supported."
        )

    if doc.page_count == 0:
        doc.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="PDF document contains zero readable pages."
        )

    if doc.page_count > MAX_PDF_PAGES:
        pages = doc.page_count
        doc.close()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Resume page count ({pages}) exceeds maximum allowed limit of {MAX_PDF_PAGES} pages."
        )

    doc.close()

def validate_and_sanitize_image(content: bytes, filename: str) -> Tuple[bytes, str, str]:
    """
    Validates uploaded profile image:
    - Empty file check
    - File size limit (2 MB)
    - Validates image header and format (PNG or JPEG only)
    - Dimension checks (max 4096x4096)
    - Decompression bomb guard
    - Strips EXIF metadata & re-encodes safely to eliminate embedded payloads
    Returns: (clean_bytes, content_type, extension)
    """
    if not content or len(content) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded image is empty. Please select a valid profile photograph."
        )

    if len(content) > MAX_PROFILE_IMAGE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=f"Image file size ({len(content) / (1024*1024):.1f} MB) exceeds maximum allowed limit of 2 MB."
        )

    clean_name = sanitize_filename(filename).lower()
    allowed_exts = (".png", ".jpg", ".jpeg")
    if not any(clean_name.endswith(ext) for ext in allowed_exts):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid image extension. Profile images must have a .png, .jpg, or .jpeg extension."
        )

    try:
        img = Image.open(io.BytesIO(content))
        img_format = img.format.upper() if img.format else ""
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Corrupted or unreadable image file."
        )

    if img_format not in ("PNG", "JPEG"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported image format '{img_format}'. Only PNG and JPEG formats are permitted."
        )

    width, height = img.size
    if width > MAX_IMAGE_DIMENSION or height > MAX_IMAGE_DIMENSION:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Image dimensions ({width}x{height}) exceed maximum allowed {MAX_IMAGE_DIMENSION}x{MAX_IMAGE_DIMENSION} pixels."
        )

    # Re-encode to clean bytes, stripping EXIF and hidden metadata
    out_buf = io.BytesIO()
    if img_format == "JPEG":
        if img.mode not in ("RGB", "L"):
            img = img.convert("RGB")
        img.save(out_buf, format="JPEG", quality=90, optimize=True)
        content_type = "image/jpeg"
        ext = "jpg"
    else:  # PNG
        if img.mode not in ("RGB", "RGBA", "L"):
            img = img.convert("RGBA")
        img.save(out_buf, format="PNG", optimize=True)
        content_type = "image/png"
        ext = "png"

    return out_buf.getvalue(), content_type, ext

# -----------------------------------------------------------------------------
# Storage Service Core Methods
# -----------------------------------------------------------------------------
class StorageService:
    @staticmethod
    def upload_file_to_bucket(bucket: str, storage_path: str, content: bytes, content_type: str) -> None:
        """Uploads raw bytes to private Supabase Storage bucket."""
        client = get_supabase_client()
        if client is not None:
            try:
                client.storage.from_(bucket).upload(
                    path=storage_path,
                    file=content,
                    file_options={"content-type": content_type, "upsert": "false"}
                )
            except Exception as e:
                logger.error(f"Supabase Storage upload error ({bucket}/{storage_path}): {e}")
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail=f"Storage service failure uploading document: {str(e)}"
                )
        elif is_explicit_test_mode():
            key = f"{bucket}/{storage_path}"
            _mock_storage_objects[key] = content
        else:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase Storage service is unavailable."
            )

    @staticmethod
    def remove_file_from_bucket(bucket: str, storage_path: str) -> None:
        """Deletes file object from private Supabase Storage bucket."""
        client = get_supabase_client()
        if client is not None:
            try:
                client.storage.from_(bucket).remove([storage_path])
            except Exception as e:
                logger.warning(f"Storage object deletion notice ({bucket}/{storage_path}): {e}")
        elif is_explicit_test_mode():
            key = f"{bucket}/{storage_path}"
            _mock_storage_objects.pop(key, None)

    @staticmethod
    def get_signed_url(bucket: str, storage_path: str, expires_in: int = 60) -> str:
        """Generates a short-lived signed access URL (default 60 seconds) for private objects."""
        client = get_supabase_client()
        if client is not None:
            try:
                res = client.storage.from_(bucket).create_signed_url(storage_path, expires_in)
                url = res.get("signedURL") or res.get("signedUrl")
                if not url:
                    raise Exception("No signedURL returned by storage client")
                return url
            except Exception as e:
                logger.error(f"Error generating signed URL ({bucket}/{storage_path}): {e}")
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Could not generate secure file access token."
                )
        elif is_explicit_test_mode():
            return f"https://mock-storage.local/{bucket}/{storage_path}?token=mock_jwt&expires={expires_in}"
        else:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase Storage service is unavailable."
            )

    @staticmethod
    def download_file_bytes(bucket: str, storage_path: str) -> bytes:
        """Downloads object bytes from private bucket."""
        client = get_supabase_client()
        if client is not None:
            try:
                return client.storage.from_(bucket).download(storage_path)
            except Exception as e:
                logger.error(f"Error downloading file ({bucket}/{storage_path}): {e}")
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Requested file could not be retrieved from storage."
                )
        elif is_explicit_test_mode():
            key = f"{bucket}/{storage_path}"
            if key in _mock_storage_objects:
                return _mock_storage_objects[key]
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Requested file not found in test storage."
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Supabase Storage service is unavailable."
            )

    # -------------------------------------------------------------------------
    # Composite Operations: Resume Upload with Rollback Safety
    # -------------------------------------------------------------------------
    @classmethod
    def save_student_resume(
        cls,
        firebase_uid: str,
        content: bytes,
        original_filename: str
    ) -> Dict[str, Any]:
        """
        Validates, uploads to private resumes bucket, and writes PostgreSQL metadata.
        Rolls back storage upload if metadata write fails (Task 11).
        """
        validate_pdf_content(content, original_filename)
        safe_name = sanitize_filename(original_filename)

        file_id = str(uuid.uuid4())
        # Safe storage path: <verified-firebase-uid>/<uuid4>.pdf
        storage_path = f"{firebase_uid}/{file_id}.pdf"

        # Step 1: Upload to private resumes bucket
        cls.upload_file_to_bucket(
            bucket=RESUMES_BUCKET,
            storage_path=storage_path,
            content=content,
            content_type="application/pdf"
        )

        # Step 2: Write metadata to PostgreSQL (student_files)
        file_record = {
            "id": file_id,
            "firebase_uid": firebase_uid,
            "bucket_name": RESUMES_BUCKET,
            "storage_path": storage_path,
            "original_filename": safe_name,
            "content_type": "application/pdf",
            "file_size_bytes": len(content),
            "file_category": "resume",
            "upload_status": "completed"
        }

        try:
            saved_record = create_file_record(file_record)
            return saved_record
        except Exception as e:
            # Rollback: Clean up storage object on metadata failure
            logger.error(f"Rolling back storage object due to database error: {e}")
            cls.remove_file_from_bucket(RESUMES_BUCKET, storage_path)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error recording file metadata. Storage object was safely rolled back."
            )

    # -------------------------------------------------------------------------
    # Composite Operations: Profile Image Upload with Replacement Safety
    # -------------------------------------------------------------------------
    @classmethod
    def save_student_profile_image(
        cls,
        firebase_uid: str,
        content: bytes,
        original_filename: str
    ) -> Dict[str, Any]:
        """
        Validates, sanitizes, uploads image to profile-images bucket, and links to profile.
        Safely removes old profile image if replacement is occurring (Task 11).
        """
        clean_bytes, content_type, ext = validate_and_sanitize_image(content, original_filename)
        safe_name = sanitize_filename(original_filename)

        file_id = str(uuid.uuid4())
        # Safe storage path: <verified-firebase-uid>/<uuid4>.<ext>
        storage_path = f"{firebase_uid}/{file_id}.{ext}"

        # Check existing profile image for safe cleanup later
        old_file_id = get_profile_image_file_id(firebase_uid)
        old_record = get_file_record(old_file_id, firebase_uid) if old_file_id else None

        # Step 1: Upload new image
        cls.upload_file_to_bucket(
            bucket=PROFILE_IMAGES_BUCKET,
            storage_path=storage_path,
            content=clean_bytes,
            content_type=content_type
        )

        # Step 2: Write metadata
        file_record = {
            "id": file_id,
            "firebase_uid": firebase_uid,
            "bucket_name": PROFILE_IMAGES_BUCKET,
            "storage_path": storage_path,
            "original_filename": safe_name,
            "content_type": content_type,
            "file_size_bytes": len(clean_bytes),
            "file_category": "profile_image",
            "upload_status": "completed"
        }

        try:
            saved_record = create_file_record(file_record)
            set_profile_image(firebase_uid, file_id)

            # Step 3: Clean up previous image if replacing
            if old_record:
                cls.remove_file_from_bucket(old_record["bucket_name"], old_record["storage_path"])
                delete_file_record(old_record["id"], firebase_uid)

            return saved_record
        except Exception as e:
            logger.error(f"Rolling back image object due to database error: {e}")
            cls.remove_file_from_bucket(PROFILE_IMAGES_BUCKET, storage_path)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error updating profile image. Uploaded image was safely rolled back."
            )

    # -------------------------------------------------------------------------
    # Composite Operations: Deletions
    # -------------------------------------------------------------------------
    @classmethod
    def delete_resume_file(cls, file_id: str, firebase_uid: str) -> bool:
        """Verifies ownership and removes resume from storage and metadata."""
        record = get_file_record(file_id, firebase_uid)
        if not record or record.get("file_category") != "resume":
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Resume record not found or not owned by student."
            )

        cls.remove_file_from_bucket(record["bucket_name"], record["storage_path"])
        return delete_file_record(file_id, firebase_uid)

    @classmethod
    def delete_profile_image_file(cls, firebase_uid: str) -> bool:
        """Removes current profile image from storage and resets profile pointer."""
        file_id = get_profile_image_file_id(firebase_uid)
        if not file_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No profile image currently set for student."
            )

        record = get_file_record(file_id, firebase_uid)
        if record:
            cls.remove_file_from_bucket(record["bucket_name"], record["storage_path"])
            delete_file_record(file_id, firebase_uid)

        set_profile_image(firebase_uid, None)
        return True
