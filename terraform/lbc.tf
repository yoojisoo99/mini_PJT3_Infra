# AWS Load Balancer Controller를 위한 IAM 정책 생성
resource "aws_iam_policy" "lbc_policy" {
  name        = "${var.project_name}-lbc-policy"
  description = "AWS Load Balancer Controller Policy for EKS"
  
  # 같은 폴더에 생성된 iam_policy.json을 읽어옵니다.
  policy = file("${path.module}/iam_policy.json")
}

# IAM 역할 (IRSA) 생성
resource "aws_iam_role" "lbc_role" {
  name = "${var.project_name}-lbc-role"

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
          # eks.tf에 정의된 local.oidc_issuer를 재사용합니다.
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  # VPC와 EKS 클러스터가 완전히 생성된 후 실행되도록 보장
  depends_on = [aws_eks_cluster.main, aws_vpc.main]
}

# 정책을 역할에 연결
resource "aws_iam_role_policy_attachment" "lbc_attach" {
  role       = aws_iam_role.lbc_role.name
  policy_arn = aws_iam_policy.lbc_policy.arn
}

# Helm 설치 시 사용할 Role ARN을 출력
output "lbc_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.lbc_role.arn
}
