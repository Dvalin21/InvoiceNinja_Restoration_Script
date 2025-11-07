# InvoiceNinja Restoration Script

This repository contains a Bash script designed to restore an InvoiceNinja instance from backups in a Docker-based setup. It handles restoration of key folders (public and storage) and the database, while ensuring proper permissions and application optimization.

- **Key Functionality**: Restores public/storage folders and database from gzip-compressed backups; sets permissions; clears caches.
- **Assumptions**: Assumes a standard Docker Compose setup with app and database containers; backups must be properly structured.
- **Potential Issues**: Compression formats like .qz require qpress installed; container names must match your setup to avoid errors.
- **Compatibility**: Works with self-hosted InvoiceNinja v5 in Docker, but test in a non-production environment first due to possible variations in setups.

## Requirements
- Docker and Docker Compose installed.
- Running InvoiceNinja containers (app and database).
- Backup directory with `public/`, `storage/`, and a `.sql.gz` file.
- Bash environment (Linux/Mac).

## Configuration
Edit the script's top section:
- `BACKUP_DIR`: Path to backups (e.g., `/home/invoiceninja/backups`).
- `IN_APP_CONTAINER`: App container name (e.g., `debian-app-1`).
- `IN_DB_CONTAINER`: Database container name (e.g., `debian-mysql-1`).
- `DB_BACKUP_FILE`: Database backup filename (e.g., `db_backup.sql.gz`).

## Usage
1. Make the script executable: `chmod +x restore.sh`.
2. Run it: `./restore.sh`.
3. Verify your InvoiceNinja instance post-restoration.

For official Docker setup details, see the InvoiceNinja Dockerfiles repository: https://github.com/invoiceninja/dockerfiles.

## Troubleshooting
- If containers aren't found, check names with `docker ps`.
- For .qz files, install qpress: `apt install qpress`.
- Database credentials are pulled from `.env` in the app container.

---

This comprehensive guide provides an in-depth look at the InvoiceNinja Restoration Script, expanding on its mechanics, best practices, and integration with broader InvoiceNinja ecosystem knowledge. Built on insights from community forums and official documentation, it aims to equip users with a thorough understanding for effective deployment and maintenance.

### Script Overview and Purpose
The script is a robust tool for restoring self-hosted InvoiceNinja instances running in Docker containers. InvoiceNinja, an open-source invoicing platform, often requires manual backup and restore processes in containerized environments, as in-app backups may not fully cover Docker-specific needs. This script automates the restoration of critical components: the `public` and `storage` folders, along with the MySQL/MariaDB database dump. It includes error handling, colored output for readability, and post-restore optimizations like cache clearing.

Key steps in the script include:
- Validating the backup directory and container status.
- Copying folders via `docker cp` and setting ownership/permissions with `chown` and `chmod`.
- Extracting database credentials from the app container's `.env` file.
- Handling database restoration with support for gzip (via `zcat`) and optional qpress for .qz files.
- Running Artisan commands for optimization (e.g., `php artisan cache:clear`).

This approach aligns with community-recommended practices for full backups, which typically involve dumping the database and copying key directories.

### Detailed Requirements and Prerequisites
To run this script effectively:
- **Operating System**: Linux-based host (e.g., Ubuntu/Debian), as it uses Bash and Docker commands. Mac users may need adjustments for path handling.
- **Docker Setup**: Must have a running InvoiceNinja Docker Compose environment. Official setups use services like `app` (PHP/Laravel), `db` (MySQL/MariaDB), and `cron`. Container names in the script (e.g., `debian-app-1`) suggest a customized compose file; default names might be `invoiceninja-app-1` or similar.
- **Backup Structure**: The backup directory should contain:
  - `public/` folder (for uploaded files and assets).
  - `storage/` folder (for logs, cache, and app data).
  - A compressed database dump (e.g., `db_backup.sql.gz`).
- **Tools**: `docker`, `docker compose`, and optionally `qpress` for .qz decompression. Install qpress with `apt install qpress` on Debian-based systems.
- **Permissions**: Run the script as a user with Docker access (e.g., via sudo or Docker group membership).

If your setup differs, such as using a different database (though MySQL is standard), modifications may be needed.

### Configuration Variables Explained
The script's configuration is centralized at the top for easy editing. Here's a breakdown:

| Variable            | Description                                                                 | Default Value                  | Notes |
|---------------------|-----------------------------------------------------------------------------|--------------------------------|-------|
| `BACKUP_DIR`       | Path to the backup directory (no trailing slash).                           | `/home/invoiceninja/backups`  | Ensure it exists; script cleans double slashes. |
| `IN_APP_CONTAINER` | Name of the InvoiceNinja application container.                             | `debian-app-1`                | Match your `docker ps` output; e.g., change to `invoiceninja-app-1`. |
| `IN_DB_CONTAINER`  | Name of the database container.                                             | `debian-mysql-1`              | Typically MySQL or MariaDB; ensure it's running. |
| `DB_BACKUP_FILE`   | Filename of the database backup (gzip compressed SQL dump).                 | `db_backup.sql.gz`            | Supports .gz by default; .qz requires qpress. |

These variables pull from common Docker setups, but for advanced configurations like environment-specific .env files, refer to official Dockerfiles.

### Step-by-Step Usage Guide
1. **Clone the Repository**: `git clone <repo-url> && cd <repo-dir>`.
2. **Customize Configuration**: Open `restore.sh` in a text editor and update variables as needed.
3. **Make Executable**: `chmod +x restore.sh`.
4. **Execute the Script**: `./restore.sh`. It will output progress with colors (yellow for actions, green for success, red for errors).
5. **Post-Restoration Checks**:
   - Access your InvoiceNinja web interface to verify data integrity.
   - Check logs in `storage/logs/` for any issues.
   - Run manual Artisan commands if needed: `docker exec -i <app-container> php artisan migrate`.

For backups before restoration, consider complementary scripts from the community that automate tarball creation and uploads.

### Permissions and Optimization Details
The script meticulously handles permissions, crucial for Laravel-based apps like InvoiceNinja:
- `public/` set to 755 (readable/executable).
- `storage/` and subdirs (app, logs, framework) set to 775 (writable by group).
- Files in storage set to 664.
- Ownership: `www-data:www-data` (standard web user).

Post-restore, it clears caches and optimizes via Artisan commands, preventing common issues like stale configurations.

### Handling Compression and Database Restoration
- **Gzip (.gz)**: Uses `zcat` to pipe into `mysql` command inside the DB container.
- **Qpress (.qz)**: Attempts decompression in the container or host; falls back with installation instructions if missing.
- Credentials are dynamically extracted from `/var/www/html/.env` in the app container, ensuring no hardcoding.

If the backup file is missing, the script lists directory contents for debugging.

### Troubleshooting Common Issues
- **Container Not Running**: Script checks with `docker ps` and lists running containers.
- **Directory Not Found**: Verifies backup path and lists `/home/invoiceninja/` contents.
- **Permission Errors**: Ensure Docker user has access; run script with sudo if needed.
- **Database Import Fails**: Verify .env credentials; test manually with `docker exec`.
- **Custom Setups**: For non-Debian bases or different web servers (e.g., NGINX configs), adapt accordingly.
- Community forums suggest testing migrations for version compatibility.

### Integration with InvoiceNinja Ecosystem
This script complements official features like in-app full backups (emailed for safekeeping). For automated backups, pair with cron jobs or tools like the MGM CLI script for updates and backups. In Docker, always back up volumes for persistence.

For Synology or other NAS setups, additional volume mappings may be required.

### Best Practices and Security Considerations
- **Test Restores**: Always test in a staging environment to avoid data loss.
- **Secure Backups**: Store backups off-site; use encryption for sensitive invoicing data.
- **Version Control**: Ensure backup and restore versions match to prevent schema mismatches.
- **Updates**: Before restoring, consider updating images with `docker compose pull` and backing up first.
- **Environment Variables**: After initial setup, remove sensitive vars like `IN_PASSWORD` from .env.

### Comparison of Backup Methods

| Method                  | Pros                                      | Cons                                      | Use Case |
|-------------------------|-------------------------------------------|-------------------------------------------|----------|
| In-App Backup           | Easy, emailed full system dump            | May not cover Docker volumes fully        | Quick daily backups |
| Manual Script (This)    | Automated Docker-specific restore         | Requires configuration; compression handling | Full restores in containerized setups |
| MGM CLI Script          | Automates backup/update                   | More for maintenance than pure restore    | Ongoing management |
| Database Dump + rsync   | Simple, no extra tools                    | Manual permissions setup                  | Basic setups without Docker |

This table highlights how this script fits into broader strategies.

### Contributing and License
Feel free to fork and contribute improvements, such as adding support for more compression types or automated backups. This script is provided under the MIT License (or specify as needed).

For more on InvoiceNinja, visit the official documentation: https://invoiceninja.github.io.
