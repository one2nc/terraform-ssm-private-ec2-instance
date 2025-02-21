#!/bin/bash



export AWS_REGION=$REGION

# Get the instance ID using the provided name
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" --output text --region $REGION)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Error: Instance not found or not running."
    exit 1
fi

echo "Instance ID: $INSTANCE_ID"


aws ssm start-session --target $INSTANCE_ID
