# 첫 번째 인스턴스
resource "aws_instance" "public_server" {
  ami           = "ami-0d4c056a16f3ae150" # 팀원이 사용한 AMI ID
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[1].id # 실제 위치가 2a면 [0], 2c면 [1]
  vpc_security_group_ids = ["sg-0fcfdf6de02bb46f5"]
  key_name      = "my-bastion-key"
  
  tags = { Name = "Bastion-Jump-Host" }
}

# 두 번째 인스턴스
resource "aws_instance" "private_server" {
  ami           = "ami-0d4c056a16f3ae150" # 팀원이 사용한 AMI ID (같을 수도 있음)
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private[0].id
  vpc_security_group_ids = ["sg-057f09b2ce8c30ef5"]
  key_name      = "my-bastion-key"
  
  tags = { Name = "Team01-Backend-New" }
}