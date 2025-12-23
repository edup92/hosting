#!/usr/bin/env bash
set -euo pipefail

# Variable validation

required_vars=(
  PLAYBOOK_PATH
  INSTANCE_ID
  INSTANCE_USER
  INSTANCE_SSH_KEY
)
MAIN_PLAYBOOK="$PLAYBOOK_PATH/main.yml"
INSTANCE_STATUS=0
INSTALLED_FLAG="/var/local/.installed"
VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
missing_vars=()

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    missing_vars+=("$var")
  fi
done

if [ "${#missing_vars[@]}" -ne 0 ]; then
  echo "ERROR: Missing required environment variables:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  exit 1
fi

# 2 - Check file

if [ ! -f "$MAIN_PLAYBOOK" ]; then
  echo "ERROR: main.yml not found"
  exit 1
fi

echo "Main.yml found."

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

# 5 - Get instance data

INSTANCE_IP="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp || Reservations[0].Instances[0].PublicIpAddress" \
  --output text)"

INSTANCE_SGS="$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
  --output text)"

# 6 - Create TEMP SG

SG_TEMP_ID="$(aws ec2 create-security-group \
  --group-name "SG_TEMPSSH" \
  --description "Temporary SSH access" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)"

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_TEMP_ID" \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"0.0.0.0/0"}],"Ipv6Ranges":[{"CidrIpv6":"::/0"}]}
  ]' >/dev/null 2>&1

aws ec2 authorize-security-group-egress \
  --group-id "$SG_TEMP_ID" \
  --ip-permissions '[
    {"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}],"Ipv6Ranges":[{"CidrIpv6":"::/0"}]}
  ]' >/dev/null 2>&1 || true

echo "Created temporary SSH SG"

# 7 - Assign temporary firewall

echo "Assigning temporary SSH firewall"
aws ec2 modify-instance-attribute \
  --instance-id "$INSTANCE_ID" \
  --groups $INSTANCE_SGS "$SG_TEMP_ID"
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
  aws ec2 modify-instance-attribute \
  --instance-id "$INSTANCE_ID" \
  --groups $INSTANCE_SGS
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
    aws ec2 modify-instance-attribute \
    --instance-id "$INSTANCE_ID" \
    --groups $INSTANCE_SGS
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

aws ec2 modify-instance-attribute \
  --instance-id "$INSTANCE_ID" \
  --groups $INSTANCE_SGS

# 12 - Cleanup

rm -rf "$WORKDIR"
aws ec2 delete-security-group --group-id "$SG_TEMP_ID"  >/dev/null 2>&1 || true

# 13 - Done

echo "Script Finished"
