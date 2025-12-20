#!/usr/bin/env bash
set -euo pipefail

USERNAME="${1:-admin-$(date +%s)}"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Requirements
command -v aws >/dev/null 2>&1 || { echo "aws CLI not found."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not found."; exit 1; }

echo "Creating IAM user: $USERNAME"

# Check if user already exists
if aws iam get-user --user-name "$USERNAME" >/dev/null 2>&1; then
  echo "Error: User '$USERNAME' already exists."
  exit 1
fi

# Create user without tags
aws iam create-user --user-name "$USERNAME"
echo "User created: $USERNAME"

# Attach admin policy
aws iam attach-user-policy \
  --user-name "$USERNAME" \
  --policy-arn "$POLICY_ARN"

echo "Policy attached: $POLICY_ARN"

# Create access key
CREDS_JSON=$(aws iam create-access-key --user-name "$USERNAME" --output json)

ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKey.SecretAccessKey')

# Display credentials once
cat <<EOF
--- TEMPORARY IAM USER CREDENTIALS ---
UserName:         $USERNAME
AccessKeyId:      $ACCESS_KEY_ID
SecretAccessKey:  $SECRET_ACCESS_KEY
--------------------------------------
NOTE: The SecretAccessKey is shown only once.
EOF

echo "Temporary IAM user created successfully."
