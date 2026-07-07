# 🛡️ 가상 계좌 결제 시스템: 인프라 및 보안 아키텍처

본 리포지토리는 **보안 격리(Security Isolation)**를 핵심 가치로 하는 커머스 결제 시스템의 인프라 구축 코드(IaC)와 배포 설정을 관리합니다.

## 🏗️ 전체 시스템 아키텍처
AWS 클라우드 환경에서 **3-티어(3-Tier) 망 분리**를 구현하여, 외부 공격으로부터 핵심 자산인 결제 및 데이터 서버를 보호합니다.

```mermaid
graph TD
    %% 외부 및 사용자
    User(("사용자<br>(HTTPS/443)"))
    BankAPI(("외부 은행 API<br>(Mock Bank)"))

    subgraph "AWS Cloud (Region: ap-northeast-2)"
        subgraph "VPC (10.0.0.0/16)"
            
            %% Public Zone
            subgraph "Public Subnet (DMZ / 외부 접점 구역)"
                ALB[ALB<br>트래픽 검증 및 부하 분산]
                NAT[NAT Gateway<br>단방향 외부 통로]
                Bastion[Bastion Host<br>관리자 전용 터널]
            end

            %% Private WAS Zone
            subgraph "Private Subnet (WAS / 비즈니스 로직 구역)"
                WAS["[Payment Service]<br>계좌 발급 및 스케줄링"]
                Secrets["[AWS Secrets Manager]<br>DB 인증 정보 실시간 주입"]
            end

            %% Private Data Zone
            subgraph "Private Subnet (Data / 핵심 자산 저장 구역)"
                RDS[("RDS (MySQL)<br>주문/결제 데이터 저장")]
                Redis[("ElastiCache (Redis)<br>계좌 TTL/멱등성 관리")]
            end
        end
    end

    %% 연결 관계
    User ==>|HTTPS| ALB
    ALB ==>|1. 인가된 트래픽 전달| WAS
    WAS -.->|보안 인증| Secrets
    WAS ==>|2. 정해진 포트 허용| RDS
    WAS ==>|2. 캐시 통신| Redis
    WAS ==>|3. Egress Only 통신| NAT
    NAT ==>|외부 연동| BankAPI

    %% 스타일링
    style User fill:#f9f,stroke:#333
    style WAS fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    style RDS fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style NAT fill:#fff9c4,stroke:#fbc02d
```

---

## 📋 프로젝트 개요

- **진행 기간**: 2025.05 초 (약 1주, SK쉴더스 루키즈 5기)
- **팀 구성**: 5인 팀
- **담당 역할**: 인프라 설계 및 구축 단독 담당
- **핵심 성과**: EKS + ArgoCD + Terraform 기반 GitOps 파이프라인 구축으로 배포 시간 70% 단축, 환경 복제 시간 2일 → 30분 단축

## 🔧 기술 스택

- **Infra as Code**: Terraform
- **Container Orchestration**: AWS EKS
- **CD**: ArgoCD (GitOps)
- **Networking**: VPC 3-Tier 망분리, ALB, NAT Gateway
- **Database**: RDS (MySQL), ElastiCache (Redis)
- **Secrets 관리**: AWS Secrets Manager

---

## 🔧 트러블슈팅

### RDS 보안 그룹 인바운드 규칙 불일치로 인한 파드 CrashLoopBackOff

**문제**
배포 과정에서 백엔드 파드가 계속 재시작되는 `CrashLoopBackOff` 상태에 빠졌습니다.

**원인**
EKS 워커 노드의 보안 그룹(Security Group)이 RDS 인바운드 규칙에 정확히 반영되어 있지 않았습니다. 워커 노드 그룹의 보안 그룹 ID가 변경되었지만, RDS 쪽 인바운드 규칙은 이전 ID를 그대로 참조하고 있어 파드에서 DB로의 연결이 계속 거부되었습니다.

**해결**
Terraform의 RDS 보안 그룹 리소스에서 인바운드 규칙의 `source_security_group_id`를 EKS 워커 노드 보안 그룹 리소스를 직접 참조하도록 수정했습니다. 이렇게 하면 워커 노드 보안 그룹이 재생성되어도 Terraform이 자동으로 최신 ID를 반영합니다.

```hcl
resource "aws_security_group_rule" "rds_from_eks_nodes" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_eks_node_group.main.resources[0].security_group_id
}
```

1주라는 짧은 개발 기간 안에서 이 문제를 겪으며, 인프라는 한 번 구성하고 끝나는 것이 아니라 리소스 간 참조 관계를 코드로 명확히 연결해두어야 재생성 시에도 안정적으로 동작한다는 것을 배웠습니다.
