# ────────────────────────────────────────────────────────────────────────────
# main.tf
# 프로젝트 전체에서 공유하는 로컬 변수와 데이터 소스를 정의합니다.
# 실제 리소스는 각 역할별 파일(vpc.tf, eks.tf, rds.tf 등)에 위치합니다.
# ────────────────────────────────────────────────────────────────────────────

# ── 공통 로컬 변수 ──────────────────────────────────────────────────────────

locals {
  # 리소스 이름에 공통으로 사용하는 prefix
  # ex) "sample-app-dev"
  name_prefix = "${var.project_name}-${var.environment}"

  # 공통 태그 (provider.tf의 default_tags에 더해 리소스별로 병합 가능)
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # S3 버킷 ARN 목록 (eks.tf의 IAM 정책에서 와일드카드 * 대신 사용)
  # s3.tf가 먼저 적용된 이후에 참조 가능
  s3_bucket_arns = [
    aws_s3_bucket.app.arn,
    "${aws_s3_bucket.app.arn}/*",
    # aws_s3_bucket.frontend_static.arn,
    # "${aws_s3_bucket.frontend_static.arn}/*",
  ]
}

# ── 현재 AWS 계정 정보 조회 ─────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ────────────────────────────────────────────────────────────────────────────
# [참고] terraform apply 순서 의존성 요약
#
#  provider.tf → variables.tf
#       ↓
#  vpc.tf          (VPC, 서브넷, IGW, NAT, 라우팅 테이블)
#       ↓
#  eks.tf          (IAM 역할, EKS 클러스터, OIDC, 노드 그룹, 보안 그룹)
#  rds.tf          (DB 서브넷 그룹, 보안 그룹, RDS 인스턴스)
#  ecr.tf          (ECR 레포지토리, 라이프사이클 정책)
#  s3.tf           (S3 버킷, 퍼블릭 차단, 암호화, 버전 관리)
#  lbc.tf          (LBC IAM 정책·역할·연결)
#       ↓
#  outputs.tf      (주요 리소스 ID·URL·ARN 출력)
# ────────────────────────────────────────────────────────────────────────────
