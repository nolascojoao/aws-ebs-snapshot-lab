#!/bin/bash

set -e

echo

echo '
 /$$   /$$  /$$$$$$  /$$        /$$$$$$   /$$$$$$   /$$$$$$   /$$$$$$
| $$$ | $$ /$$__  $$| $$       /$$__  $$ /$$__  $$ /$$__  $$ /$$__  $$
| $$$$| $$| $$  \ $$| $$      | $$  \ $$| $$  \__/| $$  \__/| $$  \ $$
| $$ $$ $$| $$  | $$| $$      | $$$$$$$$|  $$$$$$ | $$      | $$  | $$
| $$  $$$$| $$  | $$| $$      | $$__  $$ \____  $$| $$      | $$  | $$
| $$\  $$$| $$  | $$| $$      | $$  | $$ /$$  \ $$| $$    $$| $$  | $$
| $$ \  $$|  $$$$$$/| $$$$$$$$| $$  | $$|  $$$$$$/|  $$$$$$/|  $$$$$$/
|__/  \__/ \______/ |________/|__/  |__/ \______/  \______/  \______/
'
echo

# Create VPC
echo "Creating VPC"
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --query 'Vpc.VpcId' \
  --output text)
echo "VPC created with ID: $VPC_ID"
echo

# Create Public Subnet
echo "Creating a public subnet"
PU_SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public Subnet}]' \
  --query 'Subnet.SubnetId' \
  --output text)
echo "Public Subnet created with ID: $PU_SUBNET_ID"
echo

# Create and Attach Internet Gateway
IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=IGW-01}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text) && \
  echo "Internet Gateway created with ID: $IGW" && \
  aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW \
  --vpc-id $VPC_ID && \
  echo "Internet Gateway $IGW attached to VPC $VPC_ID"
echo

# Create Public Route Table
PU_RTB=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public Route Table}]' \
  --query 'RouteTable.RouteTableId' \
  --output text) && \
  echo "Public Route Table created with ID: $PU_RTB" && \
  aws ec2 associate-route-table \
  --route-table-id $PU_RTB \
  --subnet-id $PU_SUBNET_ID && \
  echo "Public Route Table $PU_RTB associated with Subnet $PU_SUBNET_ID"
echo

# Create Security Groups
echo "Creating security group for Command Host instance..."
COMMAND_HOST_SG=$(aws ec2 create-security-group \
    --vpc-id $VPC_ID \
    --group-name CommandHostSG \
    --description "Security group for Command Host" \
    --query 'GroupId' \
    --output text)
echo "Security group for Command Host created with ID: $COMMAND_HOST_SG"

# Retrieve public IP address
PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)
echo "Public IP retrieved"

# Allow SSH access to the Command Host security group
echo "Authorizing SSH access for Command Host security group..."
aws ec2 authorize-security-group-ingress \
   --group-id $COMMAND_HOST_SG \
   --protocol tcp \
   --port 22 \
   --cidr ${PUBLIC_IP}/32
echo "SSH access authorized for Command Host security group."

# Create a security group for the Processor instance
echo "Creating security group for Processor instance..."
PROCESSOR_SG=$(aws ec2 create-security-group \
   --vpc-id $VPC_ID \
   --group-name ProcessorSG \
   --description "Security group for Processor" \
   --query 'GroupId' \
   --output text)
echo "Security group for Processor created with ID: $PROCESSOR_SG"

# Allow SSH access from the Command Host to the Processor security group
echo "Authorizing SSH access from Command Host to Processor security group..."
aws ec2 authorize-security-group-ingress \
  --group-id $PROCESSOR_SG \
  --protocol tcp \
  --port 22 \
  --source-group $COMMAND_HOST_SG
echo "SSH access authorized from Command Host to Processor security group."
echo

# Check if the key pair already exists
if aws ec2 describe-key-pairs \
  --key-names EC2-KEY &> /dev/null; then
  echo "Key pair 'EC2-KEY' already exists"
else
  echo "Creating key pair 'EC2-KEY'..."
  aws ec2 create-key-pair --key-name EC2-KEY --query 'KeyMaterial' --output text > EC2-KEY.pem
  echo "Key pair 'EC2-KEY' created and saved to EC2-KEY.pem"
  chmod 400 EC2-KEY.pem
fi


# Launch Command Host EC2 Instance
echo "Launching Command Host instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id ami-0ebfd941bbafe70c6 \
    --instance-type t2.micro \
    --key-name EC2-KEY \
    --subnet-id $PU_SUBNET_ID \
    --associate-public-ip-address \
    --security-group-ids $COMMAND_HOST_SG \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "Command Host instance launched with ID: $INSTANCE_ID"

# Optionally, you can wait for the instance to be in running state
echo "Waiting for the instance to be in running state..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "Instance $INSTANCE_ID is now running."


