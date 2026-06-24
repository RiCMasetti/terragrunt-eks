output "traefik_role_arn" {
  value = aws_iam_role.traefik.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "vpc_cni_role_arn" {
  value = aws_iam_role.vpc_cni.arn
}
