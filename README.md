# AWS Python EBS Snapshots (IN PROGRESS)

<div align="center">
  <img src="screenshot/architecture.png" width=""/>
</div>

## Overview
This project is divided into two parts: 
- Part 1 focuses on setting up the architecture necessary to conduct the lab, including creating a VPC, subnets, and EC2 instances. 
- Part 2 automates the management of EBS snapshots, deletion of old snapshots, and syncing them with S3 for backup.

---

# Part 1: Architecture Preparation

---

## Step 1: Set Up a VPC
#### 1.1. Create a VPC to house all the resources in a specific region:
```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16
```

---

## Step 2: Create a Public Subnet
#### 2.1. Create a public subnet where the EC2 instances will be hosted:
```bash
aws ec2 create-subnet \
	--vpc-id <vpc-id> \
	--cidr-block 10.0.1.0/24 \
	--availability-zone <your-az>
```

---

## Step 3: Create Security Groups
#### 3.1. Create and configure a security group for the Command Host instance, allowing SSH access:
```bash
aws ec2 create-security-group \
	--group-name CommandHostSG \
	--description "Security group for Command Host"
```
```bash
aws ec2 authorize-security-group-ingress \
	--group-id <command-host-sg-id> \
	--protocol tcp \
	--port 22 \
	--cidr <your-ip>/32
```

#### 3.2. Create a security group for the Processor instance and allow SSH access from the Command Host:
```bash
aws ec2 create-security-group \
	--group-name ProcessorSG \
	--description "Security group for Processor"
```
```bash
aws ec2 authorize-security-group-ingress \
	--group-id <processor-sg-id> \
	--protocol tcp \
	--port 22 \
	--source-group <command-host-sg-id>
```

---

## Step 4: Launch Command Host EC2 Instance
#### 4.1. This instance will manage and control other resources:
```bash
aws ec2 run-instances \
	--image-id ami-<your-ami-id> \
	--instance-type t2.micro \
	--key-name <your-key-pair> \
	--subnet-id <subnet-id> \
	--associate-public-ip-address \
	--security-group-ids <command-host-sg-id>
```

---

## Step 5: Launch Processor EC2 Instance
#### 5.1. This instance will interact with the default EBS volume attached to it for processing data:
```bash
aws ec2 run-instances \
	--image-id ami-<your-ami-id> \
	--instance-type t2.micro \
	--key-name <your-key-pair> \
	--subnet-id <subnet-id> \
	--security-group-ids <processor-sg-id>
```

---

# Part 2: Automating EBS Snapshots and Syncing to S3

---

## Step 6: Schedule EBS snapshots to be taken every minute using cron.
	- 1. SSH into the Processor instance.
	- 2. Add the following cron job to create a snapshot every minute:
```bash
* * * * * aws ec2 create-snapshot --volume-id <volume-id> --description "Automated snapshot"
```

---

## Step 7: Stop Cron Job
#### 7.1. nce sufficient snapshots are created, stop the cron job by editing the cron configuration:
```bash
crontab -e
```

---

## Step 8: Python Script to Delete Old Snapshots
- Before running the cleanup script, let's list all the snapshots that have been taken to ensure we have proper control before stopping the cron job and deleting the old snapshots.

#### 8.1. List All Snapshots:
```bash
aws ec2 describe-snapshots --filters "Name=volume-id, Values=<VOLUME-ID>" --query 'Snapshots[*].SnapshotId'
```

#### 8.2. Python Script:
- Save the script below as snapshot_cleanup.py and execute it to delete the oldest snapshots, keeping only the two most recent ones:
```bash
#!/usr/bin/env python

import boto3

MAX_SNAPSHOTS = 2  # Number of snapshots to keep

# Create the EC2 resource
ec2 = boto3.resource('ec2')

# Get a list of all volumes
volume_iterator = ec2.volumes.all()

# Create a snapshot of each volume
for v in volume_iterator:
    v.create_snapshot()

    # Too many snapshots?
    snapshots = list(v.snapshots.all())
    if len(snapshots > MAX_SNAPSHOTS):
        # Delete oldest snapshots, but keep MAX_SNAPSHOTS available
        snap_sorted = sorted([(s.id, s.start_time, s) for s in snapshots], key=lambda k: k[1])
        for s in snap_sorted[:-MAX_SNAPSHOTS]:
            print("Deleting snapshot", s[0])
            s[2].delete()
```

---

## Step 9: Sync Snapshots with S3
#### 9.1. Create an S3 bucket and sync the snapshot data to the bucket:
```bash
aws s3api create-bucket --bucket <your-bucket-name> --region <your-region>
```
#### 9.2. Sync the snapshots to your bucket:
```bash
aws s3 sync /path/to/snapshot s3://<your-bucket-name>/
```



