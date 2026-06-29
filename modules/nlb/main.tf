# Discover EKS node group ASGs by cluster ownership tag
data "aws_autoscaling_groups" "eks_nodes" {
  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned"]
  }
}

# ── Network Load Balancer ──────────────────────────────────────────────────────

resource "aws_lb" "this" {
  name               = "${var.cluster_name}-nlb"
  load_balancer_type = "network"
  internal           = false
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true
}

# ── Target groups ──────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "http" {
  name        = "${var.cluster_name}-http"
  port        = var.traefik_nodeport_http
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = var.traefik_nodeport_http
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

resource "aws_lb_target_group" "https" {
  name        = "${var.cluster_name}-https"
  port        = var.traefik_nodeport_https
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = var.traefik_nodeport_https
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }
}

# ── Listeners ──────────────────────────────────────────────────────────────────

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# ── ASG → target group attachments ────────────────────────────────────────────

resource "aws_autoscaling_attachment" "http" {
  for_each               = toset(data.aws_autoscaling_groups.eks_nodes.names)
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.http.arn
}

resource "aws_autoscaling_attachment" "https" {
  for_each               = toset(data.aws_autoscaling_groups.eks_nodes.names)
  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.https.arn
}

# ── Node security group: allow internet traffic on NodePorts ──────────────────
# NLB with TCP listeners preserves the client source IP, so nodes must accept
# traffic directly from internet addresses, not just the VPC CIDR.

resource "aws_vpc_security_group_ingress_rule" "traefik_http" {
  security_group_id = var.node_security_group_id
  from_port         = var.traefik_nodeport_http
  to_port           = var.traefik_nodeport_http
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "NLB - Traefik HTTP NodePort"
}

resource "aws_vpc_security_group_ingress_rule" "traefik_https" {
  security_group_id = var.node_security_group_id
  from_port         = var.traefik_nodeport_https
  to_port           = var.traefik_nodeport_https
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "NLB - Traefik HTTPS NodePort"
}
