#!/usr/bin/env bash
set -euo pipefail

# Variables

WORKDIR="$(mktemp -d)"
MAIN_PLAYBOOK="$WORKDIR/main.yml"
INSTANCE_STATUS=0
INSTALLED_FLAG="/var/local/.installed"

# Functions

set_instance_sg() {
  local sg_id="$1"
  aws ec2 modify-instance-attribute \
      --instance-id "$INSTANCE_ID" \
      --groups "$sg_id"
}

# 1 - Requeriments

command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip not installed"; exit 1; }

if [ -z "${PLAYBOOK_PATH:-}" ]; then
  echo "ERROR: PLAYBOOK_PATH not provided"
  exit 1
fi

if [ ! -f "$PLAYBOOK_PATH" ]; then
  echo "ERROR: Playbook ZIP not found at: $PLAYBOOK_PATH"
  exit 1
fi

# 2 - Uncompress ZIP

echo "Extracting Ansible playbook ZIP..."

unzip -oq "$PLAYBOOK_PATH" -d "$WORKDIR"

if [ ! -f "$MAIN_PLAYBOOK" ]; then
  echo "ERROR: main.yml not found inside ZIP"
  exit 1
fi

echo "Playbook extracted. main.yml found."

# 3 - Check extravars

echo "Validating EXTRAVARS..."

if [ -z "${EXTRAVARS:-}" ]; then
  echo "EXTRAVARS not provided. Skipping JSON validation."
else
  if echo "$EXTRAVARS" | jq -e . >/dev/null 2>&1; then
    echo "JSON valid."
  else
    echo "ERROR: Invalid JSON"
    exit 1
  fi
fi

# 4 - Load extravars if found

ANSIBLE_EXTRA_VARS_ARGS=()
if [ -n "${EXTRAVARS:-}" ]; then
  ANSIBLE_EXTRA_VARS_ARGS=(--extra-vars "$EXTRAVARS")
fi

# 5 - Assign temporary firewall

echo "Assigning temporary SSH firewall"
set_instance_sg "$SG_TEMP"
echo "Temporary SG applied."

# 6 - Start ssh-agent

eval "$(ssh-agent -s)"
ssh-add <(printf "%s" "$INSTANCE_SSH_KEY")
echo "SSH key loaded into ssh-agent (memory only)"

# 7 - Wait for instance to up

echo "Waiting for instance SSH"

for i in {1..14}; do
  ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$INSTANCE_USER@$INSTANCE_IP" 'exit' >/dev/null 2>&1 && {
        echo "SSH available."
        INSTANCE_STATUS=1
        break
      }
  echo "Instance SSH unavailable, retrying..."
  sleep 5
done

if [ "$INSTANCE_STATUS" -ne 1 ]; then
  echo "ERROR: Instance unreachable, restoring firewall"
  set_instance_sg "$SG_MAIN"
  exit 1
fi

# 8 - Check if installed flag exists

echo "Checking if $INSTALLED_FLAG exists on server"

if ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$INSTANCE_USER@$INSTANCE_IP" "test -f $INSTALLED_FLAG"; then
    echo "Playbook already installed"
    echo "If you need to rerun the playbook you need to enter the server and do sudo rm $INSTALLED_FLAG"
    echo "Restoring firewall"
    set_instance_sg "$SG_MAIN"
    echo "Exiting."
    exit 0
fi

echo "Playbook NOT installed, continuing"

# 9 - Run playbook

echo "Running main.yml playbook"

ansible-playbook \
  -i "${INSTANCE_IP}," \
  -e ansible_python_interpreter=/usr/bin/python3 \
  --user "$INSTANCE_USER" \
  "${ANSIBLE_EXTRA_VARS_ARGS[@]}" \
  --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$MAIN_PLAYBOOK"

echo "Running main.yml playbook finished"

# 10 - Set installed flag

echo "Setting $INSTALLED_FLAG"

ssh -o BatchMode=yes \
    -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$INSTANCE_USER@$INSTANCE_IP" \
    "sudo touch $INSTALLED_FLAG"

echo "Saved $INSTALLED_FLAG"

# 11 - Restore FW

echo "Restoring firewall"
set_instance_sg "$SG_MAIN"

# 12 - Cleanup

rm -rf "$WORKDIR"

# 13 - Done

echo "Script Finished"
