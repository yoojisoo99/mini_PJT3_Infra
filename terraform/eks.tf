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

  # [아키텍처 반영] Bastion -> 노드: 관리용 SSH 22번 허용

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    security_groups = ["sg-0fcfdf6de02bb46f5"] # 기존 Bastion SG ID
    description     = "SSH Access via Bastion Host Only"
  }

  # ALB에서 노드로의 트래픽 허용 (NodePort 범위: 30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidrs
    description = "ALB to NodePort"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "ALB to backend pod direct"
  }

  # 프론트엔드가 80 포트를 사용한다면:
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow ALB to Frontend Pod direct"
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
# SecretsManager 접근 권한
resource "aws_iam_role" "eso_sa" {
  name = "${var.project_name}-eso-sa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:mini-project3:external-secrets-sa"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_secrets_manager" {
  name = "${var.project_name}-eso-secrets-policy"
  role = aws_iam_role.eso_sa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:ap-northeast-2:805400277714:secret:team01-mini-project3/backend-A3n7Uy"
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
# ────────────────────────────────────────────────────────────────────────────
# 프론트엔드 전용 노드 그룹
# ────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "frontend" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-frontend-node-group" # 이름으로 구분
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = ["t3.medium"] # 프론트엔드 사양
  
  labels = {
    role = "frontend" # 쿠버네티스 내부에서 프론트엔드 파드만 배치되도록 식별자 부여
  }

  scaling_config {
    # nodes_on이 false면 개수를 0으로 만들어 인스턴스를 삭제합니다.
    desired_size = var.nodes_on ? 1 : 0 
    min_size     = var.nodes_on ? 1 : 0
    max_size     = 2
  }

  # EC2 콘솔에서 'Name' 태그로 보이게 설정
  tags = {
    "Name" = "${var.project_name}-frontend-worker"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]

  remote_access {
    ec2_ssh_key               = "my-bastion-key" # ec2.tf에서 사용하는 키와 일치
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }
}

# ────────────────────────────────────────────────────────────────────────────
# 백엔드 전용 노드 그룹
# ────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "backend" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-backend-node-group" # 이름으로 구분
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = ["t3.medium"] # 백엔드 사양
  
  labels = {
    role = "backend" # 쿠버네티스 내부에서 백엔드 파드만 배치되도록 식별자 부여
  }

  scaling_config {
    # nodes_on이 false면 개수를 0으로 만들어 인스턴스를 삭제합니다.
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  tags = {
    "Name" = "${var.project_name}-backend-worker"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
    aws_iam_role_policy_attachment.eks_cni_policy,
  ]

  remote_access {
    ec2_ssh_key               = "my-bastion-key"
    source_security_group_ids = [aws_security_group.eks_nodes.id]
  }
}