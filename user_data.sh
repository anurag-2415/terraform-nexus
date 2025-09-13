#!/bin/bash
sudo dnf update -y
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo yum install -y amazon-efs-utils
sudo usermod -aG docker ec2-user
docker pull amazon/amazon-ecs-agent:latest
docker run --name ecs-agent --detach \
  --restart=always \
  --volume=/var/run/docker.sock:/var/run/docker.sock \
  --volume=/var/log/ecs/:/log \
  --volume=/var/lib/ecs/data:/data \
  --net=host \
  --env=ECS_CLUSTER=demo-cluster \
  amazon/amazon-ecs-agent:latest  