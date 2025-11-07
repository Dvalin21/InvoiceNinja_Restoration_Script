#!/bin/bash
# InvoiceNinja Restoration Script with Backup Selection
set -e # Exit on any error

# Configuration
ARCHIVE_DIR="/home/invoiceninja/backups" # Directory containing backup archives (no trailing slash)
IN_APP_CONTAINER="debian-app-1" # Change to your app container name
IN_DB_CONTAINER="debian-mysql-1" # Change to your database container name
DB_BACKUP_FILE="db_backup.sql.gz" # Your database backup file
BACKUP_PATTERN="*.tar.gz" # Pattern for backup files (adjust if needed, e.g., "*.zip")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting InvoiceNinja Restoration with Backup Selection...${NC}"

# Remove any double slashes from path and ensure no trailing slash
ARCHIVE_DIR=$(echo "$ARCHIVE_DIR" | sed 's#//#/#g')
ARCHIVE_DIR="${ARCHIVE_DIR%/}"

echo -e "${YELLOW}Using archive directory: $ARCHIVE_DIR${NC}"

# Check if archive directory exists
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo -e "${RED}Archive directory not found: $ARCHIVE_DIR${NC}"
    echo -e "${YELLOW}Available directories in /home/invoiceninja/:${NC}"
    ls -la "/home/invoiceninja/" 2>/dev/null || echo "Cannot access /home/invoiceninja/"
    exit 1
fi

# Find backup archives
mapfile -t archives < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "$BACKUP_PATTERN" | sort)

if [ ${#archives[@]} -eq 0 ]; then
    echo -e "${RED}No backup archives found in $ARCHIVE_DIR matching $BACKUP_PATTERN${NC}"
    echo -e "${YELLOW}Contents of archive directory:${NC}"
    ls -la "$ARCHIVE_DIR"
    exit 1
fi

# Display selection menu
echo -e "${YELLOW}Available backups:${NC}"
select chosen_archive in "${archives[@]}"; do
    if [[ -n "$chosen_archive" ]]; then
        echo -e "${GREEN}Selected backup: $chosen_archive${NC}"
        break
    else
        echo -e "${RED}Invalid selection. Please choose a number from the list.${NC}"
    fi
done

# Create temporary directory for decompression
temp_dir="/tmp/in_restore_$$"
mkdir -p "$temp_dir"
trap 'rm -rf "$temp_dir"' EXIT  # Cleanup on exit

# Decompress the chosen archive
echo -e "${YELLOW}Decompressing selected backup...${NC}"
if [[ "$chosen_archive" == *.tar.gz ]]; then
    tar -xzf "$chosen_archive" -C "$temp_dir"
elif [[ "$chosen_archive" == *.zip ]]; then
    unzip -q "$chosen_archive" -d "$temp_dir"
else
    echo -e "${RED}Unsupported archive format. Please adjust BACKUP_PATTERN.${NC}"
    exit 1
fi
echo -e "${GREEN}Decompression complete.${NC}"

# Set BACKUP_DIR to the temporary directory
BACKUP_DIR="$temp_dir"

# Now proceed with the original restoration logic...

# List contents of backup directory for debugging
echo -e "${YELLOW}Contents of extracted backup directory:${NC}"
ls -la "$BACKUP_DIR"

# Check if containers are running
if ! docker ps --format 'table {{.Names}}' | grep -q "$IN_APP_CONTAINER"; then
    echo -e "${RED}App container '$IN_APP_CONTAINER' is not running${NC}"
    echo -e "${YELLOW}Running containers:${NC}"
    docker ps --format 'table {{.Names}}\t{{.Status}}'
    exit 1
fi
if ! docker ps --format 'table {{.Names}}' | grep -q "$IN_DB_CONTAINER"; then
    echo -e "${RED}Database container '$IN_DB_CONTAINER' is not running${NC}"
    echo -e "${YELLOW}Running containers:${NC}"
    docker ps --format 'table {{.Names}}\t{{.Status}}'
    exit 1
fi
echo -e "${GREEN}Containers found and running${NC}"

# Function to run commands in app container with proper user
run_in_app_container() {
    docker exec -i $IN_APP_CONTAINER "$@"
}

# Function to run commands in database container
run_in_db_container() {
    docker exec -i $IN_DB_CONTAINER "$@"
}

# Restore Public folder
echo -e "${YELLOW}⏳ Restoring 'public' folder...${NC}"
if [ -d "$BACKUP_DIR/public" ]; then
    echo -e "${YELLOW}Copying public folder to container...${NC}"
    docker cp "$BACKUP_DIR/public" "$IN_APP_CONTAINER":/var/www/html/
    run_in_app_container chown -R www-data:www-data /var/www/html/public
    run_in_app_container chmod -R 755 /var/www/html/public
    echo -e "${GREEN}✅ Public folder restored and permissions set${NC}"
else
    echo -e "${RED}❌ Public folder not found in backup directory${NC}"
    echo -e "${YELLOW}Looking for public folder in: $BACKUP_DIR${NC}"
    exit 1
fi

# Restore Storage folder
echo -e "${YELLOW}⏳ Restoring 'storage' folder...${NC}"
if [ -d "$BACKUP_DIR/storage" ]; then
    echo -e "${YELLOW}Copying storage folder to container...${NC}"
    docker cp "$BACKUP_DIR/storage" "$IN_APP_CONTAINER":/var/www/html/
    run_in_app_container chown -R www-data:www-data /var/www/html/storage
    run_in_app_container chmod -R 775 /var/www/html/storage
    # Ensure specific storage subdirectories have correct permissions
    run_in_app_container chmod -R 775 /var/www/html/storage/app
    run_in_app_container chmod -R 775 /var/www/html/storage/logs
    run_in_app_container chmod -R 775 /var/www/html/storage/framework
    echo -e "${GREEN}✅ Storage folder restored and permissions set${NC}"
else
    echo -e "${RED}❌ Storage folder not found in backup directory${NC}"
    echo -e "${YELLOW}Looking for storage folder in: $BACKUP_DIR${NC}"
    exit 1
fi

# Restore Database
echo -e "${YELLOW}⏳ Restoring database...${NC}"
DB_BACKUP_PATH="$BACKUP_DIR/$DB_BACKUP_FILE"
echo -e "${YELLOW}Looking for database file: $DB_BACKUP_PATH${NC}"
if [ -f "$DB_BACKUP_PATH" ]; then
    echo -e "${GREEN}✅ Database backup file found${NC}"
   
    # Extract database credentials from .env file in container
    echo -e "${YELLOW}Extracting database credentials...${NC}"
    DB_HOST=$(run_in_app_container grep DB_HOST /var/www/html/.env | cut -d '=' -f2)
    DB_DATABASE=$(run_in_app_container grep DB_DATABASE /var/www/html/.env | cut -d '=' -f2)
    DB_USERNAME=$(run_in_app_container grep DB_USERNAME /var/www/html/.env | cut -d '=' -f2)
    DB_PASSWORD=$(run_in_app_container grep DB_PASSWORD /var/www/html/.env | cut -d '=' -f2 | sed 's/^"\|"$//g')
   
    echo -e "${YELLOW}📦 Database detected: $DB_DATABASE on host: $DB_HOST${NC}"
   
    # Check what type of compression we have
    if [[ "$DB_BACKUP_FILE" == *".qz" ]]; then
        echo -e "${YELLOW}Detected .qz compression, using qpress...${NC}"
        # Check if qpress is available in the database container
        if docker exec $IN_DB_CONTAINER which qpress &> /dev/null; then
            echo -e "${YELLOW}Using qpress inside database container...${NC}"
            docker cp "$DB_BACKUP_PATH" "$IN_DB_CONTAINER":/tmp/db_backup.sql.qz
            docker exec $IN_DB_CONTAINER bash -c "qpress -d /tmp/db_backup.sql.qz /tmp/db_backup.sql"
            docker exec $IN_DB_CONTAINER mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" < /tmp/db_backup.sql
            docker exec $IN_DB_CONTAINER rm -f /tmp/db_backup.sql /tmp/db_backup.sql.qz
        else
            echo -e "${YELLOW}qpress not found in container, trying on host...${NC}"
            # Try to use host's qpress if available
            if command -v qpress &> /dev/null; then
                TEMP_SQL="/tmp/db_restore_$$.sql"
                qpress -d "$DB_BACKUP_PATH" "$TEMP_SQL"
                docker cp "$TEMP_SQL" "$IN_DB_CONTAINER":/tmp/db_backup.sql
                docker exec $IN_DB_CONTAINER mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" < /tmp/db_backup.sql
                docker exec $IN_DB_CONTAINER rm -f /tmp/db_backup.sql
                rm -f "$TEMP_SQL"
            else
                echo -e "${RED}qpress not found. Please install qpress or use gzip compression.${NC}"
                echo -e "${YELLOW}You can install qpress with: apt install qpress${NC}"
                exit 1
            fi
        fi
    else
        # Assume it's gzipped or plain SQL
        echo -e "${YELLOW}Assuming gzip compression or plain SQL...${NC}"
        docker cp "$DB_BACKUP_PATH" "$IN_DB_CONTAINER":/tmp/db_backup.sql.gz
        docker exec $IN_DB_CONTAINER bash -c "zcat /tmp/db_backup.sql.gz | mysql -h $DB_HOST -u $DB_USERNAME -p$DB_PASSWORD $DB_DATABASE"
        docker exec $IN_DB_CONTAINER rm -f /tmp/db_backup.sql.gz
    fi
   
    echo -e "${GREEN}✅ Database restored successfully${NC}"
else
    echo -e "${RED}❌ Database backup file not found: $DB_BACKUP_PATH${NC}"
    echo -e "${YELLOW}Available files in backup directory:${NC}"
    ls -la "$BACKUP_DIR"/
    echo -e "${YELLOW}Please check the filename and update DB_BACKUP_FILE variable if needed${NC}"
    exit 1
fi

# Run InvoiceNinja optimization commands
echo -e "${YELLOW}⏳ Running application optimization...${NC}"
run_in_app_container php /var/www/html/artisan cache:clear
run_in_app_container php /var/www/html/artisan config:clear
run_in_app_container php /var/www/html/artisan view:clear
run_in_app_container php /var/www/html/artisan route:clear
run_in_app_container php /var/www/html/artisan optimize

# Set final permissions
echo -e "${YELLOW}⏳ Setting final permissions...${NC}"
run_in_app_container chown -R www-data:www-data /var/www/html
run_in_app_container chmod -R 755 /var/www/html/public
run_in_app_container chmod -R 775 /var/www/html/storage
run_in_app_container find /var/www/html/storage -type f -exec chmod 664 {} \;

echo -e "${GREEN}🎉 InvoiceNinja restoration completed successfully!${NC}"
echo -e "${YELLOW}Please check your InvoiceNinja instance to verify everything is working.${NC}"
