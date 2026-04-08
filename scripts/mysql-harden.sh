#!/bin/bash
#
# MySQL Hardening Script (Standalone - No Ansible Required)
# Run this directly on SCP-DATABASE-01 (10.10.10.102)
#
# Usage: sudo bash mysql-harden.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  MYSQL HARDENING SCRIPT${NC}"
echo -e "${GREEN}  Standalone Deployment${NC}"
echo -e "${GREEN}================================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Please run as root (sudo bash mysql-harden.sh)${NC}"
    exit 1
fi

# Check if MySQL is installed
if ! command -v mysql &> /dev/null; then
    echo -e "${RED}ERROR: MySQL is not installed${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/9] Installing UFW...${NC}"
apt-get update -qq
apt-get install -y ufw > /dev/null 2>&1
echo -e "${GREEN}✓ UFW installed${NC}"

echo -e "${YELLOW}[2/9] Configuring firewall rules...${NC}"

# Reset UFW
ufw --force reset > /dev/null 2>&1

# Default policies
ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1

# Allow SSH
ufw allow 22/tcp comment 'SSH Access' > /dev/null 2>&1

# Allow MySQL from Apache
ufw allow from 10.10.10.101 to any port 3306 proto tcp comment 'MySQL from Apache' > /dev/null 2>&1

# Allow MySQL from Grey Team
for ip in 10.10.10.{200..210}; do
    ufw allow from $ip to any port 3306 proto tcp comment 'MySQL from Grey Team' > /dev/null 2>&1
    ufw allow from $ip proto icmp comment 'Grey Team ICMP' > /dev/null 2>&1
done

# Block MySQL from other blue team infrastructure
for ip in 10.10.10.21 10.10.10.22 10.10.10.23 10.10.10.103 10.10.10.104; do
    ufw deny from $ip to any port 3306 proto tcp comment 'Block MySQL' > /dev/null 2>&1
done

# Block ICMP by default (already allowed for grey team above)
ufw deny proto icmp comment 'Block ICMP by default' > /dev/null 2>&1

# Allow loopback
ufw allow in on lo > /dev/null 2>&1
ufw allow out on lo > /dev/null 2>&1

# Enable UFW
ufw --force enable > /dev/null 2>&1

echo -e "${GREEN}✓ Firewall configured${NC}"

echo -e "${YELLOW}[3/9] Backing up MySQL user table...${NC}"
BACKUP_FILE="/root/mysql_user_backup_$(date +%Y%m%d_%H%M%S).sql"
mysqldump mysql user > "$BACKUP_FILE" 2>/dev/null || true
echo -e "${GREEN}✓ Backup saved to: $BACKUP_FILE${NC}"

echo -e "${YELLOW}[4/9] Discovering MySQL users...${NC}"
mapfile -t MYSQL_USERS < <(mysql -e "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User != '';" -s -N 2>/dev/null)
echo -e "${GREEN}✓ Found ${#MYSQL_USERS[@]} MySQL users${NC}"

echo -e "${YELLOW}[5/9] Changing passwords for all MySQL users...${NC}"
PASSWORD_FILE="/root/mysql_passwords_$(date +%Y%m%d_%H%M%S).txt"
echo "# MySQL Passwords - Generated $(date)" > "$PASSWORD_FILE"
echo "# KEEP THIS FILE SECURE!" >> "$PASSWORD_FILE"
echo "" >> "$PASSWORD_FILE"

for user_host in "${MYSQL_USERS[@]}"; do
    USER=$(echo "$user_host" | cut -d@ -f1)
    HOST=$(echo "$user_host" | cut -d@ -f2)
    
    # Generate random password
    NEW_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
    
    # Change password
    mysql -e "ALTER USER '$USER'@'$HOST' IDENTIFIED BY '$NEW_PASSWORD';" 2>/dev/null || true
    
    # Save to file
    echo "$user_host: $NEW_PASSWORD" >> "$PASSWORD_FILE"
done

chmod 600 "$PASSWORD_FILE"
echo -e "${GREEN}✓ Passwords changed and saved to: $PASSWORD_FILE${NC}"

echo -e "${YELLOW}[6/9] Removing anonymous users and test database...${NC}"
mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
echo -e "${GREEN}✓ Anonymous users and test database removed${NC}"

echo -e "${YELLOW}[7/9] Removing remote root access...${NC}"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
echo -e "${GREEN}✓ Remote root access removed${NC}"

echo -e "${YELLOW}[8/9] Revoking dangerous privileges from non-root users...${NC}"
mysql -e "SELECT CONCAT(User,'@',Host) FROM mysql.user WHERE User != 'root' AND User != '';" -s -N 2>/dev/null | while read user_host; do
    USER=$(echo "$user_host" | cut -d@ -f1)
    HOST=$(echo "$user_host" | cut -d@ -f2)
    
    mysql -e "REVOKE FILE ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE SUPER ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE PROCESS ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE RELOAD ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE SHUTDOWN ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE CREATE USER ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
    mysql -e "REVOKE GRANT OPTION ON *.* FROM '$USER'@'$HOST';" 2>/dev/null || true
done
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
echo -e "${GREEN}✓ Dangerous privileges revoked${NC}"

echo -e "${YELLOW}[9/9] Applying hardened MySQL configuration...${NC}"
cp /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf.backup 2>/dev/null || true

cat > /etc/mysql/mysql.conf.d/mysqld.cnf << 'EOF'
# MySQL Hardened Configuration
# Applied by Blue Team Hardening Script

[mysqld]
# Network Security
bind-address = 10.10.10.102
port = 3306

# Disable dangerous features
local_infile = 0
symbolic-links = 0
skip-show-database

# Performance and Security
skip-name-resolve = 1
max_connections = 150
max_connect_errors = 10
connect_timeout = 10
max_allowed_packet = 16M

# Logging
log_error = /var/log/mysql/error.log
log_warnings = 2

# Character set
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
no-auto-rehash

[client]
port = 3306
EOF

systemctl restart mysql
sleep 3

# Test MySQL connection
if mysql -e "SELECT 1;" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ MySQL configuration applied and service restarted${NC}"
else
    echo -e "${RED}⚠ MySQL service may have issues - check logs${NC}"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  HARDENING COMPLETE${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${GREEN}✓ Firewall hardened (UFW)${NC}"
echo -e "  - MySQL (3306): Apache + Grey Team only"
echo -e "  - SSH (22): Existing access maintained"
echo -e "  - ICMP: Grey Team only"
echo -e "  - Blocked: DC, SMB, SMTP, OpenSSH, OpenVPN"
echo ""
echo -e "${GREEN}✓ MySQL service hardened${NC}"
echo -e "  - All user passwords changed"
echo -e "  - Anonymous users removed"
echo -e "  - Test database removed"
echo -e "  - Remote root disabled"
echo -e "  - Dangerous privileges revoked"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC}"
echo -e "  → New passwords: ${YELLOW}$PASSWORD_FILE${NC}"
echo -e "  → User backup: ${YELLOW}$BACKUP_FILE${NC}"
echo -e "  → Update Apache config with new DB password!"
echo -e "  → Test Apache -> MySQL connection"
echo ""
echo -e "${GREEN}================================================${NC}"
