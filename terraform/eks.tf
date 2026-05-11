# ────────────────────────────────────────────────────────────────────────────
# EKS 노드 보안 그룹
# ALB → 노드(NodePort), 노드 간 통신, 컨트롤 플레인 통신 제어
# ────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # 노드 간 전체 통신 허용 (클러스터 내부 Pod-to-Pod, CNI 등)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # 22번 포트 허용 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["sg-0fcfdf6de02bb46f5"]  # Bastion SG ID로 제한
  description     = "SSH from Bastion only"
  }

  # ALB에서 노드로의 트래픽 허용 (NodePort 범위: 30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidrs
    description = "ALB to NodePort"
  }

  # EKS 컨트롤 플레인 → 노드 kubelet 통신
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Control plane to kubelet"
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubelet API"
  }

  # 아웃바운드 전체 허용 (NAT GW를 통해 ECR pull, 외부 API 호출 등)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
  }
}

# ────────────────────────────────────────────────────────────────────────────
# EKS 클러스터 IAM 역할
# AmazonEKSClusterPolicy: EKS 컨트롤 플레인이 EC2·ELB 등 AWS 리소스를 관리하기 위해 필요
# ────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ────────────────────────────────────────────────────────────────────────────
# EKS 클러스터
# ────────────────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true  # VPC 내부에서 API 서버 접근 허용
    endpoint_public_access  = true  # kubectl 로컬 사용을 위해 퍼블릭도 허용
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# ────────────────────────────────────────────────────────────────────────────
# OIDC Provider (IRSA - IAM Roles for Service Accounts 사용에 필요)
# Pod가 IAM 역할을 직접 assume할 수 있게 해주는 인증 브릿지
# ────────────────────────────────────────────────────────────────────────────

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ────────────────────────────────────────────────────────────────────────────
# 백엔드 서비스 어카운트용 IAM 역할 (IRSA)
# 백엔드 Pod가 S3에 직접 접근하기 위해 사용
# ────────────────────────────────────────────────────────────────────────────

locals {
  oidc_issuer = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

# resource "aws_iam_role" "backend_sa" {
#   name = "${var.project_name}-backend-sa-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = {
#         Federated = aws_iam_openid_connect_provider.eks.arn
#       }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       Condition = {
#         StringLike = {
#           "${local.oidc_issuer}:sub" = "system:serviceaccount:sample-app:*"
#           "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
#         }
#       }
#     }]
#   })
# }

# resource "aws_iam_role_policy" "backend_s3" {
#   name = "${var.project_name}-backend-s3-policy"
#   role = aws_iam_role.backend_sa.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "s3:GetObject",
#         "s3:PutObject",
#         "s3:DeleteObject",
#         "s3:ListBucket"
#       ]
#       Resource = local.s3_bucket_arns # 실제 운영 환경에서는 특정 버킷 ARN으로 제한 권장
#     }]
#   })
# }

# ────────────────────────────────────────────────────────────────────────────
# 노드 그룹 IAM 역할
# AmazonEKSWorkerNodePolicy : 노드가 클러스터에 등록되고 통신하기 위해 필요
# AmazonEC2ContainerRegistryReadOnly : ECR에서 이미지를 pull하기 위해 필요
# AmazonEKS_CNI_Policy : VPC CNI 플러그인이 Pod IP를 할당하기 위해 필요
# ────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy" "node_s3" {
  name = "${var.project_name}-node-s3-policy"
  role = aws_iam_role.eks_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      # main.tf의 로컬 변수로 특정 버킷 ARN만 허용 (최소 권한 원칙)
      Resource = local.s3_bucket_arns
    }]
  })
}

# ────────────────────────────────────────────────────────────────────────────
# EKS 관리형 노드 그룹
# 프라이빗 서브넷에 워커 노드 배치 (보안상 권장)
# ────────────────────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id # 노드는 프라이빗 서브넷에 배치

  instance_types = [var.node_instance_type]
  ami_type       = "AL2_x86_64"
  version        = var.kubernetes_version

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1 # 롤링 업데이트 시 동시에 교체할 최대 노드 수
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]

  remote_access {
    ec2_ssh_key               = data.aws_key_pair.deployer.key_name
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }
}
