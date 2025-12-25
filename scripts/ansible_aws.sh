

echo "Created temporary SSH SG"

# 7 - Assign temporary firewall

echo "Assigning temporary SSH firewall"
aws ec2 modify-instance-attribute \
  --instance-id "$instance_id" \
  --groups $INSTANCE_SGS "$SG_TEMP_ID"
echo "Temporary SG applied."

# 6 - Start ssh-agent

eval "$(ssh-agent -s)"
ssh-add <(printf "%s" "$instance_pem")
echo "SSH key loaded into ssh-agent (memory only)"

# 7 - Wait for instance to up

echo "Waiting for instance SSH"

for i in {1..14}; do
  ssh -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "$instance_user@$INSTANCE_IP" 'exit' >/dev/null 2>&1 && {
        echo "SSH available."
        INSTANCE_STATUS=1
        break
      }
  echo "Instance SSH unavailable, retrying..."
  sleep 5
done

if [ "$INSTANCE_STATUS" -ne 1 ]; then
  echo "ERROR: Instance unreachable, restoring firewall"
  aws ec2 modify-instance-attribute \
  --instance-id "$instance_id" \
  --groups $INSTANCE_SGS
  exit 1
fi

# 8 - Run playbook

echo "Running main.yml playbook"

ansible-playbook \
  -i "${INSTANCE_IP}," \
  -e ansible_python_interpreter=/usr/bin/python3 \
  --user "$instance_user" \
  -e @vars.json \
  --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$MAIN_PLAYBOOK"

echo "Running main.yml playbook finished"

# 9 - Restore FW

echo "Restoring firewall"

aws ec2 modify-instance-attribute \
  --instance-id "$instance_id" \
  --groups $INSTANCE_SGS

# 10 - Cleanup

aws ec2 delete-security-group --group-id "$SG_TEMP_ID"  >/dev/null 2>&1 || true

# 11 - Done

echo "Script Finished"