# EKS에서 ALB 추가 및 sample test  

설치 참조 사이트: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/   

ALB Controller 설치 후 aws annotation을 추가한 Ingress를 적용해야 AWS에 ALB가 작성됨.   
Public Subnet에 ALB Controller 설치  
** AWS LBC는 nginx ingress controller 처럼 rewrite-target annotation이 없음.

### 사전 조건(Prereq)  
- 1.19 이상 클러스터의 경우 버전 2.4.0 이상을 사용하는 것이 좋다.  
  여기서는 2.4.1을 사용할 예정  
- 서로 다른 가용영역에 두개 이상의 서브넷이 존재해야 한다. AWS 로드 밸런서 컨트롤러는 각 가용 영역에서 서브넷을   
  하나씩 선택합니다. 가용 영역에서 태그가 지정된 서브넷이 여러 개 있는 경우 컨트롤러는 서브넷 ID가 사전 순으로  
  가장 먼저 표시되는 서브넷을 선택합니다. 각 서브넷에는 최소 8개의 사용 가능한 IP 주소가 있어야 합니다.  
  작업자 노드에 연결된 여러 보안 그룹을 사용하는 경우 정확히 하나의 보안 그룹에 다음과 같이 태그를 지정해야  
  합니다.  cluster-name을 클러스터 이름으로 교체합니다.    
  ○ 키 - kubernetes.io/cluster/cluster-name  
  ○ 값 - shared 또는 owned  
  eksctl로 cluster 작성 시 cluster wide security group에 위 항목이 설정되어 있다.  
```  
$ aws eks describe-cluster --name eksworkshop-eksctl --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text  
sg-xxxxxxxxxx    
$ aws ec2 describe-security-groups --group-ids sg-xxxxxxxxxx --query 'SecurityGroups[].Tags' --output text  
ws:eks:cluster-name    eksworkshop-eksctl  
Name    eks-cluster-sg-eksworkshop-eksctl-1769733817  
kubernetes.io/cluster/eksworkshop-eksctl        owned  
```  

- Controller version 2.1.1 이상인 경우에는 cluster subnet에 위 tag를 추가하는 것이 선택사항이지만, 향후 제어를  
  위해서 추가하는 것이 좋다.

eks cluster vpc id 추출  
```  
$ aws eks describe-cluster --name eksworkshop-eksctl --query 'cluster.resourcesVpcConfig.vpcId' --output text  
vpc-xxxxxxxxxx  
```  

cluster가 설치된 Public Subnet id 추출 및 확인  
```  
$ export PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxxxxxx" "Name=tag:Name,Values=*Public*" --query 'Subnets[].SubnetId' --output text)  

$ aws ec2 describe-subnets --subnet-ids ${PUBLIC_SUBNET_IDS}
```

cluster subnet에 tag 추가  
```
$ export CLUSTER_SUBNET_IDS=$(aws eks describe-cluster --name eksworkshop-eksctl --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

$ aws ec2 create-tags --resources ${CLUSTER_SUBNET_IDS} --tags 'Key="kubernetes.io/cluster/eksworkshop-eksctl",Value=owned'  
```  

- Public Subnet에 아래 annotation 추가  
  ○ 키: kubernetes.io/role/elb  
  ○ 값: 1
```  
$ aws ec2 create-tags --resources ${PUBLIC_SUBNET_IDS} --tags Key=kubernetes.io/role/elb,Value=1  
```  

### 고려사항  
- annotation kubernetes.io/ingress.class: alb 를 가진 ingress resource가 cluster상에 생성될 때마다, ALB  
  Controller는 ALB와 필요한 AWS자원을 생성한다. ingress resource는 ALB가 HTTP 또는 HTTP traffic을 클러스터  
  상의 pod로 route할 수 있도록 구성한다. ingress object가 AWS Load Balancer Controller(이하 LBC)를  
  사용하도록 보장하기 위하여 아래의 ingress rousrce spec에 아래 annotation을 추가해야 한다.  
```  
  annotations:
    kubernetes.io/ingress.class: alb
```  
  AWS LBC는 아래와 같은 traffic mode를 지원한다.
  ○ Instance: cluster내의 node를 ALB에 대한 target으로 등록한다. ALB에 도달하는 traffic는 service의 NodePort로  라우팅되고, Pod로 proxy된다. 이것이 default traffic mode이다.   
  explicitly alb.ingress.kubernetes.io/target-type: instance로 등록가능하다.   

  ○ IP: Pod를 ALB의 target으로 등록한다. traffic은 ALB에서 곧바로 Pod로 라우팅된다.  
  반드시 alb.ingress.kubernetes.io/target-type: ip annotaion을 등록해야 한다.  
  이 타입은 Fargate상에 Pod를 실행시킬 때 필요하다.

- controller에 의해 만들어진 ALBs에 tag하기 위해서, controller에 다음 annotaion을 추가한다.  
  alb.ingress.kubernetes.io/tags  

- IngressGroups를 사용하여 여러 서비스 리소스 간에 Application Load Balancer 공유  
  ingress를 group으로 join하기 위해, ingress resource spec에 다음 annotation을 추가한다.  
  
  alb.ingress.kubernetes.io/group.name: my-group  
  
  Controller가 자동으로 ingress rules를 동일 ingress group으로 merge한다. ingress에 정의된 대부분의  
  annotaion은 오직 그 ingress에 정의된 path에만 적용된다. 기본적으로 ingress resource는 어떤 ingress  
  group에도 속하지 않는다.  

  ingress resource의 order nubmber를 다음 annotaion을 이용하여 정할 수 있다.  
  alb.ingress.kubernetes.io/group.order: '10'  

  1~1000까지 numbering가능하고, 같은 ingress group에서 번호가 낮을 수록 먼저 평가된다. annotation을 추가하지  
  않을 경우 zero로 설정된다.  

### AWS Load Balacer Controller 설치  
IAM Permissions

#### Setup IAM role for service accounts  
1. Create IAM OIDC provider  
```  
eksctl utils associate-iam-oidc-provider \
    --region ap-northeast-2 \
    --cluster eksworkshop-eksctl \
    --approve
```  
2. Download IAM policy for the AWS Load Balancer Controller  
```
 curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.1/docs/install/iam_policy.json  
```

3. Create an IAM policy called AWSLoadBalancerControllerIAMPolicy  
```
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json  
```  
4. Create a IAM role and ServiceAccount for the AWS Load Balancer controller, use the ARN from the step above  
```  
eksctl create iamserviceaccount \
--cluster=eksworkshop-eksctl \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--attach-policy-arn=arn:aws:iam::<AWS_ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
--override-existing-serviceaccounts \
--region ap-northeast-2 \
--approve  
```

Add Controller to Cluster (Using Helm chart)  

1. Add the EKS chart repo to helm  
`helm repo add eks https://aws.github.io/eks-charts`  
2. Install the TargetGroupBinding CRDs if upgrading the chart via helm upgrade.  
`kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"`  
3. Install the helm chart if using IAM roles for service accounts   
`helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=eksworkshop-eksctl --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller `  


Deploy sample applicatin ( 2048 Game)
1. 2048 game yaml download & deploy (public)
`curl -o 2048_full.yaml https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.0/docs/examples/2048/2048_full.yaml`  

Verify AWS Load Balancer  
`aws elbv2 describe-load-balancers `  




