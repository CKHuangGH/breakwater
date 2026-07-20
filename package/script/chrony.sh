NODE_LIST="./all_node_list"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"


if [[ ! -f "$NODE_LIST" ]]; then
  echo "Error: $NODE_LIST not found" >&2
  exit 1
fi


MGMT_IP=$(head -n 1 "$NODE_LIST" | awk '{print $1}')
if [[ -z "$MGMT_IP" ]]; then
  echo "Error: First line of $NODE_LIST is empty" >&2
  exit 1
fi
echo "Management IP: $MGMT_IP"


LOCAL_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$LOCAL_IP" ]]; then
  echo "Error: Failed to get local IP" >&2
  exit 1
fi
echo "Local IP: $LOCAL_IP"

CHRONY_CONF="/etc/chrony/chrony.conf"

if [[ -f "$CHRONY_CONF" ]]; then
  sudo cp -p "$CHRONY_CONF" "${CHRONY_CONF}.orig-${TIMESTAMP}"
fi

if [[ "$LOCAL_IP" == "$MGMT_IP" ]]; then
  echo "Configuring as Management Node (NTP Server)"
  sudo tee "$CHRONY_CONF" > /dev/null <<EOF
# chrony.conf - Management Node
driftfile /var/lib/chrony/chrony.drift
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
pool 2.pool.ntp.org iburst
pool 3.pool.ntp.org iburst

allow 10.0.0.0/8
local stratum 10
logdir /var/log/chrony
EOF
else
  echo "Configuring as Client (syncing from $MGMT_IP)"
  sudo tee "$CHRONY_CONF" > /dev/null <<EOF
# chrony.conf - Client
driftfile /var/lib/chrony/chrony.drift
server $MGMT_IP iburst minpoll 4 maxpoll 4

logdir /var/log/chrony
EOF
fi

sudo systemctl enable chrony
sudo systemctl restart chrony