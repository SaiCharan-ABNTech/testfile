provider "aws" {
  region = var.region
}

resource "aws_sns_topic" "notification_topic" {
  name = "notification-topic"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.notification_topic.arn
  protocol  = "email"
  endpoint  = var.operator_email
}

resource "aws_autoscaling_group" "web_server_group" {
  vpc_zone_identifier = var.subnets
  launch_configuration = aws_launch_configuration.launch_config.id
  min_size             = 1
  max_size             = 3
  target_group_arns    = [aws_lb_target_group.target_group.arn]
  wait_for_capacity_timeout = "0"
  
  notification_configuration {
    topic_arn          = aws_sns_topic.notification_topic.arn
    notification_types = [
      "autoscaling:EC2_INSTANCE_LAUNCH",
      "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
      "autoscaling:EC2_INSTANCE_TERMINATE",
      "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
    ]
  }
  
  tag {
    key                 = "Name"
    value               = "web-server"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "launch_config" {
  name          = "launch-config"
  image_id      = "ami-0776774b8b001036c"
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.instance_sg.id]
  iam_instance_profile = "ec2adminaccess"

  user_data = <<-EOF
    #!/bin/bash -xe
    yum update -y aws-cfn-bootstrap
    yum update -y aws-cli
    /opt/aws/bin/cfn-init -v --stack ${terraform.workspace} --resource launch_config --region ${var.region}
    /opt/aws/bin/cfn-signal -e $? --stack ${terraform.workspace} --resource web_server_group --region ${var.region}
    EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.web_server_group.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.web_server_group.name
}

resource "aws_cloudwatch_alarm" "cpu_high" {
  alarm_description          = "Scale-up if CPU > 90% for 10 minutes"
  metric_name                = "CPUUtilization"
  namespace                  = "AWS/EC2"
  statistic                  = "Average"
  period                     = 300
  evaluation_periods         = 2
  threshold                  = 90
  comparison_operator        = "GreaterThanThreshold"
  alarm_actions              = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server_group.name
  }
}

resource "aws_cloudwatch_alarm" "cpu_low" {
  alarm_description          = "Scale-down if CPU < 70% for 10 minutes"
  metric_name                = "CPUUtilization"
  namespace                  = "AWS/EC2"
  statistic                  = "Average"
  period                     = 300
  evaluation_periods         = 2
  threshold                  = 70
  comparison_operator        = "LessThanThreshold"
  alarm_actions              = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server_group.name
  }
}

resource "aws_lb" "application_load_balancer" {
  name               = "application-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.instance_sg.id]
  subnets            = var.subnets
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.application_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}

resource "aws_lb_target_group" "target_group" {
  name     = "target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    interval            = 30
    timeout             = 5
    healthy_threshold    = 3
    unhealthy_threshold  = 5
  }
}

resource "aws_security_group" "instance_sg" {
  name        = "instance-sg"
  description = "Enable SSH access and HTTP from the load balancer only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_location]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_lb.application_load_balancer.security_groups[0]]
  }
}

output "url" {
  value = "http://${aws_lb.application_load_balancer.dns_name}"
}

