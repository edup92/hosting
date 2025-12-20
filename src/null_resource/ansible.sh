#!/usr/bin/env bash
set -euo pipefail

# Asignar Security Group temporal para SSH
echo "Assigning temporary SSH security group: $SG_TEMP"

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
      -i "$INSTANCE_SSH_KEY" \
      $USER@"$IP" 'exit' >/dev/null 2>&1 && {
        echo "SSH available."
        OK=1
        break
      }
  echo "Instance SSH unavailable, retrying..."
  sleep 5
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: Instance unreachable, restoring main SG..."
  aws ec2 modify-instance-attribute \
      --instance-id "$INSTANCE_ID" \
      --groups "$SG_MAIN"
  exit 1
fi

# Check if is installed
echo "Checking if playbook was already executed..."

if ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -i "$SSH_KEY" \
      $INSTANCE_USER@"$IP" \
      "test -f /.installed"; then

    echo "Playbook already installed. Exiting."
    exit 0
fi

# Ejecutar Ansible
ansible-playbook \
  -i "$IP," \
  --user $INSTANCE_USER \
  --private-key "$INSTANCE_SSH_KEY" \
  --extra-vars "@$VARS_FILE" \
  --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$PLAYBOOK_PATH"

# Marking as installed

echo "Settign as installed"

ssh -o BatchMode=yes \
    -o ConnectTimeout=3 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" \
    $INSTANCE_USER@"$IP" \
    "sudo touch /.installed"

# Restaurar SG principal
echo "Restoring main security group: $SG_MAIN"

aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --groups "$SG_MAIN"

echo "DONE"
