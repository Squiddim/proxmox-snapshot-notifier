# proxmox-snapshot-notifier

Script that periodically checks for old Snapshots and send a report to Mattermost via Webhook

```bash
# Clone/update repository
git pull

# Install dependencies
sudo apt install curl jq
sudo dnf install curl jq

# Create directories
sudo mkdir -p /opt/snapshot-notifier /etc/snapshot-notifier

# Copy files
sudo cp snapshot-notifier.sh /opt/snapshot-notifier/
sudo cp snapshot-notifier.conf.example /etc/snapshot-notifier/snapshot-notifier.conf
sudo cp snapshot-notifier.service /etc/systemd/system/
sudo cp snapshot-notifier.timer /etc/systemd/system/

# Set permissions
sudo chmod 755 /opt/snapshot-notifier/snapshot-notifier.sh
sudo chmod 600 /etc/snapshot-notifier/snapshot-notifier.conf
sudo chown root:root /etc/snapshot-notifier/snapshot-notifier.conf

# Configure credentials
sudo vim /etc/snapshot-notifier/snapshot-notifier.conf

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable --now snapshot-notifier.timer
```
