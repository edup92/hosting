locals {
  # Instances

  keypair_name  = "${var.project_name}-keypair-main"
  instance_name  = "${var.project_name}-instance-main"
  disk_name       = "${var.project_name}-disk-main"
  snapshot_name = "${var.project_name}-snapshot-main"
  instanceprofile_name = "${var.project_name}-instanceprofile-main"
  instance_disk_type" = "gp3"
  instance_ami" = "ami-0afadb98a5a7f1807"

  # Secrets

  secret_pem_ssh    = "${var.project_name}-secret-pem-ssh"

  # Roles

  role_dlm_name = "${var.project_name}-role-dlm"
  role_lambda_cfupdater_name = "${var.project_name}-role-lambda-cfupdater"
  role_scheduler_cfupdater_name = "${var.project_name}-role-scheduler-cfupdater"
  role_instanceprofile_name = "${var.project_name}-role-instanceprofile"

  # Policies

  policy_bucket_backup_name = "${var.project_name}-policy-bucket-backup"

  # Network

  firewall_main_name = "${var.project_name}-firewall-main"
  firewall_tempssh_name = "${var.project_name}-firewall-tempssh"
  firewall_test_name = "${var.project_name}-firewall-test"
  eip_name       = "${var.project_name}-eip-main"

  # lambda

  lambda_cfupdater_name       = "${var.project_name}-lambda-cfupdater"
  lambda_runtime" = "python3.12"

  # scheduler

  scheduler_cfupdater_name       = "${var.project_name}-scheduler-cfupdater"

  # ssm

   ssm_ansible_install_name       = "${var.project_name}-ssm-ansible-install"

   # s3

  s3_backup_name       = "${var.project_name}-s3-backup-main"

}