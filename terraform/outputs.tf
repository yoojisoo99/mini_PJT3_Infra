# ────────────────────────────────────────────────────────────────────────────
# Outputs
# terraform apply 완료 후 출력되는 값들
# kubectl, Helm, CI/CD 파이프라인에서 참조합니다.
# ────────────────────────────────────────────────────────────────────────────

# ── VPC ────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록 (ALB 배치)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (EKS 노드 배치)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "DB 서브넷 ID 목록 (RDS 배치)"
  value       = aws_subnet.database[*].id
}

# ── EKS ────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS 클러스터 이름 (kubectl config용)"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS API 서버 엔드포인트"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS 클러스터 CA 인증서 (kubeconfig에 사용)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_node_security_group_id" {
  description = "EKS 노드 보안 그룹 ID"
  value       = aws_security_group.eks_nodes.id
}

output "backend_sa_role_arn" {
  description = "백엔드 ServiceAccount IAM Role ARN (IRSA)"
  value       = aws_iam_role.backend_sa.arn
}

# kubeconfig 업데이트 명령어 안내
output "kubeconfig_update_command" {
  description = "로컬 kubeconfig 업데이트 명령어"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

# ── ECR ────────────────────────────────────────────────────────────────────

output "ecr_backend_repository_url" {
  description = "백엔드 ECR 레포지토리 URL (docker push 시 사용)"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_repository_url" {
  description = "프론트엔드 ECR 레포지토리 URL"
  value       = aws_ecr_repository.frontend.repository_url
}

# ECR 로그인 명령어 안내
output "ecr_login_command" {
  description = "ECR 도커 로그인 명령어"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.repository_url}"
}

# ── RDS ────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS 엔드포인트 (애플리케이션 DB 연결 주소)"
  value       = aws_db_instance.main.endpoint
}

output "rds_port" {
  description = "RDS 포트"
  value       = aws_db_instance.main.port
}

output "rds_database_name" {
  description = "RDS 초기 데이터베이스 이름"
  value       = aws_db_instance.main.db_name
}

# ── S3 ─────────────────────────────────────────────────────────────────────

output "s3_uploads_bucket_name" {
  description = "업로드 버킷 이름"
  value       = aws_s3_bucket.uploads.bucket
}

output "s3_uploads_bucket_arn" {
  description = "업로드 버킷 ARN (IAM 정책에서 참조)"
  value       = aws_s3_bucket.uploads.arn
}

output "s3_frontend_static_bucket_name" {
  description = "프론트엔드 정적 파일 버킷 이름"
  value       = aws_s3_bucket.frontend_static.bucket
}

output "s3_frontend_static_bucket_arn" {
  description = "프론트엔드 정적 파일 버킷 ARN"
  value       = aws_s3_bucket.frontend_static.arn
}

# ── LBC ────────────────────────────────────────────────────────────────────

# lbc_role_arn은 lbc.tf에 이미 output으로 정의되어 있습니다.
# Helm 설치 시 사용:
# helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
#   -n kube-system \
#   --set clusterName=<eks_cluster_name> \
#   --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<lbc_role_arn>
