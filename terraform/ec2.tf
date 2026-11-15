data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true
  monitoring                  = var.detailed_monitoring

  # "standard" credits: a long CPU stress test can't run up T3 Unlimited charges
  credit_specification {
    cpu_credits = "standard"
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    region    = var.region
    log_group    = aws_cloudwatch_log_group.app.name
    service_name = var.service_name
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name_prefix}-app"
  }

  # The instance needs the internet route at boot to reach SSM, CloudWatch and dnf.
  depends_on = [aws_cloudwatch_log_group.app, aws_route_table_association.public]
}
