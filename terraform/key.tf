# 팀원이 이미 생성한 공개키 정보를 테라폼에 등록
data "aws_key_pair" "deployer" {
  key_name = "my-bastion-key"  # AWS에 등록된 키페어 이름
}