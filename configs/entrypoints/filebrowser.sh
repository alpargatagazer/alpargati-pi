#!/bin/sh
set -eu

# ============================================================================
# FileBrowser entrypoint - initializes database and admin user from secret
# ============================================================================

DB_PATH="/database/filebrowser.db"
CONFIG_FILE="/database/.filebrowser.json"

read_secret() {
  file="/run/secrets/$1"
  if [ -f "$file" ]; then
    cat "$file" | tr -d '\n'
  fi
}

# Initialize config if not exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating FileBrowser config..."
  cat > "$CONFIG_FILE" <<EOF
{
  "port": 8080,
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "stdout",
  "database": "/database/filebrowser.db",
  "root": "/srv"
}
EOF
fi

# Initialize database if not exists
if [ ! -f "$DB_PATH" ]; then
  echo "Initializing FileBrowser database..."
  /filebrowser config init --database "$DB_PATH"
  
  # Set up admin user from environment/secret
  ADMIN_USER="${FILEBROWSER_ADMIN_USER:-admin}"
  ADMIN_PASS="$(read_secret filebrowser_admin_password)"
  
  if [ -n "$ADMIN_PASS" ]; then
    echo "Creating admin user: $ADMIN_USER"
    /filebrowser users add "$ADMIN_USER" "$ADMIN_PASS" --perm.admin --database "$DB_PATH"
  else
    echo "Warning: No admin password set, using default credentials"
    /filebrowser users add admin admin --perm.admin --database "$DB_PATH"
  fi
fi

# Execute FileBrowser
exec /filebrowser --config "$CONFIG_FILE" "$@"
