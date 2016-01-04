
# Add user and group
target_user=piggysting
useradd -s '/bin/bash' -m -G adm,sudo ${target_user}
echo "Set password for ${target_user}:"
passwd ${target_user}
echo "Set password for root:"
passwd root

# Install packages
echo "apt-get update"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  language-pack-en-base \
  sudo \
  ssh \
  net-tools \
  ethtool \
  wireless-tools \
  ifupdown \
  network-manager \
  iputils-ping \
  rsyslog \
  bash-completion \
  kmod \
  linux-firmware

# Setup hostname
echo 'station001.piggysting' > /etc/hostname
dpkg-reconfigure resolvconf
dpkg-reconfigure tzdata

exit
