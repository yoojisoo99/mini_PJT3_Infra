# 1. RDS가 배치될 서브넷 그룹 정의 (2개 이상의 AZ에 걸친 DB 서브넷 사용)
resource "aws_db_subnet_group" "database" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# 2. RDS 보안 그룹 (문지기 설정)
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL traffic from EKS nodes only"
  vpc_id      = aws_vpc.main.id

  # 인바운드 규칙: WAS(EKS) 보안 그룹으로부터의 3306 포트만 허용
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
    description     = "MySQL from EKS nodes only" 
  }

  # 아웃바운드: RDS는 외부 인터넷으로 나갈 이유가 없으므로 VPC 내부로만 제한
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow outbound within VPC only"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# 3. RDS MySQL 인스턴스 생성
resource "aws_db_instance" "main" {
  allocated_storage      = 20
  max_allocated_storage  = 100 # 스토리지 오토스케일링
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class # variables.tf의 db.t3.micro 사용
  
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password # sensitive 변수 사용

  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  skip_final_snapshot    = true # 프로젝트 종료 후 삭제 편의를 위함
  multi_az               = false # 비용 절감을 위해 단일 AZ (운영 시 true 권장)
  publicly_accessible    = false # 외부 접근 차단 (보안 핵심)

  tags = {
    Name = "${var.project_name}-rds"
  }
}