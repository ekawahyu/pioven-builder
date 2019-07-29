#!/bin/sh

exec 2>> /var/log/rc.local.log # send stderr from rc.local to a log file
exec 1>&2

set -x
set -e

DATA_DIR=/opt/data

stage_one(){
if [ "%PI_USERNAME%" != "pi" ]; then
#
# Delete "pi" user and create another one
#
useradd -m %PI_USERNAME% -G sudo || true
echo "%PI_USERNAME% ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_%PI_USERNAME%-nopasswd
rm /etc/sudoers.d/010_pi-nopasswd
deluser -remove-home pi
#
# Change user and group ID
#
usermod -u 1000 --shell /bin/bash %PI_USERNAME%
groupmod -g 1000 %PI_USERNAME%
fi
#
# Change user password
#
echo "%PI_USERNAME%:%PI_PASSWORD%" | chpasswd
#
# Install SSH key
#
install -d -m 700 /home/%PI_USERNAME%/.ssh
mv /id_rsa.pub /home/%PI_USERNAME%/.ssh/authorized_keys
chown %PI_USERNAME%:%PI_USERNAME% -Rf /home/%PI_USERNAME%/.ssh/
#
# Modify sources.list to point to US mirror
#
sudo sed -e '/deb.*/ s/^#*/#/' -i /etc/apt/sources.list
sudo bash -c 'cat >> /etc/apt/sources.list << EOL
deb http://mirrors.ocf.berkeley.edu/raspbian/raspbian/ stretch main contrib non-free rpi
EOL'
sudo sed -e '/deb.*/ s/^#*/#/' -i /etc/apt/sources.list.d/raspi.list
sudo bash -c 'cat >> /etc/apt/sources.list.d/raspi.list << EOL
deb http://mirrors.ocf.berkeley.edu/rasppi/debian/ stretch main ui
EOL'
sudo apt-get update
sudo apt-get -y upgrade
}

stage_two(){
#
# Install hostapd and dnsmasq
#
sudo apt-get install -y hostapd dnsmasq socat
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo bash -c 'cat >> /etc/dhcpcd.conf << EOL
interface wlan0
	static ip_address=192.168.50.1/24
	nohook wpa_supplicant
EOL'
# sudo systemctl restart dhcpcd
sudo touch /etc/hostapd/hostapd.conf
sudo chmod g+w /etc/hostapd/hostapd.conf
sudo bash -c 'cat > /etc/hostapd/hostapd.conf << EOL
interface=wlan0
driver=nl80211

hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=0
macaddr_acl=0
ignore_broadcast_ssid=0

auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP

# This is the name of the network
ssid=gateway
# The network passphrase
wpa_passphrase=password
EOL'
#
# Assign ssid=gateway-xxxx and random password
#
sudo sed -i '/^ssid=/s/.*/'"$(sed 's/://g' /sys/class/net/wlan0/address | sed 's/.*\(....\)$/\1/' | sed 's/.*/ssid=%PI_HOSTNAME%-&/')"'/' /etc/hostapd/hostapd.conf
sudo sed -i '/^wpa_passphrase=/s/.*/wpa_passphrase=%PI_PASSWORD%/' /etc/hostapd/hostapd.conf
sudo sed -i '/127.0.1.1\traspberrypi/s/.*/'"$(sed 's/://g' /sys/class/net/wlan0/address | sed 's/.*\(....\)$/\1/' | sed 's/.*/127.0.1.1\t%PI_HOSTNAME%-&/')"'/' /etc/hosts
sed 's/://g' /sys/class/net/wlan0/address | sed 's/.*\(....\)$/\1/' | sed 's/.*/%PI_HOSTNAME%-&/' | sudo tee /etc/hostname > /dev/null 2>&1
#
# Configure hostapd and port forwarding
#
sudo sed -i 's/#DAEMON_CONF=.*/DAEMON_CONF=\"\/etc\/hostapd\/hostapd.conf\"/g' /etc/default/hostapd
sudo sed -i 's/DAEMON_CONF=.*/DAEMON_CONF=\/etc\/hostapd\/hostapd.conf/g' /etc/init.d/hostapd
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo bash -c 'cat > /etc/dnsmasq.conf << EOL
interface=wlan0      # Use interface wlan0  
server=1.1.1.1       # Use Cloudflare DNS  
dhcp-range=192.168.50.10,192.168.50.50,12h # IP range and lease time
EOL'
sudo sed -i 's/#net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sudo bash -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo bash -c 'iptables-save > /etc/iptables.ipv4.nat'
sudo sed '/exit 0/i iptables-restore < \/etc\/iptables.ipv4.nat\n' /etc/rc.local
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl start hostapd
sudo service dnsmasq start
sudo bash -c 'cat >> /broadcast-info.sh << EOL
sudo echo 'this is testing socat' | socat - udp-sendto:255.255.255.255:12345,broadcast
EOL'
sudo echo 'this is testing direct socat' | socat - udp-sendto:255.255.255.255:12345,broadcast
}

if [ -f /var/log/rebooting-done ]; then
sudo rm /var/log/rebooting-done
sudo sed -i '\/first_run_gateway.sh/d' /etc/rc.local
sudo rm -Rf ${DATA_DIR}
sudo rm -- "$0"
echo 'Deleted current script and rebooting!'
sudo reboot
elif [ -f /var/log/rebooting-to-stage-2 ]; then
stage_two
sudo rm /var/log/rebooting-to-stage-2
sudo touch /var/log/rebooting-done
sudo reboot
else
stage_one
sudo touch /var/log/rebooting-to-stage-2
sudo reboot
fi

# Configure hostname
#randomWord1=$(shuf ${DATA_DIR}/words.txt -n 1 | sed -e "s/\s/-/g")
#randomWord2=$(shuf ${DATA_DIR}/words.txt -n 1 | sed -e "s/\s/-/g")
#PI_CONFIG_HOSTNAME="%PI_HOSTNAME%-${randomWord1}-${randomWord2}"

#echo "${PI_CONFIG_HOSTNAME}" > "/etc/hostname"
#OLD_HOST="raspberrypi"
#sed -i "s/$OLD_HOST/$PI_CONFIG_HOSTNAME/g" "/etc/hosts"
#hostnamectl set-hostname "${PI_CONFIG_HOSTNAME}"

# Configure the memory split
#if test "%PI_GPU_MEMORY%" = "16" || test "%PI_GPU_MEMORY%" = "32" || test "%PI_GPU_MEMORY%" = "64" || test "%PI_GPU_MEMORY%" = "128" || test "%PI_GPU_MEMORY%" = "256"; then
#  echo "gpu_mem=%PI_GPU_MEMORY%" >> /boot/config.txt
#fi

# Configure static IP address
#apt-get -qq update
#apt-get install -y python-dev python-pip
#pip install netifaces

#export TARGET_IP="target_ip"
#export NETWORK_CONFIG="/etc/network/interfaces"
#export PI_IP_ADDRESS_RANGE_START="%PI_IP_ADDRESS_RANGE_START%"
#export PI_IP_ADDRESS_RANGE_END="%PI_IP_ADDRESS_RANGE_END%"
#export PI_DNS_ADDRESS="%PI_DNS_ADDRESS%"
#python /interfaces.py

#cat /etc/network/interfaces
#rm /interfaces.py
#pip uninstall -y netifaces
#apt-get remove -y python-dev python-pip

#PI_IP_ADDRESS=$(cat ./target_ip)
#rm ./target_ip

# Remove DHCPCD5 - https://www.raspberrypi.org/forums/viewtopic.php?t=111709
#apt-get remove -y dhcpcd5

# Install Docker
#if "%PI_INSTALL_DOCKER%" -eq "true"; then
#  curl -sSL https://get.docker.com | CHANNEL=stable sh
#  usermod -aG docker %PI_USERNAME%
#fi

# Send email telling about this server
#if test "%PI_MAILGUN_API_KEY%" && test "%PI_MAILGUN_DOMAIN%" && test "%PI_EMAIL_ADDRESS%"; then
#  curl -s --user "api:%PI_MAILGUN_API_KEY%" \
#    https://api.mailgun.net/v3/%PI_MAILGUN_DOMAIN%/messages \
#    -F from="%PI_USERNAME%@%PI_MAILGUN_DOMAIN%" \
#    -F to=%PI_EMAIL_ADDRESS% \
#    -F subject="New Raspberry Pi (${PI_CONFIG_HOSTNAME}) set up" \
#    -F text="New %PI_USERNAME%@${PI_CONFIG_HOSTNAME} setup on: ${PI_IP_ADDRESS}"
#fi

#rm -Rf ${DATA_DIR}

#rm -- "$0"

#echo "Deleted current script"
