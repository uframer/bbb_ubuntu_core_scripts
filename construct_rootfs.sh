
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
while read package_name ; do
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y ${package_name}
done < /scripts/package.list

dpkg-reconfigure resolvconf
dpkg-reconfigure tzdata

# Setup hosts
echo "station001.piggysting" > /etc/hostname
echo "127.0.0.1    localhost" > /etc/hosts
echo "127.0.0.1    station001.piggysting" >> /etc/hosts

exit
