#!/usr/local/bin/bash

# Script to perform MySQL database backups, compress them, and upload to AWS S3.
# Purpose: Automated backup management for MySQL databases.

# Enable debug mode for troubleshooting (commented by default)
#set -xv

# Cleanup on exit (remove temporary files)
trap "rm -f /tmp/*.$$ > /dev/null" 0 1 2 15

# Configuration Variables
BACKUP_NUM=7  # Number of backup rotations to keep
BACKUP_DIR="YOUR/LOCAL/DIR"  # Local directory to store backups
S3_BUCKET="YOUR_S3_BUCKET"  # S3 bucket for uploads
S3_DIR="BUCKET/DIR"  # S3 path inside the bucket

# Timestamps for file naming and logging
TIMESTAMP=$(date +'%Y-%m-%d_%Hh%Mm%Ss')
DATA=$(date +'%Y-%m-%d')
ANO=$(echo $DATA | cut -f1 -d-)
MES=$(echo $DATA | cut -f2 -d-)
DIA=$(echo $DATA | cut -f3 -d-)

# Paths to required binaries
TAR="/usr/bin/tar"
XZ="/usr/bin/xz"  # Compression tool
AWS="/usr/local/bin/aws"  # AWS CLI
MYSQL="/usr/bin/mysql"
MYSQL_DUMP="/usr/bin/mysqldump"

# MySQL connection parameters (use environment variables or encrypted storage in production)
MYSQL_CONN="-u root -YOUR_PASSWORD"
MYSQL_PARAMS="--triggers --routines --events --opt --lock-all-tables \
               --flush-logs --flush-privileges --allow-keywords \
               --hex-blob --set-gtid-purged=OFF --no-autocommit"

# List of databases to back up (replace with dynamic command if needed)
DBLIST="database1 database2"

# Main backup loop
for DBNAME in $DBLIST ; do

    # Create backup directory if it doesn't exist
    if [ ! -d $BACKUP_DIR/$DBNAME ]; then
        echo -n "Creating backup directory $BACKUP_DIR/$DBNAME ..."
        mkdir -p $BACKUP_DIR/$DBNAME || continue
        echo "done."
    fi

    # Backup file paths
    ARQ="$BACKUP_DIR/$DBNAME/$DBNAME.dump"
    ARQXZ="$ARQ.xz"
    ARQ_TIME="$BACKUP_DIR/$DBNAME/$DBNAME.dump.$DATA.log"

    # Remove the oldest backup if it exists
    if [ -f $ARQ.$BACKUP_NUM ]; then
        rm -f $ARQ.$BACKUP_NUM
    fi

    # Rotate previous backups
    n=$(( $BACKUP_NUM - 1 ))
    while [ $n -gt 0 ]; do
        if [ -f $ARQXZ.$n ]; then
            mv $ARQXZ.$n $ARQXZ.$(( $n + 1 ))
        fi
        n=$(( $n - 1 ))
    done

    # Rename the latest backup
    if [ -f $ARQXZ ]; then
        mv $ARQXZ $ARQXZ.1
    fi

    # Perform MySQL dump
    echo -n "Dumping MySQL database: $DBNAME ...   "
    START_BACKUP_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    $MYSQL_DUMP $MYSQL_CONN $MYSQL_PARAMS $DBNAME > $ARQ
    END_BACKUP_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    echo "done."

    # Compress the dump file
    echo -n "Compressing dump of: $DBNAME ...   "
    START_COMPRESS_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    $XZ $ARQ
    END_COMPRESS_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    echo "done."

    # Upload the compressed dump to AWS S3
    echo "Uploading dump of $DBNAME to AWS..."
    START_AWS_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    $AWS s3 cp $ARQXZ s3://$S3_BUCKET/$S3_DIR/$ANO-$MES/$DBNAME/"$TIMESTAMP"_"$DBNAME".dump.xz
    END_AWS_TIME=$(date +'%Y-%m-%d %H:%M:%S')
    echo "done."

    # Log the times for auditing and debugging
    echo -e "Start Backup: $START_BACKUP_TIME\n\
    End Backup: $END_BACKUP_TIME\n\
    Start Compression: $START_COMPRESS_TIME\n\
    End Compression: $END_COMPRESS_TIME\n\
    Start AWS Upload: $START_AWS_TIME\n\
    End AWS Upload: $END_AWS_TIME" > $ARQ_TIME

    # Optional: Notify BetterStack heartbeat for uptime monitoring
    curl -s https://uptime.betterstack.com/api/v1/heartbeat/YOUR_KEY

done

# Disable debug mode
set +xv
exit 0

# Notes:
# 1. Avoid storing plaintext passwords in scripts; consider using AWS Secrets Manager or .my.cnf files.
# 2. Check the permissions for the AWS CLI to ensure upload permissions.
# 3. Make sure the required tools (xz, aws CLI) are installed and accessible.
