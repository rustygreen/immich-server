#!/usr/bin/env python3
"""
Immich Import Watcher
Watches directories for new files and imports them to Immich using the correct user's API key.
Supports ZIP files including Google Takeout exports.

Users are configured via environment variables:
  IMPORT_USER_RUSTY=api-key-here
  IMPORT_USER_LAUREN=api-key-here
"""

import os
import sys
import time
import yaml
import logging
import requests
import zipfile
import shutil
from pathlib import Path
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Supported file extensions
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.tiff', '.tif', '.bmp', '.raw', '.arw', '.cr2', '.nef', '.orf', '.raf', '.dng'}
VIDEO_EXTENSIONS = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.mts', '.m2ts', '.mpg', '.mpeg'}
SUPPORTED_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS

# How long a file must be unchanged before processing (seconds)
FILE_STABILITY_SECONDS = 5

# Files/patterns to remove from Google Takeout
TAKEOUT_JUNK_FILES = {
    'archive_browser.html',
    'print-subscriptions.json',
    'shared_album_comments.json',
    'user-generated-memory-titles.json',
    'metadata.json',
}


def load_config(config_path: str) -> dict:
    """Load configuration from YAML file."""
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def get_users_from_env() -> dict:
    """Load user mappings from IMPORT_USER_* environment variables."""
    users = {}
    prefix = 'IMPORT_USER_'
    
    for key, value in os.environ.items():
        if key.startswith(prefix) and value:
            username = key[len(prefix):].lower()
            users[username] = value
            
    return users


def is_file_stable(file_path: Path, stability_seconds: int = FILE_STABILITY_SECONDS) -> bool:
    """Check if a file has stopped being written to (size unchanged for stability_seconds)."""
    try:
        if not file_path.exists():
            return False
        
        initial_size = file_path.stat().st_size
        initial_mtime = file_path.stat().st_mtime
        
        # If file was modified very recently, it might still be copying
        if time.time() - initial_mtime < stability_seconds:
            return False
        
        # Double-check by waiting a moment and comparing
        time.sleep(1)
        
        if not file_path.exists():
            return False
            
        current_size = file_path.stat().st_size
        
        # Size changed = still copying
        if current_size != initial_size:
            return False
        
        # File with 0 bytes is likely still being created
        if current_size == 0:
            return False
            
        return True
        
    except (OSError, IOError):
        return False


def is_google_takeout(extract_dir: Path) -> bool:
    """Check if an extracted directory is a Google Takeout export."""
    # Check for typical Takeout structure
    if (extract_dir / 'Takeout').exists():
        return True
    if (extract_dir / 'Google Photos').exists():
        return True
    
    # Check for JSON metadata files alongside photos (Takeout pattern)
    json_files = list(extract_dir.rglob('*.json'))[:10]  # Sample first 10
    if json_files:
        media_files = list(extract_dir.rglob('*.jpg'))[:5] + list(extract_dir.rglob('*.mp4'))[:5]
        if media_files:
            # Check if JSON files follow Takeout naming pattern (e.g., IMG_1234.jpg.json)
            for json_file in json_files:
                if json_file.stem.endswith(('.jpg', '.jpeg', '.png', '.heic', '.mp4', '.mov')):
                    return True
    
    return False


def cleanup_google_takeout(extract_dir: Path) -> int:
    """
    Clean up a Google Takeout export:
    - Remove JSON metadata files
    - Remove junk files
    - Flatten directory structure
    Returns the number of media files found.
    """
    logger.info(f"  Cleaning up Google Takeout export...")
    
    # Find the actual photos directory
    photos_dir = extract_dir
    if (extract_dir / 'Takeout' / 'Google Photos').exists():
        photos_dir = extract_dir / 'Takeout' / 'Google Photos'
    elif (extract_dir / 'Takeout').exists():
        photos_dir = extract_dir / 'Takeout'
    elif (extract_dir / 'Google Photos').exists():
        photos_dir = extract_dir / 'Google Photos'
    
    # Remove JSON metadata files
    json_count = 0
    for json_file in photos_dir.rglob('*.json'):
        try:
            json_file.unlink()
            json_count += 1
        except OSError:
            pass
    logger.info(f"  Removed {json_count} JSON metadata files")
    
    # Remove known junk files
    for junk_file in extract_dir.rglob('*'):
        if junk_file.name in TAKEOUT_JUNK_FILES:
            try:
                junk_file.unlink()
            except OSError:
                pass
    
    # Collect all media files
    media_files = []
    for ext in SUPPORTED_EXTENSIONS:
        media_files.extend(photos_dir.rglob(f'*{ext}'))
        media_files.extend(photos_dir.rglob(f'*{ext.upper()}'))
    
    # Move media files to extract_dir root (flatten structure)
    moved_count = 0
    for media_file in media_files:
        if media_file.parent == extract_dir:
            continue  # Already in root
        
        target = extract_dir / media_file.name
        
        # Handle duplicate filenames
        if target.exists():
            counter = 1
            stem = media_file.stem
            suffix = media_file.suffix
            while target.exists():
                target = extract_dir / f"{stem}_{counter}{suffix}"
                counter += 1
        
        try:
            shutil.move(str(media_file), str(target))
            moved_count += 1
        except OSError as e:
            logger.warning(f"  Failed to move {media_file.name}: {e}")
    
    if moved_count > 0:
        logger.info(f"  Moved {moved_count} files to root directory")
    
    # Clean up empty directories and Takeout structure
    if photos_dir != extract_dir and photos_dir.exists():
        try:
            shutil.rmtree(photos_dir)
        except OSError:
            pass
    
    # Remove Takeout directory if it still exists
    takeout_dir = extract_dir / 'Takeout'
    if takeout_dir.exists():
        try:
            shutil.rmtree(takeout_dir)
        except OSError:
            pass
    
    # Remove any remaining empty directories
    for dir_path in sorted(extract_dir.rglob('*'), reverse=True):
        if dir_path.is_dir():
            try:
                dir_path.rmdir()  # Only removes if empty
            except OSError:
                pass
    
    # Count remaining media files
    final_count = sum(1 for f in extract_dir.iterdir() if f.is_file() and f.suffix.lower() in SUPPORTED_EXTENSIONS)
    logger.info(f"  Google Takeout cleanup complete. {final_count} media files ready.")
    
    return final_count


def extract_zip_file(zip_path: Path, user_dir: Path) -> Path | None:
    """
    Extract a ZIP file to a subdirectory.
    Returns the extraction directory path, or None if extraction failed.
    """
    extract_dir = user_dir / f"_extracted_{zip_path.stem}_{int(time.time())}"
    
    try:
        # Validate ZIP file
        if not zipfile.is_zipfile(zip_path):
            logger.error(f"Invalid ZIP file: {zip_path.name}")
            return None
        
        file_size = zip_path.stat().st_size
        size_str = f"{file_size / (1024*1024*1024):.2f} GB" if file_size > 1024*1024*1024 else f"{file_size / (1024*1024):.1f} MB"
        logger.info(f"Extracting: {zip_path.name} ({size_str})")
        
        extract_dir.mkdir(parents=True, exist_ok=True)
        
        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Check for zip bombs (extreme compression ratio)
            total_size = sum(info.file_size for info in zf.infolist())
            if total_size > file_size * 100 and total_size > 10 * 1024 * 1024 * 1024:  # 100x ratio and > 10GB
                logger.warning(f"Suspicious compression ratio in {zip_path.name}, proceeding with caution")
            
            zf.extractall(extract_dir)
        
        logger.info(f"✓ Extracted: {zip_path.name}")
        return extract_dir
        
    except zipfile.BadZipFile:
        logger.error(f"Corrupted ZIP file: {zip_path.name}")
        if extract_dir.exists():
            shutil.rmtree(extract_dir, ignore_errors=True)
        return None
    except Exception as e:
        logger.error(f"Error extracting {zip_path.name}: {e}")
        if extract_dir.exists():
            shutil.rmtree(extract_dir, ignore_errors=True)
        return None


def process_zip_files(user_dir: Path, delete_after: bool) -> int:
    """
    Find and extract ZIP files in user directory.
    Returns the number of ZIP files processed.
    """
    zip_files = [f for f in user_dir.iterdir() if f.is_file() and f.suffix.lower() == '.zip']
    
    if not zip_files:
        return 0
    
    processed = 0
    for zip_path in zip_files:
        # Skip if file is still being written
        if not is_file_stable(zip_path, stability_seconds=10):  # Longer wait for large ZIPs
            logger.debug(f"Skipping ZIP (still copying): {zip_path.name}")
            continue
        
        # Extract the ZIP
        extract_dir = extract_zip_file(zip_path, user_dir)
        if extract_dir is None:
            continue
        
        # Check if it's a Google Takeout and clean it up
        if is_google_takeout(extract_dir):
            logger.info(f"  Detected Google Takeout export")
            cleanup_google_takeout(extract_dir)
        
        # Delete original ZIP file
        if delete_after:
            try:
                zip_path.unlink()
                logger.info(f"  Deleted ZIP file: {zip_path.name}")
            except OSError as e:
                logger.warning(f"  Failed to delete ZIP: {e}")
        
        processed += 1
    
    return processed


def upload_file(file_path: Path, api_key: str, immich_url: str) -> bool:
    """Upload a file to Immich using the API."""
    try:
        url = f"{immich_url}/api/assets"
        
        headers = {
            'x-api-key': api_key,
            'Accept': 'application/json'
        }
        
        # Get file stats for metadata
        stat = file_path.stat()
        modified_time = datetime.fromtimestamp(stat.st_mtime).isoformat()
        
        with open(file_path, 'rb') as f:
            files = {
                'assetData': (file_path.name, f, 'application/octet-stream')
            }
            data = {
                'deviceAssetId': f"{file_path.name}-{stat.st_mtime}",
                'deviceId': 'import-watch',
                'fileCreatedAt': modified_time,
                'fileModifiedAt': modified_time,
                'isFavorite': 'false'
            }
            
            response = requests.post(url, headers=headers, files=files, data=data, timeout=300)
        
        if response.status_code in (200, 201):
            result = response.json()
            if result.get('duplicate'):
                logger.info(f"Duplicate skipped: {file_path.name}")
            else:
                logger.info(f"Uploaded: {file_path.name}")
            return True
        else:
            logger.error(f"Upload failed for {file_path.name}: {response.status_code} - {response.text}")
            return False
            
    except requests.exceptions.Timeout:
        logger.error(f"Timeout uploading {file_path.name}")
        return False
    except Exception as e:
        logger.error(f"Error uploading {file_path.name}: {e}")
        return False


def process_directory(user_dir: Path, api_key: str, immich_url: str, delete_after: bool) -> tuple[int, int]:
    """Process all files in a user's directory. Returns (uploaded, skipped) counts."""
    uploaded = 0
    skipped = 0
    
    # Collect all files first (as a list) to avoid iterator issues when deleting
    all_files = [f for f in user_dir.rglob('*') if f.is_file()]
    
    for file_path in all_files:
        # Skip if file was already deleted (e.g., by previous iteration)
        if not file_path.exists():
            continue
            
        # Skip hidden files and temp files
        if file_path.name.startswith('.') or file_path.name.startswith('~'):
            continue
            
        # Check if supported extension
        if file_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            logger.debug(f"Skipping unsupported file: {file_path.name}")
            continue
        
        # Wait for file to be stable (not actively being written)
        if not is_file_stable(file_path):
            logger.debug(f"Skipping (still copying): {file_path.name}")
            skipped += 1
            continue
        
        # Try to upload
        if upload_file(file_path, api_key, immich_url):
            uploaded += 1
            if delete_after:
                try:
                    file_path.unlink()
                    logger.info(f"Deleted: {file_path.name}")
                    
                    # Clean up empty directories (only if directory is truly empty)
                    parent = file_path.parent
                    while parent != user_dir and parent.exists():
                        try:
                            # Double-check directory is empty before removing
                            contents = list(parent.iterdir())
                            if not contents:
                                parent.rmdir()
                                logger.debug(f"Removed empty directory: {parent}")
                            else:
                                break  # Directory has contents, stop cleanup
                        except OSError:
                            break
                        parent = parent.parent
                except Exception as e:
                    logger.error(f"Error deleting {file_path.name}: {e}")
    
    return uploaded, skipped


def main():
    config_path = os.environ.get('CONFIG_PATH', '/config/config.yaml')
    
    logger.info("Starting Immich Import Watcher")
    logger.info(f"Loading config from: {config_path}")
    
    config = load_config(config_path)
    
    watch_dir = Path(config['watch_dir'])
    immich_url = os.environ.get('IMPORT_IMMICH_URL', config.get('immich_url', 'http://immich:2283'))
    scan_interval = int(os.environ.get('IMPORT_SCAN_INTERVAL', config.get('scan_interval', 30)))
    delete_after = os.environ.get('IMPORT_DELETE_AFTER', str(config.get('delete_after_import', True))).lower() == 'true'
    
    # Load users from environment variables
    users = get_users_from_env()
    
    if not users:
        logger.error("No users configured! Add IMPORT_USER_<NAME>=<api_key> to your .env file")
        logger.error("Example: IMPORT_USER_RUSTY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
        sys.exit(1)
    
    logger.info(f"Watch directory: {watch_dir}")
    logger.info(f"Immich URL: {immich_url}")
    logger.info(f"Scan interval: {scan_interval}s")
    logger.info(f"Delete after import: {delete_after}")
    logger.info(f"Configured users: {list(users.keys())}")
    
    # Create user directories if they don't exist
    for username in users.keys():
        user_dir = watch_dir / username
        user_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Watching: {user_dir}")
    
    # Main loop
    while True:
        try:
            total_uploaded = 0
            total_skipped = 0
            total_zips = 0
            
            for username, api_key in users.items():
                user_dir = watch_dir / username
                
                if not user_dir.exists():
                    continue
                
                # First, process any ZIP files (extract them)
                zips_processed = process_zip_files(user_dir, delete_after)
                total_zips += zips_processed
                
                # Check if there are any files to upload
                files = list(user_dir.rglob('*'))
                file_count = sum(1 for f in files if f.is_file() and not f.name.startswith('.') and f.suffix.lower() != '.zip')
                
                if file_count > 0:
                    logger.info(f"Processing {file_count} files for {username}...")
                    uploaded, skipped = process_directory(user_dir, api_key, immich_url, delete_after)
                    total_uploaded += uploaded
                    total_skipped += skipped
            
            if total_zips > 0:
                logger.info(f"Extracted {total_zips} ZIP file(s)")
            if total_uploaded > 0 or total_skipped > 0:
                logger.info(f"Scan complete. Uploaded: {total_uploaded}, Still copying: {total_skipped}")
            
        except Exception as e:
            logger.error(f"Error during scan: {e}")
        
        time.sleep(scan_interval)

if __name__ == '__main__':
    main()
