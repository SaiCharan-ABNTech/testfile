output "url" {
  description = "The URL of the website"
  value       = "http://${aws_lb.application_load_balancer.dns_name}"
}

