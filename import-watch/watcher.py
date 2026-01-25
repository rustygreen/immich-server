#!/usr/bin/env python3
"""
Immich Import Watcher
Watches directories for new files and imports them to Immich using the correct user's API key.

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
from pathlib import Path
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Supported file extensions
IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif', '.tiff', '.tif', '.bmp', '.raw', '.arw', '.cr2', '.nef', '.orf', '.raf', '.dng'}
VIDEO_EXTENSIONS = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v', '.3gp', '.mts', '.m2ts'}
SUPPORTED_EXTENSIONS = IMAGE_EXTENSIONS | VIDEO_EXTENSIONS


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


def process_directory(user_dir: Path, api_key: str, immich_url: str, delete_after: bool) -> int:
    """Process all files in a user's directory."""
    uploaded = 0
    
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
        
        # Try to upload
        if upload_file(file_path, api_key, immich_url):
            uploaded += 1
            if delete_after:
                try:
                    file_path.unlink()
                    logger.info(f"Deleted: {file_path.name}")
                    
                    # Clean up empty directories
                    parent = file_path.parent
                    while parent != user_dir and parent.exists():
                        try:
                            if not any(parent.iterdir()):
                                parent.rmdir()
                                logger.debug(f"Removed empty directory: {parent}")
                        except OSError:
                            break
                        parent = parent.parent
                except Exception as e:
                    logger.error(f"Error deleting {file_path.name}: {e}")
    
    return uploaded


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
            
            for username, api_key in users.items():
                user_dir = watch_dir / username
                
                if not user_dir.exists():
                    continue
                
                # Check if there are any files
                files = list(user_dir.rglob('*'))
                file_count = sum(1 for f in files if f.is_file() and not f.name.startswith('.'))
                
                if file_count > 0:
                    logger.info(f"Processing {file_count} files for {username}...")
                    uploaded = process_directory(user_dir, api_key, immich_url, delete_after)
                    total_uploaded += uploaded
            
            if total_uploaded > 0:
                logger.info(f"Scan complete. Uploaded {total_uploaded} files.")
            
        except Exception as e:
            logger.error(f"Error during scan: {e}")
        
        time.sleep(scan_interval)


if __name__ == '__main__':
    main()
