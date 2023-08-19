#!/bin/bash
# vim: tabstop=2 shiftwidth=2 expandtab

#set -x

# Allow start with custom commands
if [ "$#" -ne 0 ] && command -v "$@" > /dev/null 2>&1; then
  "$@"
  exit 0
fi

function local_backup(){
  BACKUP_CMD="/sbin/su-exec ${UID}:${GID} /app/backup.sh"
  echo "Running $(basename "$0") as $(id)"

  # Preparation
  BACKUP_DIR=$(dirname "$BACKUP_FILE")
  if [ ! -d "$BACKUP_DIR" ]
  then
    echo "$BACKUP_DIR not exists. Creating it with owner $UID:$GID and permissions $BACKUP_FILE_PERMISSIONS."
    install -o "$UID" -g "$GID" -m "$BACKUP_FILE_PERMISSIONS" -d "$BACKUP_DIR"
  fi

  ATTACHMENT_BACKUP_DIR=$(dirname "$ATTACHMENT_BACKUP_FILE")
  if [ ! -d "$ATTACHMENT_BACKUP_DIR" ]
  then
    echo "$ATTACHMENT_BACKUP_DIR not exists. Creating it with owner $UID:$GID and permissions $BACKUP_FILE_PERMISSIONS."
    install -o "$UID" -g "$GID" -m "$BACKUP_FILE_PERMISSIONS" -d "$ATTACHMENT_BACKUP_DIR"
  fi

  # For compatibility reasons
  if [ "$1" = "/backup.sh" ]; then
    >&2 echo "Using /backup.sh is deprecated and will be removed in future versions! Please use \`manual\` as argument instead"
    $BACKUP_CMD
  fi

  # Just run the backup script
  if [ "$1" = "manual" ]; then
    $BACKUP_CMD
    exit 0
  fi

  # Initialize cron
  if [ "$(id -u)" -eq 0 ] && [ "$(grep -c "$BACKUP_CMD" "$CRONFILE")" -eq 0 ]; then
    echo "Initalizing..."
    echo "Writing backup command \"$BACKUP_CMD\" to cron."
    echo "$CRON_TIME $BACKUP_CMD >> $LOGFILE 2>&1" | crontab -

  fi

  # Start crond if it's not running
  if ! pgrep crond > /dev/null 2>&1; then
    /usr/sbin/crond -L /app/log/cron.log
  fi

  # Restart script as user "app:app"
  if [ "$(id -u)" -eq 0 ]; then
    echo "Restarting $(basename "$0") as app:app"
    exec su-exec app:app "$0" "$@"
  fi

  echo "$(date "+%F %T") - Container started" > "$LOGFILE"
  tail -F "$LOGFILE" /app/log/cron.log
}

function remote_backup(){

  if [[ "$REMOTE_METHOD" == "sftp" ]]; then
    if [ -z "$SFTP_HOST" ] || [ -z "$SFTP_USER" ] || [[ -z "$SFTP_PASSWORD" || -z "$SFTP_KEY_FILE" ]]; then
      echo "Missing some parameters, please check your config and try again"
      exit 1
    fi

    echo "Configuring rclone sftp for remote backup support"

    # Run password through rclone obscure
    PASSWORD=$(echo "$SFTP_PASSWORD" | rclone obscure -)

    # Create rclone config dir if it doesn't exist
    if [ -d ~/.config/rclone ]; then
      mkdir -p ~/.config/rclone
    fi

    # Create rclone config file
    {
      echo '[vaultwarden_sftp]'
      echo 'type = sftp'
      echo "host = $SFTP_HOST"
      echo "user = $SFTP_USER"
      echo "pass = $PASSWORD"
      echo "port = $PORT"
      echo "key_file = $KEY_FILE"
    } > ~/.config/rclone/rclone.conf

    # Run local backup since we use that to create backup db
    local_backup
  fi  
}

echo "Backup method is $BACKUP_METHOD"
if [[ ${BACKUP_METHOD} == "local" ]]; then
  local_backup "$@"
fi

if [[ ${BACKUP_METHOD} == "remote" ]]; then
  remote_backup
fi
