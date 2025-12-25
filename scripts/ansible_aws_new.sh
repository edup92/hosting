#!/usr/bin/env bash

# 1) Arguments

path_zip="${1:-}"
required_bin=(unzip jq aws ansible)
required_env=(instance_id instance_user instance_pem)
path_temp="$(mktemp -d)"
path_playbook="$path_temp/main.yml"
extravars_file="extravars.json"
sg_tempssh_name="SG_TEMPSSH"

# 2) Functions

cleanup() { rm -rf "$path_temp"; }
trap cleanup EXIT

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

if [[ -z "${extravars:-}" ]] || ! jq -e . >/dev/null 2>&1 <<<"$extravars"; then
  echo "ERROR: extravars is missing/empty or not valid JSON." >&2
  exit 1
fi
echo "OK: extravars is valid JSON"


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

vpc_id="$(jq -r '.Reservations[0].Instances[0].VpcId // empty' <<<"$instance_json")"
instance_ip="$(jq -r '.Reservations[0].Instances[0].PublicIpAddress // empty' <<<"$instance_json")"
instance_sg_list="$(jq -r '.Reservations[0].Instances[0].SecurityGroups[].GroupId' <<<"$instance_json")"

if [[ -z "${vpc_id:-}" || -z "${instance_ip:-}" || -z "${instance_sg_list:-}" ]]; then
  echo "ERROR: Invalid instance data for $instance_id (vpc_id/ip/security_groups)." >&2
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

# 8) Extravars, generate if not found, if not empty, save to extravars_file

if [[ "${extravars+x}" != "x" ]]; then
  jq -n '{}' >"$extravars_file"
else
  printf '%s' "$extravars" | jq -S '.' >"$extravars_file"
fi