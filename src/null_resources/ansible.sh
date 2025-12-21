#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# Start ssh-agent and load key without files
# ----------------------------------------
eval "$(ssh-agent -s)"
ssh-add <(printf "%s" "$INSTANCE_SSH_KEY")
echo "SSH key loaded into ssh-agent (memory only)"

# ----------------------------------------
# Assign temporary firewall
# ----------------------------------------
echo "Assigning temporary SSH firewall"
aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --groups "$SG_TEMP"

echo "Temporary SG applied."
echo "Waiting for instance SSH"

OK=0
for i in {1..14}; do
  ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$INSTANCE_USER@$INSTANCE_IP" 'exit' >/dev/null 2>&1 && {
        echo "SSH available."
        OK=1
        break
      }
  echo "Instance SSH unavailable, retrying..."
  sleep 5
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: Instance unreachable, restoring firewall"
    aws ec2 modify-instance-attribute \
        --instance-id "$INSTANCE_ID" \
        --groups "$SG_MAIN"
  exit 1
fi

# ----------------------------------------
# Check if playbook was already executed
# ----------------------------------------
echo "Checking if playbook was already executed..."

if ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$INSTANCE_USER@$INSTANCE_IP" "test -f /var/local/.installed"; then
    echo "Playbook already installed"
    echo "If you need to rerun the playbook you need to enter the server and do sudo rm /var/local/.installed"
    echo "Restoring firewall"
    aws ec2 modify-instance-attribute \
        --instance-id "$INSTANCE_ID" \
        --groups "$SG_MAIN"
    echo "Exiting."
    exit 0
fi

echo "Playbook NOT installed. Continuing..."

# ----------------------------------------
# Validate JSON
# ----------------------------------------
echo "Validating JSON..."

if [ -z "${VARS_JSON:-}" ]; then
  echo "VARS_JSON not provided. Skipping JSON validation."
else
  if echo "$VARS_JSON" | jq -e . >/dev/null 2>&1; then
    echo "JSON valid."
  else
    echo "ERROR: Invalid JSON"
    exit 1
  fi
fi

ANSIBLE_EXTRA_VARS_ARGS=()
if [ -n "${VARS_JSON:-}" ]; then
  ANSIBLE_EXTRA_VARS_ARGS=(--extra-vars "$VARS_JSON")
fi

# ----------------------------------------
# Run Ansible without private key argument (ssh-agent handles it)
# ----------------------------------------
ansible-playbook \
  -i "${INSTANCE_IP}," -e ansible_python_interpreter=/usr/bin/python3 \
  --user "$INSTANCE_USER" \
  "${ANSIBLE_EXTRA_VARS_ARGS[@]}" \
  --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$PLAYBOOK_PATH"

echo "Ansible finished correctly"

ssh -o BatchMode=yes \
    -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$INSTANCE_USER@$INSTANCE_IP" \
    "sudo touch /var/local/.installed"

echo "Marked as installed"

# ----------------------------------------
# Restore main firewall
# ----------------------------------------
echo "Restoring firewall"

aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --groups "$SG_MAIN"

echo "DONE"