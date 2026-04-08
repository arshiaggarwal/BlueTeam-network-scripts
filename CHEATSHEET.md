# MySQL Hardening Quick Reference

## 🚀 Deployment

```bash
# Ansible (recommended)
ansible-playbook deploy-scripts.yml

# Standalone script
scp scripts/mysql-harden.sh root@10.10.10.102:/root/
ssh root@10.10.10.102 "sudo bash /root/mysql-harden.sh"
```

## 📋 Post-Deployment Checklist

- [ ] Check password file: `cat mysql_passwords_SCP-DATABASE-01.txt`
- [ ] Update Apache DB config with new password
- [ ] Restart Apache: `ssh root@10.10.10.101 "systemctl restart apache2"`
- [ ] Test web app: `curl http://10.10.10.101`
- [ ] Monitor grey team scoring

## 🔍 Verification Commands

```bash
# Check firewall rules
ssh root@10.10.10.102 "ufw status numbered"

# Check MySQL is running
ssh root@10.10.10.102 "systemctl status mysql"

# Test MySQL connection from Apache
ssh root@10.10.10.101 "mysql -h 10.10.10.102 -u <user> -p"

# Check MySQL users
ssh root@10.10.10.102 "mysql -e 'SELECT User, Host FROM mysql.user;'"

# View MySQL config
ssh root@10.10.10.102 "cat /etc/mysql/mysql.conf.d/mysqld.cnf"
```

## 🛡️ What's Protected

### Firewall (UFW)
✅ MySQL (3306): Apache + Grey Team ONLY  
✅ SSH (22): Maintained  
✅ ICMP: Grey Team ONLY  
❌ Blocked: DC, SMB, SMTP, OpenSSH, OpenVPN

### MySQL Service
✅ All passwords changed  
✅ Anonymous users removed  
✅ Test database removed  
✅ Remote root disabled  
✅ Dangerous privileges revoked  
✅ Config hardened (bind-address, local_infile=0)

## 🔄 Rollback

```bash
# Quick rollback
ansible-playbook reverse.yml

# Manual rollback
ssh root@10.10.10.102
ufw disable
cp /etc/mysql/mysql.conf.d/mysqld.cnf.backup /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql
```

## 🐛 Common Issues

### Apache Can't Connect
1. Find new password: `cat mysql_passwords_SCP-DATABASE-01.txt`
2. Update Apache config: `/var/www/html/config.php` (or similar)
3. Restart Apache: `systemctl restart apache2`

### Scoring Fails
```bash
# Re-validate grey team access
ansible-playbook playbooks/greyteam-validate.yml
```

### MySQL Won't Start
```bash
# Check logs
tail -f /var/log/mysql/error.log

# Restore config
cp /etc/mysql/mysql.conf.d/mysqld.cnf.backup /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql
```

## 📊 Files Created

On Database Server:
- `/root/mysql_passwords_YYYYMMDD_HHMMSS.txt` - New passwords
- `/root/mysql_user_backup_YYYYMMDD_HHMMSS.sql` - User backup
- `/etc/mysql/mysql.conf.d/mysqld.cnf.backup` - Config backup

On Local Machine:
- `./mysql_passwords_SCP-DATABASE-01.txt` - Password file copy

## 🎯 Allowed Connections

**MySQL Port 3306:**
- ✅ 10.10.10.101 (Apache)
- ✅ 10.10.10.200 - 10.10.10.210 (Grey Team)
- ❌ Everything else BLOCKED

**SSH Port 22:**
- ✅ Existing access maintained

## ⚙️ Configuration Files

**Update IPs**: `group_vars/all.yml`  
**Update Credentials**: `inventory.ini`  
**MySQL Config**: `templates/mysqld_hardened.cnf`

## 💡 Pro Tips

- Always test Apache connection after deployment
- Keep password file secure and backed up
- Monitor grey team scoring immediately after deployment
- Have rollback command ready before deploying
- Test in non-production first if possible

## 🆘 Emergency Commands

```bash
# Disable firewall immediately
ssh root@10.10.10.102 "ufw disable"

# Stop MySQL
ssh root@10.10.10.102 "systemctl stop mysql"

# Full rollback
ansible-playbook reverse.yml

# Check if scoring engine can reach MySQL
ssh root@10.10.10.200 "nc -zv 10.10.10.102 3306"
```
