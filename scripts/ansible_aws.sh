#!/usr/bin/env bash

# 1) Arguments

path_zip="${1:-}"
required_bin=(unzip jq aws ansible)
required_env=(instance_id instance_user instance_pem)
path_temp="$(mktemp -d)"
path_playbook="$path_temp/main.yml"
extravars_file="extravars.json"
sg_tempssh_name="SG_TEMPSSH"
instance_desired_state="running"
instance_desired_state_sleep=3
instance_desired_state_deadline=$((SECONDS + 120))

# 2) Functions


# 3) Requirements (env, file, OS, binaries)

echo "Checking requeriments"

if ! grep -q '^ID=ubuntu$' /etc/os-release; then
  echo "ERROR: Runner must be Ubuntu." >&2
  exit 7
fi
echo "OK: Runner is Ubuntu"

for bin in "${required_bin[@]}"; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: Runner '$bin' not found." >&2
    exit 3
  fi
done
echo "OK: Required binaries found: ${required_bin[*]}"

if [[ -z "${path_zip:-}" || ! -f "$path_zip" ]]; then
  echo "ERROR: Missing or invalid file. Usage: $0 /path/to/playbook.zip" >&2
  exit 2
fi
echo "OK: Playbook zip found: $path_zip"

for v in "${required_env[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: Missing required env var: $v" >&2
    exit 1
  fi
done
echo "OK: Required env vars present: ${required_env[*]}"

if [[ -n "${extravars+x}" ]]; then
  if [[ -z "${extravars:-}" ]] || ! jq -e . >/dev/null 2>&1 <<<"$extravars"; then
    echo "ERROR: extravars exists but is empty or not valid JSON." >&2
    exit 1
  fi
  echo "OK: extravars is valid JSON"
fi

if ! ssh-keygen -y -f <(printf '%s' "$instance_pem") >/dev/null 2>&1; then
  echo "ERROR: instance_pem is not a valid private key (PEM)." >&2
  exit 1
fi
echo "OK: instance PEM is valid"

# 4) Unzip, error if fails or main.yml not found

echo "Unziping playbook"

if ! unzip -q "$path_zip" -d "$path_temp" || [[ ! -f "$path_playbook" ]]; then
  echo "ERROR: Unzip failed or main.yml missing." >&2
  exit 4
fi

echo "OK: playbook unzipped and contains main.yml"

# 5) Check aws access

echo "Checking aws credentials"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: No AWS access (credentials/permissions/region may be misconfigured)." >&2
  exit 1
fi

echo "OK: AWS credentials OK"

# 6) Get instance data

echo "Getting Instance data"

instance_json="$(aws ec2 describe-instances --instance-ids "$instance_id" --output json)" || {
  echo "ERROR: EC2 instance not found: $instance_id" >&2
  exit 1
}

instance_state="$(jq -r '.Reservations[0].Instances[0].State.Name // empty' <<<"$instance_json")"
vpc_id="$(jq -r '.Reservations[0].Instances[0].VpcId // empty' <<<"$instance_json")"
instance_ip="$(jq -r '.Reservations[0].Instances[0].PublicIpAddress // empty' <<<"$instance_json")"
instance_sg_list="$(aws ec2 describe-instances --instance-ids "$instance_id" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text)"

if [[ -z "${instance_state:-}" || -z "${instance_ip:-}" || -z "${instance_sg_list:-}" ]]; then
  echo "ERROR: Could not determine instance state for: $instance_id" >&2
  exit 1
fi

echo "OK: AWS instance data adquired"

# 7) Create tempssh SG

echo "Checking temporary SSH SG"

sg_tempssh_id="$(
  aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=$sg_tempssh_name" \
    --query 'SecurityGroups[0].GroupId' \
    --output text
)"

if [[ -n "${sg_tempssh_id:-}" && "$sg_tempssh_id" != "None" ]]; then
  echo "OK: SG '$sg_tempssh_name' already exists ($sg_tempssh_id). It will not be recreated."
else
  echo "INFO: SG '$sg_tempssh_name' not found in VPC '$vpc_id'. Creating it..."

  sg_tempssh_id="$(
    aws ec2 create-security-group \
      --vpc-id "$vpc_id" \
      --group-name "$sg_tempssh_name" \
      --description "Temporary SSH access" \
      --query 'GroupId' \
      --output text
  )"

  aws ec2 authorize-security-group-ingress \
    --group-id "$sg_tempssh_id" \
    --ip-permissions '[
      {"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"SSH anywhere IPv4"}]},
      {"IpProtocol":"tcp","FromPort":22,"FromPort":22,"ToPort":22,"Ipv6Ranges":[{"CidrIpv6":"::/0","Description":"SSH anywhere IPv6"}]}
    ]' \
    >/dev/null 2>&1

  aws ec2 authorize-security-group-egress \
    --group-id "$sg_tempssh_id" \
    --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"All outbound IPv4"}]}]' \
    >/dev/null 2>&1 || true

  aws ec2 authorize-security-group-egress \
    --group-id "$sg_tempssh_id" \
    --ip-permissions '[{"IpProtocol":"-1","Ipv6Ranges":[{"CidrIpv6":"::/0","Description":"All outbound IPv6"}]}]' \
    >/dev/null 2>&1 || true

  echo "OK: SG '$sg_tempssh_name' created ($sg_tempssh_id) with SSH ingress + allow-all egress."
fi

echo "OK: Created TempSSH SG"

# 8) Extravars, generate if not found, if not empty, save to extravars_file

if [[ "${extravars+x}" != "x" ]]; then
  jq -n '{}' >"$extravars_file"
else
  printf '%s' "$extravars" | jq -S '.' >"$extravars_file"
fi

# 9) Set tempssh sg

aws ec2 modify-instance-attribute \
  --instance-id "$instance_id" \
  --groups $instance_sg_list "$sg_tempssh_id" \
  >/dev/null 2>&1

# 10) Check instance state

echo "Checking instance state"

while [[ "$instance_state" != "$instance_desired_state" ]]; do
  if (( SECONDS >= instance_desired_state_deadline )); then
    echo "ERROR: Timeout waiting for instance '$instance_id' to reach state '$instance_desired_state' (last: '$instance_state')." >&2
    echo "Restoring original SG"
    aws ec2 modify-instance-attribute \
      --instance-id "$instance_id" \
      --groups $instance_sg_list \
      >/dev/null 2>&1
    echo "Restored original SG"
    rm -rf path_temp
    echo "Removed temp path $path_temp"
    echo "Finished script"
    exit 1
  fi

  echo "INFO: instance_state=$instance_state (waiting for $instance_desired_state)"
  sleep "$instance_desired_state_sleep"

  instance_state="$(
    aws ec2 describe-instances --instance-ids "$instance_id" --output json \
    | jq -r '.Reservations[0].Instances[0].State.Name // empty'
  )"

  if [[ -z "${instance_state:-}" ]]; then
    echo "ERROR: Could not determine instance state for: $instance_id" >&2
    exit 1
  fi
done

echo "OK: Instance is in desired state: $instance_desired_state"

echo "Checking SSH reachability"

while :; do
  if (( SECONDS >= instance_desired_state_deadline )); then
    echo "ERROR: Timeout waiting for SSH on $instance_user@$instance_ip" >&2
    echo "Restoring original SG"
    aws ec2 modify-instance-attribute \
      --instance-id "$instance_id" \
      --groups $instance_sg_list \
      >/dev/null 2>&1
    echo "Restored original SG"
    rm -rf path_temp
    echo "Removed temp path $path_temp"
    echo "Finished script"
    exit 1
  fi

  if ssh \
    -i <(printf '%s' "$instance_pem") \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 \
    "$instance_user@$instance_ip" "true" \
    >/dev/null 2>&1; then
    echo "OK: SSH reachable on $instance_user@$instance_ip"
    break
  fi

  echo "INFO: SSH not reachable yet on $instance_user@$instance_ip (retrying)"
  sleep "$instance_desired_state_sleep"
done

# 11) Run playbook

echo "Running main.yml playbook"

ansible-playbook \
  -i "${instance_ip}," \
  -e ansible_python_interpreter=/usr/bin/python3 \
  --user "$instance_user" \
  -e @"$extravars_file" \
  --private-key <(printf '%s' "$instance_pem") \
  --ssh-extra-args="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$path_playbook"

echo "Running main.yml playbook finished"

echo "Restoring original SG"
aws ec2 modify-instance-attribute \
  --instance-id "$instance_id" \
  --groups $instance_sg_list \
  >/dev/null 2>&1
echo "Restored original SG"
rm -rf path_temp
echo "Removed temp path $path_temp"
echo "Finished script"

exit 1