# SSH Key

resource "tls_private_key" "pem_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "keypair_main" {
  key_name   = local.keypair_name
  public_key = tls_private_key.pem_ssh.public_key_openssh
}

resource "aws_secretsmanager_secret" "secret_pem_ssh" {
  name = local.secret_pem_ssh
}

resource "aws_secretsmanager_secret_version" "secretversion_pem_ssh" {
  secret_id     = aws_secretsmanager_secret.secret_pem_ssh.id
  secret_string = jsonencode({
    private_key = tls_private_key.pem_ssh.private_key_pem
    public_key  = tls_private_key.pem_ssh.public_key_openssh
  })
}

# SG

resource "aws_security_group" "sg_main" {
  name        = local.firewall_main_name
  description = "Security group ${local.firewall_main_name}"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    Name = local.firewall_main_name
  }
}

resource "aws_security_group" "sg_test" {
  name        = local.firewall_test_name
  description = "Security group ${local.firewall_test_name}"
  vpc_id      = data.aws_vpc.default.id
  tags = {
    Name = local.firewall_test_name
  }
}

resource "aws_security_group_rule" "sgrule_main_adminaccess" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs
  security_group_id = aws_security_group.sg_main.id
  description       = "Allow HTTPS from Cloudflare (IPv4)"
}

resource "aws_security_group_rule" "sgrule_main_ipv4" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.admin_ip]
  security_group_id = aws_security_group.sg_main.id
  description       = "Allow Admin Access"
}

resource "aws_security_group_rule" "sgrule_main_ipv6" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  ipv6_cidr_blocks  = data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs
  security_group_id = aws_security_group.sg_main.id
  description       = "Allow HTTPS from Cloudflare (IPv6)"
}

resource "aws_security_group_rule" "sgrule_main_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.sg_main.id
  description       = "Allow egress"
}

resource "aws_security_group_rule" "sgrule_test" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.sg_test.id
  description       = "Allow all traffic from anywhere (IPv4 & IPv6)"
}

resource "aws_security_group_rule" "sgrule_test_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.sg_test.id
  description       = "Allow egress"
}

# Instance

resource "aws_iam_role" "role_instanceprofile" {
  name = local.role_instanceprofile_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "instanceprofile_main" {
  name = local.instanceprofile_name
  role = aws_iam_role.role_instanceprofile.name
}

resource "aws_instance" "instance_main" {
  ami                    = local.instance_ami
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.sg_main.id]
  iam_instance_profile = aws_iam_instance_profile.instanceprofile_main.name
  key_name               = aws_key_pair.keypair_main.key_name
  root_block_device {
    volume_type           = local.instance_disk_type
    volume_size           = var.instance_disk_size
    delete_on_termination = true
    tags = {
      Name = local.disk_name
    }
  }
  tags = {
    Name = local.instance_name
  }
}

resource "aws_eip" "eip_main" {
  tags = {
    Name = local.eip_name
  }
}

resource "aws_eip_association" "eipassoc_main" {
  instance_id   = aws_instance.instance_main.id
  allocation_id = aws_eip.eip_main.id
}

# Snapshot

resource "aws_iam_role" "role_dlm" {
  name = local.role_dlm_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "dlm.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "policyattach_dlm" {
  role       = aws_iam_role.role_dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "dlm_main" {
  execution_role_arn = aws_iam_role.role_dlm.arn
  description = "Dlm for ${local.instance_name}"
  state              = "ENABLED"
  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Name = local.disk_name
    }
    schedule {
      name = "daily-snapshots"
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["00:00"]
      }
      retain_rule {
        count = 30
      }
    }
  }
  tags = {
    Name = local.snapshot_name
  }
}

# Cloduflare ip updater

resource "aws_iam_role" "role_cfupdater" {
  name = local.role_lambda_cfupdater_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "policy_lambda_cfupdater" {
  role = aws_iam_role.role_cfupdater.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups"
        ]
        Resource = aws_security_group.sg_main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = aws_security_group.sg_main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "lambda_cfupdater" {
  function_name = local.lambda_cfupdater_name
  role          = aws_iam_role.role_cfupdater.arn
  handler       = "main.lambda_handler"
  runtime       = local.lambda_runtime
  filename      = "./artifacts/lambda/cfupdater.zip"
  environment {
    variables = {
      SG_ID = aws_security_group.sg_main.id
    }
  }
  timeout = 30
}

resource "aws_iam_role" "role_scheduler_cfupdater" {
  name = local.role_scheduler_cfupdater_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "policy_scheduler_cfupdater" {
  role = aws_iam_role.role_scheduler_cfupdater.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = aws_lambda_function.lambda_cfupdater.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "cfupdater_daily" {
  name        = local.scheduler_cfupdater_name
  schedule_expression          = "rate(24 hours)"
  schedule_expression_timezone = "UTC"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_lambda_function.lambda_cfupdater.arn
    role_arn = aws_iam_role.role_scheduler_cfupdater.arn
  }
}

# S3 Backup

resource "aws_s3_bucket" "bucket_backup" {
  bucket = local.s3_backup_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bucketsse_backup" {
  bucket = aws_s3_bucket.bucket_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_policy" "policy_bucket_backup" {
  name = local.policy_bucket_backup_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.bucket_backup.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.bucket_backup.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "policyattach_bucket_backup" {
  role       = aws_iam_role.role_instanceprofile.name
  policy_arn = aws_iam_policy.policy_bucket_backup.arn
}

# Playbook

resource "null_resource" "null_ansible_main" {
  depends_on = [
    aws_instance.instance_main
  ]
  triggers = {
    instance_id   = aws_instance.instance_main.id
    ansible_tree_sha  = local.ansible_tree_sha
  }
  provisioner "local-exec" {
    environment = {
      INSTANCE_ID    = aws_instance.instance_main.id
      INSTANCE_USER  = local.ansible_user
      INSTANCE_SSH_KEY = nonsensitive(tls_private_key.pem_ssh.private_key_pem)
      EXTRAVARS = jsonencode({
        sites = var.sites
      })
      PLAYBOOK_PATH = local.ansible_path
    }
    command = local.script_ansible
  }
}

# Cloudflare



# Uptimerobot

#resource "uptimerobot_monitor" "uptimerobot_main" {
#  for_each          = var.sites
#  name              = each.value.domain
#  type              = "KEYWORD"
#  url               = "https://${each.value.domain}"
#  interval          = 900 
#  keyword_value     = each.value.monitor_keyword
#}

#resource "uptimerobot_monitor" "uptimerobot_main" {
#  for_each          = var.sites
#  name     = each.value.domain
#  type     = "KEYWORD"
#  url      = "https://${each.value.domain}"
#  interval = 900

  # Look for "healthy" in the response
 # keyword_type  = "ALERT_NOT_EXISTS"
 # keyword_value     = trimspace(each.value.monitor_keyword)

  # Case insensitive search (default)
 # keyword_case_type = "CaseInsensitive"

  # Set exact contacts and their semantics
 # assigned_alert_contacts = [
 #   {
 #     alert_contact_id = "6819028",
 #     threshold        = 10,
 #     recurrence       = 15
 #   }
 # ]

#}