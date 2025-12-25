#!/usr/bin/env bash

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
SG_NAME="SG_TEMPSSH"
missing_vars=()



TYPE="${each.value.monitor_type}"
URL="https://${each.value.domain}"
FRIENDLY_NAME="${each.value.domain}"
INTERVAL="${each.value.interval}"

# UptimeRobot expects "alert_contacts" as: "<id>_<threshold>_<recurrence>"
# threshold: number of incidents before alert (p.ej 1)
# recurrence: minutes between repeated alerts (p.ej 0=no repeats)
ALERT_CONTACTS="${var.uptimerobot_alert_contact_id}_1_0"

if [ "$TYPE" = "KEYWORD" ]; then
if [ -z "${try(each.value.keyword_value, "")}" ]; then
    echo "ERROR: keyword_value is required when monitor_type=KEYWORD for ${each.value.domain}" >&2
    exit 1
fi

curl -sS -X POST "${local.api_base}/newMonitor" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "api_key=${var.uptimerobot_api_key}" \
    --data-urlencode "format=json" \
    --data-urlencode "type=3" \
    --data-urlencode "url=$URL" \
    --data-urlencode "friendly_name=$FRIENDLY_NAME" \
    --data-urlencode "interval=$INTERVAL" \
    --data-urlencode "keyword_type=${try(each.value.keyword_type, "ALERT_NOT_EXISTS")}" \
    --data-urlencode "keyword_value=${each.value.keyword_value}" \
    --data-urlencode "alert_contacts=$ALERT_CONTACTS" \
    | jq -e '.stat=="ok"' >/dev/null
else
# HTTP monitor (type=1)
curl -sS -X POST "${local.api_base}/newMonitor" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "api_key=${var.uptimerobot_api_key}" \
    --data-urlencode "format=json" \
    --data-urlencode "type=1" \
    --data-urlencode "url=$URL" \
    --data-urlencode "friendly_name=$FRIENDLY_NAME" \
    --data-urlencode "interval=$INTERVAL" \
    --data-urlencode "alert_contacts=$ALERT_CONTACTS" \
    | jq -e '.stat=="ok"' >/dev/null
fi

echo "Created/updated monitor request sent for ${each.value.domain}"
