#!/bin/bash

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file location
LOG_FILE="$HOME/automation_audit_$(date +%Y%m%d_%H%M%S).log"
LOCAL_WHOIS_FILE="$HOME/whois_result_$(date +%Y%m%d_%H%M%S).txt"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    case $1 in
        "success") echo -e "${GREEN}[✓] $2${NC}" ;;
        "error") echo -e "${RED}[✗] $2${NC}" ;;
        "warning") echo -e "${YELLOW}[!] $2${NC}" ;;
        "info") echo -e "${BLUE}[i] $2${NC}" ;;
    esac
}

################################################
# SECTION 1: Installations and Anonymity Check #
################################################

print_status "info" "### SECTION 1: Installation and Anonymity Check ###"
log_message "Script execution started"
echo
echo "Starting SUDO APT UPDATE..."
sudo apt update

# Required packages
REQUIRED_PACKAGES=("nipe" "whois" "sshpass" "ftp" "tcpdump" "geoip-bin")

# Check and install packages
print_status "info" "Checking required packages..."

for package in "${REQUIRED_PACKAGES[@]}"; do
    if [ "$package" == "nipe" ]; then
        # Special handling for Nipe (Tor anonymizer)
        if [ ! -d "$HOME/nipe" ]; then
            print_status "warning" "Nipe not found. Installing..."
            log_message "Installing Nipe"
            cd "$HOME" || exit 1
            git clone https://github.com/htrgouvea/nipe.git && cd nipe
            cpanm --installdeps .
            sudo cpan install Switch JSON LWP::UserAgent Config::Simple
            sudo perl nipe.pl install
            print_status "success" "Nipe installed"
        else
            print_status "success" "Nipe already installed"
        fi
    elif [ "$package" == "geoip-bin" ]; then
        # Special handling for geoip-bin (provides geoiplookup command)
        if ! command -v geoiplookup &>/dev/null; then
            print_status "warning" "geoiplookup not found. Installing geoip-bin..."
            log_message "Installing geoip-bin"
            sudo apt-get update &>/dev/null
            sudo apt-get install -y geoip-bin geoip-database &>/dev/null
            if [ $? -eq 0 ]; then
                print_status "success" "geoip-bin installed successfully"
                log_message "geoip-bin installed successfully"
            else
                print_status "error" "Failed to install geoip-bin"
                log_message "ERROR: Failed to install geoip-bin"
            fi
        else
            print_status "success" "geoiplookup already installed"
            log_message "geoiplookup is already installed"
        fi
    else
        # Standard package check using dpkg
        if dpkg -l | grep -q "^ii  $package "; then
            print_status "success" "$package is already installed"
            log_message "$package is already installed"
        else
            print_status "warning" "$package not found. Installing..."
            log_message "Installing $package"
            sudo apt-get update &>/dev/null
            sudo apt-get install -y "$package" &>/dev/null
            if [ $? -eq 0 ]; then
                print_status "success" "$package installed successfully"
                log_message "$package installed successfully"
            else
                print_status "error" "Failed to install $package"
                log_message "ERROR: Failed to install $package"
            fi
        fi
    fi
done

# Check anonymity using Nipe
print_status "info" "Checking network anonymity..."
log_message "Checking network anonymity"

# Start Nipe if not running
if [ -d "$HOME/nipe" ]; then
    cd "$HOME/nipe" || exit 1
    
    MAX_ATTEMPTS=500
    ATTEMPT=1
    ANONYMOUS=false
    
    # Start Nipe
	print_status "info" "Starting Nipe..."
	log_message "Starting Nipe (attempt $ATTEMPT)"
	sudo perl nipe.pl start &>/dev/null
    
    # Wait for Nipe to establish connection
    print_status "info" "Waiting for Tor connection to establish (30 seconds)..."
    sleep 30
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$ANONYMOUS" = false ]; do
        print_status "info" "Anonymity check attempt $ATTEMPT of $MAX_ATTEMPTS..."
        log_message "Anonymity check attempt $ATTEMPT"
        
        NIPE_STATUS=$(sudo perl nipe.pl status | grep "Status" | awk '{print $3}')
        
        if [ "$NIPE_STATUS" != "true" ]; then
            print_status "warning" "Network connection is NOT anonymous (Attempt $ATTEMPT)"
            log_message "Network is not anonymous on attempt $ATTEMPT"
            
            # Restart Nipe 
            print_status "info" "Restarting Nipe (3 seconds)..."
            log_message "Restarting Nipe (attempt $ATTEMPT)"
            sudo perl nipe.pl restart &>/dev/null
            sleep 3
                                                       
            ATTEMPT=$((ATTEMPT + 1))
        else
            ANONYMOUS=true
            print_status "success" "Network connection is anonymous!"
            log_message "Network is anonymous"
            
            # Get spoofed country using geoiplookup
            CURRENT_IP=$(curl -s ifconfig.io)
            SPOOFED_COUNTRY=$(geoiplookup "$CURRENT_IP" | awk -F': ' '{print $2}')
            print_status "success" "Spoofed Country: $SPOOFED_COUNTRY"
            print_status "success" "Spoofed IP: $CURRENT_IP"
            log_message "Spoofed country: $SPOOFED_COUNTRY"
            log_message "Spoofed IP: $CURRENT_IP"
        fi
    done
    
    # If still not anonymous after all attempts, exit
    if [ "$ANONYMOUS" = false ]; then
        print_status "error" "Failed to establish anonymous connection after $MAX_ATTEMPTS attempts"
        log_message "ERROR: Failed to establish anonymous connection after $MAX_ATTEMPTS attempts. Exiting."
        exit 1
    fi
else
    print_status "error" "Nipe directory not found at $HOME/nipe"
    log_message "ERROR: Nipe not installed"
    exit 1
fi

# Get SSH credentials first
echo ""
print_status "info" "Enter remote server credentials:"
read -p "Remote server IP: " REMOTE_IP
read -p "Remote server username: " REMOTE_USER
read -sp "Remote server password: " REMOTE_PASS
echo ""
log_message "Remote server: $REMOTE_USER@$REMOTE_IP"

###################################################
# SECTION 2: Remote Server Scanning and Execution #
###################################################
echo
echo
print_status "info" "### SECTION 2: Remote Server Operations ###"
echo
# Test SSH connection
print_status "info" "Testing SSH connection to remote server..."
log_message "Testing SSH connection to $REMOTE_IP"

sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "echo 'Connection successful'" &>/dev/null

if [ $? -ne 0 ]; then
    print_status "error" "Failed to connect to remote server via SSH"
    log_message "ERROR: SSH connection failed"
    exit 1
fi

print_status "success" "SSH connection successful"
log_message "SSH connection established"

# Start tcpdump immediately after SSH connection to capture all traffic
print_status "info" "Starting packet capture on remote server..."
PCAP_FILE="capture_$(date +%Y%m%d_%H%M%S).pcap"

# Check if tcpdump is installed on remote server, install if needed
print_status "info" "Checking for tcpdump on remote server..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "which tcpdump &>/dev/null || (echo 'Installing tcpdump...' && sudo apt-get update &>/dev/null && sudo apt-get install -y tcpdump &>/dev/null)"

# Check if whois is installed on remote server, install if needed
print_status "info" "Checking for whois on remote server..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "which whois &>/dev/null || (echo 'Installing whois...' && sudo apt-get install -y whois &>/dev/null)"

# Start tcpdump in background with proper sudo password handling
print_status "info" "Starting tcpdump capture..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << EOF
echo "$REMOTE_PASS" | sudo -S nohup tcpdump -i any -w /tmp/$PCAP_FILE port 21 or port 20 > /tmp/tcpdump.log 2>&1 &
echo \$! > /tmp/tcpdump.pid
sleep 2
if ps -p \$(cat /tmp/tcpdump.pid) > /dev/null 2>&1; then
    echo "tcpdump_started"
else
    echo "tcpdump_failed"
fi
EOF

TCPDUMP_STATUS=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "tail -n 1 /tmp/tcpdump.log 2>/dev/null || echo 'no_log'")

if [[ "$TCPDUMP_STATUS" == *"tcpdump_started"* ]] || [[ "$TCPDUMP_STATUS" == *"listening"* ]]; then
    print_status "success" "tcpdump started successfully on remote server"
    log_message "Started tcpdump on remote server (PID stored)"
else
    print_status "warning" "tcpdump may have issues starting: $TCPDUMP_STATUS"
    log_message "WARNING: tcpdump status unclear: $TCPDUMP_STATUS"
fi

# Get remote server details
print_status "info" "Gathering remote server information..."

REMOTE_UPTIME=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "uptime -p")
REMOTE_PUBLIC_IP=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "curl -s ifconfig.io")
REMOTE_COUNTRY=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "geoiplookup $REMOTE_PUBLIC_IP 2>/dev/null | awk -F': ' '{print \$2}' || echo 'Country lookup unavailable'")

echo ""
print_status "success" "Remote Server Details:"
echo "  IP Address: $REMOTE_PUBLIC_IP"
echo "  Country: $REMOTE_COUNTRY"
echo "  Uptime: $REMOTE_UPTIME"
echo ""

log_message "Remote server IP: $REMOTE_PUBLIC_IP"
log_message "Remote server country: $REMOTE_COUNTRY"
log_message "Remote server uptime: $REMOTE_UPTIME"

# Now ask for target address/URL for whois lookup
echo ""
read -p "Enter the IP address or domain for WHOIS lookup: " TARGET_ADDRESS
log_message "Target address: $TARGET_ADDRESS"

print_status "info" "Note: tcpdump is now capturing all network traffic on remote server"

print_status "info" "Note: tcpdump is now capturing all network traffic on remote server"

# Start tcpdump on remote server
print_status "info" "Starting packet capture on remote server..."
PCAP_FILE="capture_$(date +%Y%m%d_%H%M%S).pcap"

# Check if tcpdump is installed on remote server, install if needed
print_status "info" "Checking for tcpdump on remote server..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "which tcpdump &>/dev/null || (echo 'Installing tcpdump...' && sudo apt-get update &>/dev/null && sudo apt-get install -y tcpdump &>/dev/null)"

# Check if whois is installed on remote server, install if needed
print_status "info" "Checking for whois on remote server..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "which whois &>/dev/null || (echo 'Installing whois...' && sudo apt-get install -y whois &>/dev/null)"

# Start tcpdump in background with proper sudo password handling
print_status "info" "Starting tcpdump capture..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << EOF
echo "$REMOTE_PASS" | sudo -S nohup tcpdump -i any -w /tmp/$PCAP_FILE port 21 or port 20 > /tmp/tcpdump.log 2>&1 &
echo \$! > /tmp/tcpdump.pid
sleep 2
if ps -p \$(cat /tmp/tcpdump.pid) > /dev/null 2>&1; then
    echo "tcpdump_started"
else
    echo "tcpdump_failed"
fi
EOF

TCPDUMP_STATUS=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "tail -n 1 /tmp/tcpdump.log 2>/dev/null || echo 'no_log'")

if [[ "$TCPDUMP_STATUS" == *"tcpdump_started"* ]] || [[ "$TCPDUMP_STATUS" == *"listening"* ]]; then
    print_status "success" "tcpdump started successfully on remote server"
    log_message "Started tcpdump on remote server (PID stored)"
else
    print_status "warning" "tcpdump may have issues starting: $TCPDUMP_STATUS"
    log_message "WARNING: tcpdump status unclear: $TCPDUMP_STATUS"
fi

sleep 2

# Execute WHOIS lookup on remote server
print_status "info" "Executing WHOIS lookup on remote server for: $TARGET_ADDRESS"
log_message "Executing WHOIS lookup for $TARGET_ADDRESS on remote server"

REMOTE_WHOIS_FILE="/tmp/whois_$(date +%Y%m%d_%H%M%S).txt"

sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "whois $TARGET_ADDRESS > $REMOTE_WHOIS_FILE"

if [ $? -eq 0 ]; then
    print_status "success" "WHOIS lookup completed on remote server"
    log_message "WHOIS lookup completed successfully"
else
    print_status "error" "WHOIS lookup failed"
    log_message "ERROR: WHOIS lookup failed"
fi

#################################
# SECTION 3: Results Collection #
#################################
echo
echo
print_status "info" "### SECTION 3: Results Collection ###"
echo
# Setup FTP server on remote machine for file transfer
print_status "info" "Setting up FTP server on remote machine..."
log_message "Setting up FTP for file transfer"

# Install vsftpd if not present
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << 'FTPSETUP'
# Check if vsftpd is installed
if ! which vsftpd &>/dev/null; then
    echo "Installing vsftpd..."
    sudo apt-get update &>/dev/null
    sudo apt-get install -y vsftpd &>/dev/null
fi

# Configure vsftpd for anonymous access (for this session only)
sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.backup 2>/dev/null

# Create temporary FTP configuration
sudo tee /etc/vsftpd.conf > /dev/null << 'EOF'
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

# Restart FTP service
sudo systemctl restart vsftpd 2>/dev/null || sudo service vsftpd restart 2>/dev/null
echo "FTP_READY"
FTPSETUP

FTP_STATUS=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "systemctl is-active vsftpd 2>/dev/null")

# Check if FTP_STATUS contains "active" (could be "active" with newlines or extra output)
if echo "$FTP_STATUS" | grep -q "active"; then
    print_status "success" "FTP server is running on remote machine"
    log_message "FTP server started successfully"
else
    print_status "warning" "FTP server status unclear: $FTP_STATUS, will attempt FTP transfer anyway"
    log_message "WARNING: FTP server status: $FTP_STATUS"
fi

# Copy files to user's home directory for FTP access
print_status "info" "Preparing files for FTP transfer..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << EOF
# Copy WHOIS file to home directory
if [ -f "$REMOTE_WHOIS_FILE" ]; then
    cp "$REMOTE_WHOIS_FILE" ~/$(basename "$REMOTE_WHOIS_FILE")
    chmod 644 ~/$(basename "$REMOTE_WHOIS_FILE")
fi
EOF

# Download WHOIS file via FTP (while tcpdump is still capturing)
print_status "info" "Downloading WHOIS data via FTP (tcpdump capturing)..."
log_message "Downloading WHOIS data via FTP"

ftp -inv "$REMOTE_IP" << FTPCOMMANDS > /dev/null 2>&1
user $REMOTE_USER $REMOTE_PASS
binary
cd /home/$REMOTE_USER
get $(basename $REMOTE_WHOIS_FILE) $LOCAL_WHOIS_FILE
bye
FTPCOMMANDS

if [ -f "$LOCAL_WHOIS_FILE" ]; then
    print_status "success" "WHOIS data downloaded via FTP"
    log_message "WHOIS data saved to $LOCAL_WHOIS_FILE"
    
    # Display WHOIS results
    echo ""
    print_status "info" "WHOIS Results for $TARGET_ADDRESS:"
    echo "-------------------------------------------"
    cat "$LOCAL_WHOIS_FILE" | head -n 30
    echo "-------------------------------------------"
    echo ""
else
    print_status "error" "Failed to download WHOIS data via FTP"
    log_message "ERROR: Failed to download WHOIS data via FTP"
fi

# Wait a moment to ensure tcpdump captures the FTP traffic
print_status "info" "Allowing time for packet capture to complete..."
sleep 3

# Now stop tcpdump after FTP transfer is complete
print_status "info" "Stopping packet capture..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << EOF
if [ -f /tmp/tcpdump.pid ]; then
    PID=\$(cat /tmp/tcpdump.pid)
    echo "$REMOTE_PASS" | sudo -S kill \$PID 2>/dev/null
    sleep 2
    echo "tcpdump stopped"
else
    echo "no PID file found"
fi
EOF
log_message "Stopped tcpdump on remote server"

sleep 2

# Check tcpdump results
print_status "info" "Checking packet capture results..."
PCAP_SIZE=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "ls -lh /tmp/$PCAP_FILE 2>/dev/null | awk '{print \$5}' || echo 'not_found'")

if [ "$PCAP_SIZE" != "not_found" ]; then
    print_status "success" "PCAP file created on remote server (Size: $PCAP_SIZE)"
    log_message "PCAP file size: $PCAP_SIZE"
else
    print_status "warning" "PCAP file not found on remote server"
    # Check tcpdump log for errors
    TCPDUMP_ERROR=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "cat /tmp/tcpdump.log 2>/dev/null || echo 'no log'")
    print_status "warning" "tcpdump output: $TCPDUMP_ERROR"
    log_message "tcpdump error: $TCPDUMP_ERROR"
fi

# Copy PCAP file to user's home directory for FTP access
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << EOF
# Copy PCAP file to home directory
if [ -f "/tmp/$PCAP_FILE" ]; then
    cp "/tmp/$PCAP_FILE" ~/$PCAP_FILE
    chmod 644 ~/$PCAP_FILE
fi
EOF

# Download PCAP file via FTP
print_status "info" "Downloading packet capture file via FTP..."
LOCAL_PCAP_FILE="$HOME/$PCAP_FILE"

# First check if PCAP file exists on remote server
PCAP_EXISTS=$(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" "test -f /home/$REMOTE_USER/$PCAP_FILE && echo 'yes' || echo 'no'")

if [ "$PCAP_EXISTS" == "yes" ]; then
    ftp -inv "$REMOTE_IP" << FTPCOMMANDS > /dev/null 2>&1
user $REMOTE_USER $REMOTE_PASS
binary
cd /home/$REMOTE_USER
get $PCAP_FILE $LOCAL_PCAP_FILE
bye
FTPCOMMANDS
    
    if [ -f "$LOCAL_PCAP_FILE" ]; then
        print_status "success" "Packet capture downloaded via FTP to $LOCAL_PCAP_FILE"
        log_message "PCAP file saved to $LOCAL_PCAP_FILE"
    else
        print_status "warning" "Failed to download packet capture via FTP"
        log_message "WARNING: Failed to download PCAP file via FTP"
    fi
else
    print_status "warning" "Packet capture file not found in user home directory"
    log_message "WARNING: PCAP file does not exist in home directory"
fi

# Clean up remote server
print_status "info" "Cleaning up remote server..."
sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_IP" << CLEANUP
# Remove specific temporary files created in this session
if [ -f "$REMOTE_WHOIS_FILE" ]; then
    rm -f "$REMOTE_WHOIS_FILE" 2>/dev/null
    echo "Removed $REMOTE_WHOIS_FILE"
fi

if [ -f "/tmp/$PCAP_FILE" ]; then
    echo "$REMOTE_PASS" | sudo -S rm -f "/tmp/$PCAP_FILE" 2>/dev/null
    echo "Removed /tmp/$PCAP_FILE"
fi

if [ -f "/tmp/tcpdump.pid" ]; then
    rm -f /tmp/tcpdump.pid 2>/dev/null
    echo "Removed /tmp/tcpdump.pid"
fi

if [ -f "/tmp/tcpdump.log" ]; then
    rm -f /tmp/tcpdump.log 2>/dev/null
    echo "Removed /tmp/tcpdump.log"
fi

# Remove files from home directory (created for FTP)
if [ -f ~/$(basename $REMOTE_WHOIS_FILE) ]; then
    rm -f ~/$(basename $REMOTE_WHOIS_FILE) 2>/dev/null
    echo "Removed ~/$(basename $REMOTE_WHOIS_FILE)"
fi

if [ -f ~/$PCAP_FILE ]; then
    rm -f ~/$PCAP_FILE 2>/dev/null
    echo "Removed ~/$PCAP_FILE"
fi

# Restore original vsftpd config
if [ -f /etc/vsftpd.conf.backup ]; then
    echo "$REMOTE_PASS" | sudo -S cp /etc/vsftpd.conf.backup /etc/vsftpd.conf 2>/dev/null
    echo "$REMOTE_PASS" | sudo -S rm /etc/vsftpd.conf.backup 2>/dev/null
    echo "$REMOTE_PASS" | sudo -S systemctl restart vsftpd 2>/dev/null || echo "$REMOTE_PASS" | sudo -S service vsftpd restart 2>/dev/null
    echo "Restored vsftpd configuration"
fi

echo "Cleanup complete"
CLEANUP

print_status "success" "Remote server cleaned up"
log_message "Remote server cleaned up"

# Final audit log
echo ""
print_status "success" "=== EXECUTION COMPLETE ==="
echo ""
print_status "info" "Audit Summary:"
echo "  - Log file: $LOG_FILE"
echo "  - WHOIS data: $LOCAL_WHOIS_FILE"
echo "  - Packet capture: $LOCAL_PCAP_FILE"
echo "  - Target analyzed: $TARGET_ADDRESS"
echo "  - Remote server: $REMOTE_IP"
echo ""

log_message "Script execution completed successfully"
log_message "Files created: $LOCAL_WHOIS_FILE, $LOCAL_PCAP_FILE"

print_status "success" "All tasks completed. Check log file for details: $LOG_FILE"
