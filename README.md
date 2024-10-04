# AWS Python EBS Snapshots Recovery (IN PROGRESS)

<div align="center">
  <img src="screenshot/architecture.png" width=""/>
</div>

---

## Step 1: Set Up a VPC
#### 1.1. Create a VPC to house all the resources in a specific region.
```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
```

---

## Step 2: Create a Public Subnet
#### 2.1. Create a public subnet where the EC2 instances will be hosted.
```bash
aws ec2 create-subnet \
  --vpc-id <vpc-id> \
  --cidr-block 10.0.1.0/24 \
  --availability-zone <your-az>
```
Replace `<vpc-id>` with your VPC ID and `<your-az>` with the Availability Zone of your choice.

---

## Step 3: Create Security Groups
#### 3.1. Create a security group for the Command Host instance:
```bash
aws ec2 create-security-group \
  --group-name CommandHostSG \
  --description "Security group for Command Host"
```
Note the security group ID returned by this command. You will need it for launching the Command Host instance.

#### 3.2. Configure Inbound Rules for Command Host
Allow SSH access:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id <command-host-sg-id> \
  --protocol tcp \
  --port 22 \
  --cidr <your-ip>/32
```
Replace `<command-host-sg-id>` with your security group ID and `<your-ip>` with your local IP address.

#### 3.3. Create a security group for the Processor instance:
```bash
aws ec2 create-security-group \
  --group-name ProcessorSG \
  --description "Security group for Processor"
```
Note the security group ID returned by this command. You will need it for launching the Processor instance.

#### 3.4. Allow SSH access from the Command Host security group:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id <processor-sg-id> \
  --protocol tcp \
  --port 22 \
  --source-group <command-host-sg-id>
```
Replace `<processor-sg-id>` and `<command-host-sg-id>` with the respective security group IDs.

---

## Step 4: Launch Command Host EC2 Instance
#### 4.1. This EC2 instance will manage and control other resources in your infrastructure.
```bash
aws ec2 run-instances \
  --image-id ami-<your-ami-id> \
  --instance-type t2.micro \
  --key-name <your-key-pair> \
  --subnet-id <subnet-id> \
  --associate-public-ip-address \
  --security-group-ids <command-host-sg-id>
```
Replace `<your-ami-id>`, `<your-key-pair>`, and `<subnet-id>` with your own values.

---

## Step 5: Launch Processor EC2 Instance
#### 5.1. This EC2 instance will interact with the EBS volume for processing data.
```bash
aws ec2 run-instances \
  --image-id ami-<your-ami-id> \
  --instance-type t2.micro \
  --key-name <your-key-pair> \
  --subnet-id <subnet-id> \
  --security-group-ids <processor-sg-id>
```
Use the same AMI, key pair, and subnet as in the previous step.

---

## Step 6: Create an EBS Volume
#### 6.1. Create an EBS volume in the same availability zone as your instances.
```bash
aws ec2 create-volume \
  --size 8 \
  --region <region-name> \
  --availability-zone <your-az> \
  --volume-type gp2
```
Replace `<region-name>` and `<your-az>` with the appropriate region and Availability Zone.

---

## Step 7: Attach EBS Volume to Processor
#### 7.1. Attach the EBS volume to the processor EC2 instance.
```bash
aws ec2 attach-volume \
  --volume-id <volume-id> \
  --instance-id <instance-id> \
  --device /dev/sdf
```
Replace `<volume-id>` and `<instance-id>` with the volume and instance IDs from your setup.

---

## Step 8: Schedule Snapshot Creation
#### 8.1. Use CloudWatch Events to schedule the creation of snapshots every minute.
```bash
aws events put-rule \
  --schedule-expression "rate(1 minute)" \
  --name SnapshotScheduler
```
This command sets a rule to trigger a target (Lambda function) every minute.

---

## Step 9: Create a Lambda Function to Automate Snapshots
#### 9.1. Create a Lambda function that will take snapshots of your EBS volume.
```bash
aws lambda create-function \
  --function-name CreateSnapshot \
  --runtime python3.9 \
  --role <role-arn> \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://function.zip
```
You'll need to provide the role ARN and zip a Python file for the Lambda function.

---

## Step 10: Python Script to Delete Old Snapshots
#### 10.1. Use the following Python script with boto3 to delete old snapshots and retain only the latest two.
```python
import boto3
from operator import itemgetter

ec2 = boto3.client('ec2')

def delete_old_snapshots(volume_id):
    snapshots = ec2.describe_snapshots(Filters=[{'Name': 'volume-id', 'Values': [volume_id]}])['Snapshots']
    
    # Sort snapshots by date
    sorted_snapshots = sorted(snapshots, key=itemgetter('StartTime'), reverse=True)
    
    # Retain the two most recent snapshots
    snapshots_to_delete = sorted_snapshots[2:]
    
    for snapshot in snapshots_to_delete:
        snapshot_id = snapshot['SnapshotId']
        ec2.delete_snapshot(SnapshotId=snapshot_id)
        print(f"Deleted snapshot {snapshot_id}")

if __name__ == "__main__":
    delete_old_snapshots('<volume-id>')
```
Replace <volume-id> with your own volume ID in the Python script.
