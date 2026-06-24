output "nlb_dns_name" {
  value = aws_lb.this.dns_name
}

output "nlb_arn" {
  value = aws_lb.this.arn
}

output "nlb_zone_id" {
  value = aws_lb.this.zone_id
}
