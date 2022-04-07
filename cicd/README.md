### eks 1.21  
Jenkins 2.332.2 (jenkins/jenkins:jdk11)  
jenkins install ( find jenkins for k8s, follow eksworkshop )  
ref: https://artifacthub.io/packages/helm/jenkinsci/jenkins  


설치 시 pv가 필요하지만, default 설정 시 default storageclass를 사용한다고  
values.yaml에 나옴.
values.yaml  파일 수정 (plugin dependency, sa 수정)
