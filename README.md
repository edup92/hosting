# hosting-temp

# Run bootstrap.sh on Cloudshell
# Paste VARS_JSON as secret in Github Actions. Required JSON:

{
  "aws_access_key_id": "",
  "aws_secret_access_key": "",
  "aws_region": "eu-south-2",
  "cf_token": "",
  "uptimerobot_token": "",
  "admin_ip": "X.X.X.X/32",
  "project_name": "",
  "instance_type": "t4g.small",
  "instance_disk_size": "25",
  "sites":  {
    "site1": {
        "domain": "domain.tld",
        "monitor_keyworkd": ""
    }
    ...
  }
}

# Run playbook